import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/master_detail.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'control_point_sheet.dart';
import 'corrective_action_sheet.dart';
import 'reading_sheet.dart';
import 'temp_chart.dart';
import 'temperature_models.dart';
import 'temperature_providers.dart';

class TemperaturePage extends ConsumerWidget {
  const TemperaturePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(tempOverviewProvider);
    final role = ref.watch(activeMembershipProvider)?.role;

    return PageScaffold(
      title: 'Temperature',
      floatingActionButton: role?.isAdmin == true
          ? FloatingActionButton.extended(
              onPressed: () => showControlPointSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Punto di controllo'),
            )
          : null,
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Impossibile caricare i punti di controllo.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => ref.invalidate(tempOverviewProvider),
                child: const Text('Riprova')),
          ]),
        ),
        data: (o) => Column(
          children: [
            _SummaryBar(overview: o),
            const Divider(height: 1),
            Expanded(
              child: MasterDetail<ControlPoint>(
                items: o.points,
                emptyLabel: role?.isAdmin == true
                    ? 'Nessun punto di controllo.\nCreane uno con il pulsante in basso.'
                    : 'Nessun punto di controllo configurato.',
                placeholder: 'Seleziona un punto di controllo',
                titleOf: (p) => p.name,
                subtitleOf: (p) => _subtitle(p, o),
                leadingOf: (p) => Icon(
                  p.kind.icon,
                  color: (o.openDeviations[p.id] ?? 0) > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                detailBuilder: (ctx, p) => ControlPointDetail(point: p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(ControlPoint p, TempOverview o) {
    final done = o.todayCount[p.id] ?? 0;
    final last = o.lastToday[p.id];
    final open = o.openDeviations[p.id] ?? 0;
    final parts = <String>[
      '$done/${p.readingsPerDay} oggi',
      if (last != null) 'ultima ${formatTemp(last.valueC)}',
      if (open > 0) '$open scostament${open == 1 ? 'o' : 'i'} da gestire',
    ];
    return parts.join(' · ');
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.overview});
  final TempOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final open = overview.totalOpenDeviations;
    return Container(
      color: open > 0 ? cs.errorContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(open > 0 ? Icons.warning_amber : Icons.check_circle_outline,
            color: open > 0 ? cs.onErrorContainer : cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            open > 0
                ? '$open scostament${open == 1 ? 'o' : 'i'} senza azione correttiva'
                : 'Oggi: ${overview.doneToday}/${overview.expectedToday} rilevazioni',
            style: TextStyle(color: open > 0 ? cs.onErrorContainer : null),
          ),
        ),
        IconButton(
          tooltip: 'Aggiorna',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(tempOverviewProvider),
        ),
      ]),
    );
  }
}

class ControlPointDetail extends ConsumerWidget {
  const ControlPointDetail({super.key, required ControlPoint point}) : _initial = point;
  final ControlPoint _initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final role = ref.watch(activeMembershipProvider)?.role;
    final overview = ref.watch(tempOverviewProvider).valueOrNull;
    // Versione piu' recente del punto (es. dopo una modifica dei limiti).
    final point =
        overview?.points.where((p) => p.id == _initial.id).firstOrNull ?? _initial;
    final history = ref.watch(tempHistoryProvider(point.id));
    final done = overview?.todayCount[point.id] ?? 0;
    final fmt = DateFormat('dd/MM HH:mm', 'it_IT');

    Future<void> newReading() async {
      final r = await showReadingSheet(context, point);
      if (r == null || !r.outOfRange || !context.mounted) return;
      final retest = await showCorrectiveActionSheet(context, point: point, reading: r);
      if (retest == true && context.mounted) {
        final again = await showReadingSheet(context, point);
        if (again != null && again.outOfRange && context.mounted) {
          await showCorrectiveActionSheet(context, point: point, reading: again);
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(point.kind.icon, size: 40, color: t.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(point.name, style: t.textTheme.titleLarge),
              Text('${point.kind.label} · limiti ${point.rangeLabel}'),
              Text('Oggi: $done/${point.readingsPerDay} rilevazioni'),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (role?.canWrite == true)
            FilledButton.icon(
              onPressed: newReading,
              icon: const Icon(Icons.add_task),
              label: const Text('Nuova rilevazione'),
            ),
          if (role?.isAdmin == true)
            OutlinedButton.icon(
              onPressed: () => showControlPointSheet(context, existing: point),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifica'),
            ),
        ]),
        const SizedBox(height: 24),
        Text('Andamento', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        history.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const Text('Storico non disponibile.'),
          data: (h) {
            final chronological = h.readings.reversed.toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TempChart(readings: chronological, minC: point.minC, maxC: point.maxC),
              const SizedBox(height: 16),
              Text('Storico (ultime ${h.readings.length})', style: t.textTheme.titleMedium),
              if (h.readings.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nessuna rilevazione registrata.'),
              ),
              for (final r in h.readings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(formatTemp(r.valueC),
                      style: t.textTheme.titleMedium?.copyWith(
                          color: r.outOfRange ? t.colorScheme.error : null)),
                  subtitle: Text([
                    fmt.format(r.measuredAt),
                    if (r.notes != null) r.notes!,
                  ].join(' · ')),
                  trailing: !r.outOfRange
                      ? null
                      : h.withAction.contains(r.id)
                          ? const Chip(label: Text('Azione registrata'))
                          : (role?.canWrite == true
                              ? TextButton(
                                  onPressed: () => showCorrectiveActionSheet(
                                      context, point: point, reading: r),
                                  child: const Text('Registra azione'),
                                )
                              : const Chip(label: Text('Da gestire'))),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
