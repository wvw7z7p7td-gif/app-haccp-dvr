import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../alerts/alert_models.dart';
import '../haccp/menu/menu_models.dart';
import '../haccp/receiving/receiving_models.dart';
import '../safety/incidents/incident_models.dart';

/// Tabella generica di un report.
class ReportTable {
  const ReportTable({required this.title, required this.headers, required this.rows, this.note});
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final String? note;
}

/// I font PDF standard coprono solo Latin-1/WinAnsi: normalizza i caratteri fuori set.
String pdfSafe(String s) => s
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('…', '...')
    .replaceAll('’', "'")
    .replaceAll('‘', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('•', '-')
    .replaceAll('≥', '>=')
    .replaceAll('≤', '<=')
    .replaceAll(RegExp(r'[^\u0000-ÿ]'), '?');

/// Impronta SHA-256 del contenuto, stampata nel piede: permette di verificare che
/// la copia cartacea corrisponda ai dati esportati.
String reportFingerprint(String title, List<ReportTable> tables) {
  final b = StringBuffer(title);
  for (final t in tables) {
    b
      ..write('|')
      ..write(t.title)
      ..write(t.headers.join(';'));
    for (final r in t.rows) {
      b
        ..write('\n')
        ..write(r.join(';'));
    }
  }
  return sha256.convert(utf8.encode(b.toString())).toString();
}

Future<Uint8List> buildReportPdf({
  required String company,
  required String title,
  required String period,
  required List<ReportTable> tables,
  required DateTime generatedAt,
}) async {
  final doc = pw.Document(title: pdfSafe(title), author: pdfSafe(company));
  final stamp = DateFormat('dd/MM/yyyy HH:mm').format(generatedAt);
  final fp = reportFingerprint(title, tables).substring(0, 16);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (c) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(pdfSafe(company), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(pdfSafe(title)),
      ]),
    ),
    footer: (c) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Generato il $stamp - impronta $fp', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('Pagina ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
      ]),
    ),
    build: (c) => [
      pw.Text(pdfSafe(title), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(pdfSafe(period)),
      pw.SizedBox(height: 12),
      for (final t in tables) ...[
        pw.Text(pdfSafe(t.title), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        if (t.rows.isEmpty)
          pw.Text('Nessun dato nel periodo.')
        else
          pw.TableHelper.fromTextArray(
            headers: [for (final h in t.headers) pdfSafe(h)],
            data: [
              for (final r in t.rows) [for (final v in r) pdfSafe(v)]
            ],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(width: 0.3),
          ),
        if (t.note != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(pdfSafe(t.note!), style: const pw.TextStyle(fontSize: 8))),
        pw.SizedBox(height: 14),
      ],
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------
// Adattatori puri: dati dell'app -> tabelle
// ---------------------------------------------------------------------
final _d = DateFormat('dd/MM/yyyy');
final _dt = DateFormat('dd/MM/yyyy HH:mm');

ReportTable receivingTable(List<GoodsReceipt> receipts, DateTime from, DateTime to) {
  final rows = <List<String>>[];
  final sorted = receipts.where((r) => !r.receivedAt.isBefore(from) && r.receivedAt.isBefore(to)).toList()
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  for (final r in sorted) {
    for (final l in r.lines) {
      rows.add([
        _dt.format(r.receivedAt),
        r.supplierName,
        r.docNumber ?? '',
        l.productName,
        l.lotCode ?? '',
        l.expiry == null ? '' : _d.format(l.expiry!),
        l.tempC == null ? '' : l.tempC!.toStringAsFixed(1),
        l.outcome.label,
        r.operatorName ?? '',
      ]);
    }
  }
  return ReportTable(
    title: 'Registro ricevimento merci e lotti',
    headers: const ['Data', 'Fornitore', 'DDT', 'Prodotto', 'Lotto', 'Scad.', 'T C', 'Esito', 'Operatore'],
    rows: rows,
  );
}

ReportTable allergenTable(MenuData menu) {
  final active = menu.items.where((i) => i.active).toList()..sort((a, b) => a.name.compareTo(b.name));
  String names(Set<String> ids) =>
      ids.map((id) => menu.allergen(id)?.name ?? '').where((n) => n.isNotEmpty).join(', ');
  return ReportTable(
    title: 'Allergeni per piatto (Reg. UE 1169/2011)',
    headers: const ['Piatto', 'Contiene', 'Tracce', 'Revisione'],
    rows: [
      for (final i in active)
        [
          i.name,
          names(i.contains).isEmpty ? 'nessuno' : names(i.contains),
          names(i.traces),
          i.reviewedAt == null ? 'DA VERIFICARE' : _d.format(i.reviewedAt!),
        ]
    ],
    note: 'Le informazioni sugli allergeni devono essere aggiornate a ogni variazione di ricetta o fornitore.',
  );
}

ReportTable incidentsTable(List<Incident> incidents, DateTime from, DateTime to) {
  final list = incidents.where((i) => !i.occurredAt.isBefore(from) && i.occurredAt.isBefore(to)).toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  return ReportTable(
    title: 'Registro infortuni e quasi incidenti',
    headers: const ['Data', 'Tipo', 'Descrizione', 'Persona', 'Gravita', 'Giorni', 'INAIL', 'Stato'],
    rows: [
      for (final i in list)
        [
          _dt.format(i.occurredAt),
          i.kind.label,
          i.description,
          i.employeeName ?? '',
          i.kind == IncidentKind.injury ? i.severity.label : '',
          i.daysLost > 0 ? '${i.daysLost}' : '',
          i.inailRequired ? (i.has(IncidentStep.inailReport) ? 'registrata' : 'DA FARE') : '',
          i.closed ? 'chiuso' : 'aperto',
        ]
    ],
  );
}

ReportTable alertsTable(List<AppAlert> alerts) => ReportTable(
      title: 'Scadenze e criticita aperte',
      headers: const ['Livello', 'Voce', 'Dettaglio'],
      rows: [
        for (final a in alerts)
          [
            switch (a.severity) {
              AlertSeverity.critical => 'Urgente',
              AlertSeverity.warning => 'Attenzione',
              AlertSeverity.info => 'Info',
            },
            a.title,
            a.detail,
          ]
      ],
    );
