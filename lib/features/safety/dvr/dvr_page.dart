import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/data/site_repository.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'dvr_models.dart';
import 'dvr_providers.dart';
import 'dvr_risk_sheet.dart';

final _d = DateFormat('dd/MM/yyyy');

class DvrPage extends ConsumerWidget {
  const DvrPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(dvrDataProvider);
    final d = data.valueOrNull ?? DvrData.empty;
    return DefaultTabController(
      length: 4,
      child: PageScaffold(
        title: 'DVR - Valutazione dei rischi',
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Rischi'),
          Tab(text: 'Azioni'),
          Tab(text: 'Figure'),
          Tab(text: 'Versioni'),
        ]),
        floatingActionButton: isAdmin
            ? Builder(builder: (context) {
                final tab = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tab,
                  builder: (context, _) => switch (tab.index) {
                    0 => FloatingActionButton.extended(
                        onPressed: () => showRiskSheet(context, d),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuovo rischio')),
                    2 => FloatingActionButton.extended(
                        onPressed: () => _officerDialog(context, ref),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Nuova figura')),
                    3 => FloatingActionButton.extended(
                        onPressed: () => _draftDialog(context, ref),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Nuova bozza')),
                    _ => const SizedBox.shrink(),
                  },
                );
              })
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare il DVR.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(dvrDataProvider), child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _RisksTab(data: d, isAdmin: isAdmin),
            _ActionsTab(data: d, isAdmin: isAdmin),
            _OfficersTab(data: d, isAdmin: isAdmin),
            _VersionsTab(data: d, isAdmin: isAdmin),
          ]),
        ),
      ),
    );
  }
}

class _RisksTab extends StatelessWidget {
  const _RisksTab({required this.data, required this.isAdmin});
  final DvrData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.risks.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nessun rischio valutato. Parti dai pericoli tipici: tagli, ustioni, scivolamenti, movimentazione carichi, incendio…',
            textAlign: TextAlign.center),
      ));
    }
    final counts = data.countByLevel;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, children: [
          for (final l in RiskLevel.values.reversed)
            Chip(
              side: BorderSide.none,
              backgroundColor: levelColor(cs, l).withValues(alpha: 0.15),
              label: Text('${l.label}: ${counts[l]}', style: TextStyle(color: levelColor(cs, l))),
            ),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: data.risks.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = data.risks[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: levelColor(cs, r.level).withValues(alpha: 0.18),
                child: Text('${r.score}',
                    style: TextStyle(color: levelColor(cs, r.level), fontWeight: FontWeight.w700)),
              ),
              title: Text(r.title),
              subtitle: Text([
                r.hazardName,
                if (r.areaName != null) r.areaName!,
                if (r.jobRoleName != null) r.jobRoleName!,
                if (r.residualLevel != null) 'residuo ${r.residualLevel!.label.toLowerCase()}',
                if (r.openActions > 0) '${r.openActions} azioni aperte',
              ].join(' · ')),
              trailing: r.needsAttention
                  ? Icon(Icons.warning_amber_rounded, color: cs.error)
                  : null,
              onTap: isAdmin ? () => showRiskSheet(context, data, existing: r) : null,
            );
          },
        ),
      ),
    ]);
  }
}

class _ActionsTab extends ConsumerWidget {
  const _ActionsTab({required this.data, required this.isAdmin});
  final DvrData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final rows = [
      for (final r in data.risks)
        for (final a in r.actions) (risk: r, action: a)
    ]..sort((a, b) {
        final ad = a.action.status == ActionStatus.done ? 1 : 0;
        final bd = b.action.status == ActionStatus.done ? 1 : 0;
        if (ad != bd) return ad.compareTo(bd);
        return (a.action.dueOn ?? DateTime(2100)).compareTo(b.action.dueOn ?? DateTime(2100));
      });
    return Column(children: [
      if (isAdmin && data.risks.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.add_task),
              label: const Text('Nuova azione di miglioramento'),
              onPressed: () => _actionDialog(context, ref, data),
            ),
          ),
        ),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('Nessuna azione nel programma di miglioramento.'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final x = rows[i];
                  final a = x.action;
                  final late = a.isOverdue(today);
                  return ListTile(
                    leading: Icon(
                      a.status == ActionStatus.done ? Icons.check_circle : Icons.pending_actions,
                      color: late ? cs.error : null,
                    ),
                    title: Text(a.description),
                    subtitle: Text([
                      x.risk.title,
                      if (a.responsible != null) a.responsible!,
                      if (a.dueOn != null) 'entro ${_d.format(a.dueOn!)}',
                      a.status.label,
                    ].join(' · ')),
                    trailing: late ? Text('Scaduta', style: TextStyle(color: cs.error)) : null,
                    onTap: isAdmin && a.status != ActionStatus.done
                        ? () async {
                            await ref.read(dvrRepoProvider)!.saveAction(
                                id: a.id,
                                riskId: a.riskId,
                                description: a.description,
                                responsible: a.responsible,
                                dueOn: a.dueOn,
                                status: ActionStatus.done);
                            ref.invalidate(dvrDataProvider);
                          }
                        : null,
                  );
                },
              ),
      ),
      if (isAdmin && rows.any((r) => r.action.status != ActionStatus.done))
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Tocca un\'azione per segnarla come completata.', style: TextStyle(fontSize: 12)),
        ),
    ]);
  }
}

