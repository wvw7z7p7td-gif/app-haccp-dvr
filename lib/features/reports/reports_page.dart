import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/providers.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../alerts/alert_providers.dart';
import '../haccp/menu/menu_providers.dart';
import '../haccp/receiving/receiving_providers.dart';
import '../safety/incidents/incident_providers.dart';
import 'pdf_report.dart';

enum _Report { receiving, allergens, incidents, deadlines }

/// Esportazione PDF dei registri per periodo (modalita' ispezione).
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _days = 90;
  _Report? _busy;
  String? _error;

  Future<void> _generate(_Report r) async {
    setState(() {
      _busy = r;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: _days));
      final to = now.add(const Duration(minutes: 1));
      final company = ref.read(activeMembershipProvider)?.companyName ?? 'Azienda';
      final fmt = DateFormat('dd/MM/yyyy');
      final period = 'Periodo: ${fmt.format(from)} - ${fmt.format(now)}';
      late final String title;
      late final List<ReportTable> tables;
      switch (r) {
        case _Report.receiving:
          final d = await ref.read(receivingDataProvider.future);
          title = 'Registro merci e rintracciabilita';
          tables = [receivingTable(d.receipts, from, to)];
        case _Report.allergens:
          final d = await ref.read(menuDataProvider.future);
          title = 'Scheda allergeni';
          tables = [allergenTable(d)];
        case _Report.incidents:
          final d = await ref.read(incidentDataProvider.future);
          title = 'Registro infortuni e quasi incidenti';
          tables = [incidentsTable(d.incidents, from, to)];
        case _Report.deadlines:
          title = 'Scadenze e criticita aperte';
          tables = [alertsTable(ref.read(alertsProvider))];
      }
      final Uint8List bytes = await buildReportPdf(
        company: company,
        title: title,
        period: period,
        tables: tables,
        generatedAt: now,
      );
      await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
    } catch (_) {
      setState(() => _error = 'Impossibile generare il PDF. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(_Report r, IconData icon, String title, String sub) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
          trailing: _busy == r
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined),
          onTap: _busy == null ? () => _generate(r) : null,
        );
    return PageScaffold(
      title: 'Report',
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 30, label: Text('30 gg')),
              ButtonSegment(value: 90, label: Text('90 gg')),
              ButtonSegment(value: 365, label: Text('12 mesi')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
        ),
        tile(_Report.receiving, Icons.local_shipping_outlined, 'Merci e lotti', 'Ricevimenti, lotti, scadenze, temperature'),
        tile(_Report.allergens, Icons.restaurant_menu, 'Scheda allergeni', 'Piatti attivi (non dipende dal periodo)'),
        tile(_Report.incidents, Icons.healing_outlined, 'Infortuni e quasi incidenti', 'Registro con stato INAIL'),
        tile(_Report.deadlines, Icons.notifications_active_outlined, 'Scadenze e criticita', 'Stato attuale (non dipende dal periodo)'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ]),
    );
  }
}
