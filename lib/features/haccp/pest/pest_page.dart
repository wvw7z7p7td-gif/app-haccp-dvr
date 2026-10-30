import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/operator_selector.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'pest_inspection_sheet.dart';
import 'pest_models.dart';
import 'pest_providers.dart';
import 'pest_station_sheet.dart';

final _dt = DateFormat('dd/MM/yyyy HH:mm');

class PestPage extends ConsumerWidget {
  const PestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(activeMembershipProvider);
    final canWrite = m?.role.canWrite ?? false;
    final isAdmin = m?.role.isAdmin ?? false;
    final data = ref.watch(pestDataProvider);
    final d = data.valueOrNull ?? PestData.empty;
    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: 'Controllo infestanti',
        bottom: TabBar(tabs: [
          const Tab(text: 'Postazioni'),
          const Tab(text: 'Controlli'),
          Tab(text: 'Rilievi aperti${d.openFindings.isEmpty ? '' : ' (${d.openFindings.length})'}'),
        ]),
        floatingActionButton: canWrite
            ? Builder(
                builder: (context) {
                  final tab = DefaultTabController.of(context);
                  return AnimatedBuilder(
                    animation: tab,
                    builder: (context, _) => tab.index == 0
                        ? FloatingActionButton.extended(
                            onPressed: () => showPestStationSheet(context, isAdmin: isAdmin),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Nuova postazione'),
                          )
                        : FloatingActionButton.extended(
                            onPressed: () => showPestInspectionSheet(context, d),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Nuovo controllo'),
                          ),
                  );
                },
              )
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare i dati.'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => ref.invalidate(pestDataProvider), child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _StationsTab(data: d, isAdmin: isAdmin),
            _InspectionsTab(data: d),
            _FindingsTab(data: d, canWrite: canWrite),
          ]),
        ),
      ),
    );
  }
}

class _StationsTab extends StatelessWidget {
  const _StationsTab({required this.data, required this.isAdmin});
  final PestData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (data.stations.isEmpty) {
      return const Center(child: Text('Nessuna postazione. Aggiungi esche, trappole e lampade UV.'));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.stations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = data.stations[i];
        return ListTile(
          leading: Icon(
            s.overdue ? Icons.schedule : Icons.check_circle_outline,
            color: s.overdue ? cs.error : null,
          ),
          title: Text('${s.code} · ${s.kind.label}${s.active ? '' : ' (disattivata)'}'),
          subtitle: Text([
            if (s.location != null) s.location!,
            s.lastInspectedAt == null
                ? 'mai controllata'
                : 'ultimo controllo ${_dt.format(s.lastInspectedAt!)}',
            'ogni ${s.checkEveryDays} gg',
          ].join(' · ')),
          trailing: s.overdue
              ? Text('In ritardo', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))
              : (s.lastStatus != null && s.lastStatus != FindingStatus.ok
                  ? Text(s.lastStatus!.label, style: TextStyle(color: cs.error))
                  : null),
          onTap: () => showPestStationSheet(context, existing: s, isAdmin: isAdmin),
        );
      },
    );
  }
}

class _InspectionsTab extends StatelessWidget {
  const _InspectionsTab({required this.data});
  final PestData data;

  @override
  Widget build(BuildContext context) {
    if (data.inspections.isEmpty) {
      return const Center(child: Text('Nessun controllo negli ultimi 6 mesi.'));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.inspections.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = data.inspections[i];
        return ListTile(
          leading: Icon(n.kind == InspectionKind.external ? Icons.business : Icons.person_outline),
          title: Text(n.kind == InspectionKind.external
              ? 'Servizio esterno · ${n.providerName ?? ''}'
              : 'Controllo interno'),
          subtitle: Text([
            _dt.format(n.inspectedAt),
            if (n.operatorName != null) n.operatorName!,
            '${n.items.length} postazioni',
          ].join(' · ')),
          trailing: n.findings > 0
              ? Text('${n.findings} rilievi', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))
              : const Icon(Icons.check, size: 18),
          onTap: () => _showInspection(context, n, data),
        );
      },
    );
  }
}

void _showInspection(BuildContext context, PestInspection n, PestData data) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_dt.format(n.inspectedAt), style: Theme.of(ctx).textTheme.titleLarge),
        if (n.providerName != null) Text(n.providerName!),
        if (n.notes != null) Text(n.notes!),
        const Divider(height: 24),
        for (final i in n.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(data.stations.where((s) => s.id == i.stationId).firstOrNull?.code ?? '—'),
            subtitle: Text([
              i.status.label,
              if (i.catchCount != null) '${i.catchCount} catture',
              if (i.notes != null) i.notes!,
              for (final a in i.actions) 'Azione: $a',
            ].join(' · ')),
          ),
      ]),
    ),
  );
}

class _FindingsTab extends ConsumerWidget {
  const _FindingsTab({required this.data, required this.canWrite});
  final PestData data;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = data.openFindings;
    if (open.isEmpty) return const Center(child: Text('Nessun rilievo in attesa di azione correttiva.'));
    return ListView.separated(
      itemCount: open.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = open[i];
        return ListTile(
          leading: Icon(Icons.bug_report_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('${f.station?.code ?? '—'} · ${f.item.status.label}'),
          subtitle: Text('${_dt.format(f.inspection.inspectedAt)} · ${f.item.notes ?? ''}'),
          trailing: canWrite ? const Icon(Icons.chevron_right) : null,
          onTap: canWrite ? () => _recordAction(context, f.item) : null,
        );
      },
    );
  }
}

Future<void> _recordAction(BuildContext context, PestItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ActionSheet(item: item),
  );
}

class _ActionSheet extends ConsumerStatefulWidget {
  const _ActionSheet({required this.item});
  final PestItem item;
  @override
  ConsumerState<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends ConsumerState<_ActionSheet> {
  final _id = const Uuid().v4();
  late final DateTime _at = DateTime.now();
  final _action = TextEditingController();
  final _op = OperatorSelection();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_action.text.trim().isEmpty) {
      setState(() => _error = 'Descrivi l\'azione correttiva.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opError = await verifyOperator(ref, _op);
      if (opError != null) {
        setState(() => _error = opError);
        return;
      }
      await ref.read(pestRepoProvider)!.saveAction(
            id: _id,
            itemId: widget.item.id,
            action: _action.text,
            performedAt: _at,
            employeeId: _op.employee?.id,
          );
      ref.invalidate(pestDataProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Azione NON salvata. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Azione correttiva', style: t.textTheme.titleLarge),
          Text('${widget.item.status.label}: ${widget.item.notes ?? ''}'),
          const SizedBox(height: 12),
          TextField(
            controller: _action,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Cosa e\' stato fatto',
              helperText: 'Es. esca sostituita, contattata la ditta, pulizia straordinaria.',
            ),
          ),
          const SizedBox(height: 12),
          OperatorSelector(selection: _op),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Registra azione')),
        ]),
      ),
    );
  }
}
