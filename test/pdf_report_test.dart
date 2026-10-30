import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/reports/pdf_report.dart';

void main() {
  const t = ReportTable(title: 'T', headers: ['A', 'B'], rows: [
    ['uno', 'due'],
    ['è', '—'],
  ]);

  test('pdfSafe sostituisce i caratteri fuori Latin-1', () {
    expect(pdfSafe('a—b…'), 'a-b...');
    expect(pdfSafe('caffè'), 'caffè');
    expect(pdfSafe('中'), '?');
  });

  test('impronta deterministica e sensibile ai dati', () {
    final a = reportFingerprint('x', [t]);
    expect(reportFingerprint('x', [t]), a);
    const t2 = ReportTable(title: 'T', headers: ['A', 'B'], rows: [
      ['uno', 'due'],
      ['è', '-'],
    ]);
    expect(reportFingerprint('x', [t2]), isNot(a));
    expect(a.length, 64);
  });

  test('genera un PDF valido', () async {
    final bytes = await buildReportPdf(
      company: 'Bar Prova',
      title: 'Registro',
      period: 'Periodo',
      tables: [t, const ReportTable(title: 'Vuota', headers: ['A'], rows: [])],
      generatedAt: DateTime(2026, 10, 30, 12),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });
}