Future<void> _actionDialog(BuildContext context, WidgetRef ref, DvrData data) async {
  final desc = TextEditingController();
  final who = TextEditingController();
  String? riskId = data.risks.first.id;
  DateTime? due;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nuova azione'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: riskId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Rischio'),
              items: [for (final r in data.risks) DropdownMenuItem(value: r.id, child: Text(r.title, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => riskId = v,
            ),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Cosa fare')),
            TextField(controller: who, decoration: const InputDecoration(labelText: 'Responsabile')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(due == null ? 'Scadenza' : _d.format(due!)),
              onPressed: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime(2100));
                if (p != null) setS(() => due = p);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (desc.text.trim().isEmpty || riskId == null) return;
              await ref.read(dvrRepoProvider)!.saveAction(
                  riskId: riskId!, description: desc.text, responsible: who.text, dueOn: due);
              ref.invalidate(dvrDataProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
  desc.dispose();
  who.dispose();
}

class _OfficersTab extends ConsumerWidget {
  const _OfficersTab({required this.data, required this.isAdmin});
  final DvrData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final missing = data.missingOfficers(today);
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      if (missing.isNotEmpty)
        Card(
          color: cs.errorContainer,
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
            title: Text('Figure da nominare: ${missing.map((m) => m.label).join(', ')}',
                style: TextStyle(color: cs.onErrorContainer)),
          ),
        ),
      if (data.officers.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nessuna figura registrata.'))),
      for (final o in data.officers)
        ListTile(
          title: Text('${o.role.label} · ${o.name}'),
          subtitle: Text([
            if (o.appointedOn != null) 'dal ${_d.format(o.appointedOn!)}',
            if (o.endsOn != null) 'fino al ${_d.format(o.endsOn!)}',
          ].join(' · ')),
          trailing: isAdmin && o.isActive(today) && o.endsOn == null
              ? TextButton(
                  onPressed: () async {
                    await ref.read(dvrRepoProvider)!.endOfficer(o.id);
                    ref.invalidate(dvrDataProvider);
                  },
                  child: const Text('Termina incarico'))
              : (!o.isActive(today) ? const Text('Cessato') : null),
        ),
    ]);
  }
}

Future<void> _officerDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  var role = SafetyRole.employer;
  DateTime? from;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nuova figura'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<SafetyRole>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Ruolo'),
              items: [for (final r in SafetyRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (v) => role = v ?? role,
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome e cognome')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(from == null ? 'Data di nomina' : _d.format(from!)),
              onPressed: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now());
                if (p != null) setS(() => from = p);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(dvrRepoProvider)!.saveOfficer(role: role, name: name.text, appointedOn: from);
              ref.invalidate(dvrDataProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

class _VersionsTab extends ConsumerWidget {
  const _VersionsTab({required this.data, required this.isAdmin});
  final DvrData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    if (data.versions.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nessuna versione. Crea una bozza, poi emettila per congelare rischi, azioni e figure.',
            textAlign: TextAlign.center),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.versions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final v = data.versions[i];
        return ListTile(
          leading: Icon(v.isActive ? Icons.verified_outlined : (v.isDraft ? Icons.edit_note : Icons.history)),
          title: Text('Versione ${v.version} · ${v.statusLabel}'),
          subtitle: Text([
            if (v.issuedOn != null) 'emessa il ${_d.format(v.issuedOn!)}',
            if (v.nextReviewOn != null) 'revisione entro ${_d.format(v.nextReviewOn!)}',
            if (v.riskCount != null) '${v.riskCount} rischi',
            if (v.sha256 != null) 'impronta ${v.sha256!.substring(0, 12)}…',
          ].join(' · ')),
          trailing: v.reviewDue(today)
              ? Text('Da rivedere', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))
              : (v.isDraft && isAdmin
                  ? FilledButton.tonal(onPressed: () => _issueDialog(context, ref, v), child: const Text('Emetti'))
                  : null),
        );
      },
    );
  }
}

Future<void> _draftDialog(BuildContext context, WidgetRef ref) async {
  final version = TextEditingController(text: '1.0');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nuova bozza DVR'),
      content: TextField(controller: version, decoration: const InputDecoration(labelText: 'Numero di versione')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () async {
            if (version.text.trim().isEmpty) return;
            final sites = await ref.read(sitesProvider.future);
            await ref
                .read(dvrRepoProvider)!
                .createDraft(version.text, sites.length == 1 ? sites.first.id : null);
            ref.invalidate(dvrDataProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Crea'),
        ),
      ],
    ),
  );
  version.dispose();
}

Future<void> _issueDialog(BuildContext context, WidgetRef ref, DvrVersion v) async {
  var review = DateTime.now().add(const Duration(days: 365));
  final reason = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Emetti versione ${v.version}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rischi, azioni aperte e figure attuali vengono congelati e non saranno piu\' modificabili. '
                'La versione in vigore diventera\' "sostituita".'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Prossima revisione: ${_d.format(review)}'),
              onPressed: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: review,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime(2100));
                if (p != null) setS(() => review = p);
              },
            ),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo della revisione (facoltativo)')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(dvrRepoProvider)!.issue(v.id, review, reason.text);
                ref.invalidate(dvrDataProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                final msg = e.toString();
                setS(() => error = msg.contains('vuoto')
                    ? 'Nessun rischio valutato: aggiungi almeno un rischio.'
                    : 'Emissione non riuscita. Riprova.');
              }
            },
            child: const Text('Emetti'),
          ),
        ],
      ),
    ),
  );
  reason.dispose();
}
