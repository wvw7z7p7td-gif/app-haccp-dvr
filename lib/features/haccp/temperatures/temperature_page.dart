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

/// "2/3 oggi"; se ne sono state fatte piu' del previsto: "4 oggi (3 previste)".
String todayLabel(int done, int planned) =>
    done > planned ? '$done oggi ($planned previste)' : '$done/$planned oggi';

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
            _Header(overview: o),
            Expanded(
              child: MasterDetail<ControlPoint>(
                items: ([...o.points]..sort((a, b) => a.kind.index.compareTo(b.kind.index))),
                sectionOf: (p) => p.kind.sectionLabel,
                itemBuilder: (ctx, p, selected, open) => _PointCard(
                  point: p,
                  overview: o,
                  selected: selected,
                  canWrite: role?.canWrite ?? false,
                  onOpen: open,
                ),
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
      todayLabel(done, p.readingsPerDay),
      if (last != null) 'ultima ${formatTemp(last.valueC)}',
      if (open > 0) '$open scostament${open == 1 ? 'o' : 'i'} da gestire',
    ];
    return parts.join(' · ');
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.overview});
  final TempOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final open = overview.totalOpenDeviations;
    final date = DateFormat("EEEE, d MMMM y", 'it_IT').format(DateTime.now());
    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Registro Temperature HACCP',
                style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(toBeginningOfSentenceCase(date) ?? date,
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 6),
            Text(
              open > 0
                  ? '$open scostament${open == 1 ? 'o' : 'i'} senza azione correttiva'
                  : 'Oggi: ${overview.doneToday}/${overview.expectedToday} rilevazioni',
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: open > 0 ? cs.error : cs.primary),
            ),
          ]),
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

class _PointCard extends ConsumerWidget {
  const _PointCard({
    required this.point,
    required this.overview,
    required this.selected,
    required this.canWrite,
    required this.onOpen,
  });
  final ControlPoint point;
  final TempOverview overview;
  final bool selected;
  final bool canWrite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final done = overview.todayCount[point.id] ?? 0;
    final last = overview.lastToday[point.id];
    final open = overview.openDeviations[point.id] ?? 0;
    final alert = open > 0 || (last?.outOfRange ?? false);
    final fmt = DateFormat('HH:mm', 'it_IT');

    Future<void> record({bool photo = false}) async {
      final r = await showReadingSheet(context, point, startWithPhoto: photo);
      if (r == null || !r.outOfRange || !context.mounted) return;
      await showCorrectiveActionSheet(context, point: point, reading: r);
    }

    return Material(
      color: cs.surface,
      elevation: 1.5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? cs.primary : (alert ? cs.error : Colors.transparent),
              width: selected || alert ? 2 : 0,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(point.name,
                    style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (canWrite) ...[
                IconButton(
                  tooltip: 'Foto a testimonianza',
                  icon: const Icon(Icons.photo_camera, size: 26),
                  onPressed: () => record(photo: true),
                ),
                IconButton(
                  tooltip: 'Registra temperatura',
                  icon: const Icon(Icons.edit_note, size: 28),
                  onPressed: record,
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Text(
                  last == null ? '--' : formatTemp(last.valueC),
                  style: t.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: alert ? cs.error : cs.onSurface),
                ),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(todayLabel(done, point.readingsPerDay), style: t.textTheme.bodyMedium),
                  if (last != null)
                    Text('alle ${fmt.format(last.measuredAt.toLocal())}',
                        style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  if (open > 0)
                    Text('$open da gestire',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: cs.error, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
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
              Text('Oggi: ${todayLabel(done, point.readingsPerDay)}'),
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
                  leading: r.photoPath == null
                      ? null
                      : IconButton(
                          tooltip: 'Vedi foto',
                          icon: const Icon(Icons.photo_camera_outlined),
                          onPressed: () => _showPhoto(context, ref, r.photoPath!),
                        ),
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

Future<void> _showPhoto(BuildContext context, WidgetRef ref, String path) async {
  final url = await ref.read(temperatureRepoProvider)?.photoUrl(path);
  if (url == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
    ),
  );
}
