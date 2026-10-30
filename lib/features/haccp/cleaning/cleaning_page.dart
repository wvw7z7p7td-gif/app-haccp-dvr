import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'cleaning_approval_sheet.dart';
import 'cleaning_execution_sheet.dart';
import 'cleaning_log_detail_sheet.dart';
import 'cleaning_models.dart';
import 'cleaning_plan_sheet.dart';
import 'cleaning_providers.dart';

class CleaningPage extends ConsumerWidget {
  const CleaningPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cleaningDataProvider);
    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: 'Pulizie e sanificazione',
        bottom: const TabBar(tabs: [
          Tab(text: 'Oggi'),
          Tab(text: 'Storico'),
          Tab(text: 'Piani'),
        ]),
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare le pulizie.'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => ref.invalidate(cleaningDataProvider),
                  child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _TodayTab(data: d),
            _HistoryTab(data: d),
            _PlansTab(data: d),
          ]),
        ),
      ),
    );
  }
}

Future<void> _refresh(WidgetRef ref) async {
  ref.invalidate(cleaningDataProvider);
  await ref.read(cleaningDataProvider.future);
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab({required this.data});
  final CleaningData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    final today = dateOnly(DateTime.now());
    final due = data.dueOn(today);
    final events = data.eventPlans;
    final pending = data.pendingApprovals;
    final fmt = DateFormat('dd/MM', 'it_IT');

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: t.textTheme.titleMedium),
        );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (pending.isNotEmpty) ...[
            header('Da controfirmare (${pending.length})'),
            for (final l in pending)
              ListTile(
                leading: Icon(Icons.draw_outlined, color: t.colorScheme.error),
                title: Text(l.planName),
                subtitle: Text('${fmt.format(l.dueDate)}'
                    '${l.employeeName != null ? ' · ${l.employeeName}' : ''}'),
                trailing: canWrite
                    ? FilledButton.tonal(
                        onPressed: () => showCleaningApprovalSheet(context, log: l),
                        child: const Text('Controfirma'),
                      )
                    : null,
                onTap: () => showCleaningLogDetail(context, l),
              ),
          ],
          header('Da fare oggi'),
          if (due.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna attivita\' prevista per oggi.'),
            ),
          for (final p in due) _planTile(context, p, data.latestOn(p.id, today), today, canWrite),
          if (events.isNotEmpty) ...[
            header('A evento'),
            for (final p in events)
              ListTile(
                leading: const Icon(Icons.bolt_outlined),
                title: Text(p.name),
                subtitle: Text(
                    'Oggi registrate: ${data.logsOn(p.id, today).length}'),
                trailing: canWrite
                    ? FilledButton.tonal(
                        onPressed: () =>
                            showCleaningExecutionSheet(context, plan: p, dueDate: today),
                        child: const Text('Registra'),
                      )
                    : null,
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _planTile(BuildContext context, CleaningPlan p, CleaningLog? log, DateTime today,
      bool canWrite) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      if (p.shift != null) p.shift!,
      '${p.items.length} operazioni',
    ].join(' · ');

    Widget? trailing;
    IconData icon = Icons.radio_button_unchecked;
    if (log == null) {
      if (canWrite) {
        trailing = FilledButton(
          onPressed: () => showCleaningExecutionSheet(context, plan: p, dueDate: today),
          child: const Text('Esegui'),
        );
      }
    } else if (log.status == CleaningStatus.done) {
      icon = Icons.check_circle;
      trailing = log.requiresApproval && !log.approved
          ? const Chip(label: Text('Da controfirmare'))
          : const Icon(Icons.verified_outlined);
    } else {
      icon = Icons.remove_circle_outline;
      trailing = Chip(label: Text(log.status.label));
    }

    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(icon, color: log?.status == CleaningStatus.done ? cs.primary : null),
      title: Text(p.name),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: log == null ? null : () => showCleaningLogDetail(context, log),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.data});
  final CleaningData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd/MM', 'it_IT');
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: data.logs.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nessuna registrazione negli ultimi 30 giorni.')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final l = data.logs[i];
                return ListTile(
                  leading: Icon(l.status == CleaningStatus.done
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline),
                  title: Text(l.planName),
                  subtitle: Text([
                    fmt.format(l.dueDate),
                    l.status.label,
                    if (l.employeeName != null) l.employeeName!,
                    if (l.requiresApproval && l.status == CleaningStatus.done)
                      l.approved ? 'controfirmata' : 'da controfirmare',
                  ].join(' · ')),
                  trailing: l.signaturePath != null ? const Icon(Icons.draw_outlined) : null,
                  onTap: () => showCleaningLogDetail(context, l),
                );
              },
            ),
    );
  }
}

class _PlansTab extends ConsumerWidget {
  const _PlansTab({required this.data});
  final CleaningData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => showCleaningPlanSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo piano'),
            )
          : null,
      body: data.plans.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isAdmin
                      ? 'Nessun piano di pulizia.\nCrea il primo con il pulsante in basso.'
                      : 'Nessun piano di pulizia configurato.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: data.plans.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = data.plans[i];
                return ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(p.name),
                  subtitle: Text([
                    p.scheduleLabel,
                    if (p.shift != null) p.shift!,
                    if (p.requiresApproval) 'con controfirma',
                  ].join(' · ')),
                  trailing: isAdmin ? const Icon(Icons.edit_outlined) : null,
                  onTap: isAdmin ? () => showCleaningPlanSheet(context, existing: p) : null,
                );
              },
            ),
    );
  }
}
