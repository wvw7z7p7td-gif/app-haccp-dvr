import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/offline/offline_providers.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../alerts/alert_models.dart';
import '../alerts/alert_providers.dart';
import '../haccp/cleaning/cleaning_models.dart';
import '../haccp/cleaning/cleaning_providers.dart';
import '../haccp/menu/menu_providers.dart';
import '../haccp/pest/pest_providers.dart';
import '../haccp/receiving/receiving_providers.dart';
import '../haccp/temperatures/temperature_providers.dart';

/// "Modalita' turno": riepilogo di cio' che e' da fare oggi.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(activeMembershipProvider);
    final today = DateFormat.yMMMMEEEEd('it_IT').format(DateTime.now());
    final temps = ref.watch(tempOverviewProvider);
    final cleaning = ref.watch(cleaningDataProvider);
    final receiving = ref.watch(receivingDataProvider);
    final menu = ref.watch(menuDataProvider);
    final pest = ref.watch(pestDataProvider);
    final alerts = ref.watch(alertsProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final critical = alerts.where((a) => a.severity == AlertSeverity.critical).length;

    final tempSubtitle = temps.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (o) {
        if (o.points.isEmpty) return 'Nessun punto di controllo configurato';
        final open = o.totalOpenDeviations;
        final base = '${o.doneToday}/${o.expectedToday} rilevazioni completate';
        return open > 0
            ? '$base · $open scostament${open == 1 ? 'o' : 'i'} da gestire'
            : base;
      },
    );
    final tempAlert = (temps.valueOrNull?.totalOpenDeviations ?? 0) > 0;

    final now = dateOnly(DateTime.now());
    final cleaningSubtitle = cleaning.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        final due = d.dueOn(now).length;
        if (due == 0 && d.pendingApprovals.isEmpty) return 'Nessuna attivita\' prevista';
        final skipped = d.skippedOn(now);
        final pending = d.pendingApprovals.length;
        return [
          '${d.doneOn(now)}/$due eseguite',
          if (skipped > 0) '$skipped non eseguit${skipped == 1 ? 'a' : 'e'}',
          if (pending > 0) '$pending da controfirmare',
        ].join(' · ');
      },
    );
    final cleaningAlert = cleaning.maybeWhen(
      data: (d) => d.skippedOn(now) > 0 || d.pendingApprovals.isNotEmpty,
      orElse: () => false,
    );

    final receivingSubtitle = receiving.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        final today = d.receivedOn(DateTime.now());
        if (today.isEmpty) return 'Nessuna consegna registrata oggi';
        final issues = today.where((r) => r.hasIssues).length;
        final base = '${today.length} consegn${today.length == 1 ? 'a' : 'e'} registrat${today.length == 1 ? 'a' : 'e'}';
        return issues > 0 ? '$base · $issues con non conformita\'' : base;
      },
    );
    final receivingAlert = receiving.maybeWhen(
      data: (d) => d.receivedOn(DateTime.now()).any((r) => r.hasIssues),
      orElse: () => false,
    );

    final menuSubtitle = menu.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        if (d.items.isEmpty) return 'Nessun piatto registrato';
        final n = d.toReview;
        return n > 0
            ? '$n piatt${n == 1 ? 'o' : 'i'} con allergeni da verificare'
            : '${d.items.length} piatti con allergeni verificati';
      },
    );
    final menuAlert = (menu.valueOrNull?.toReview ?? 0) > 0;

    final pestSubtitle = pest.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        if (d.stations.isEmpty) return 'Nessuna postazione configurata';
        final late = d.overdueCount;
        final open = d.openFindings.length;
        return [
          late > 0 ? '$late postazion${late == 1 ? 'e' : 'i'} da controllare' : 'controlli in regola',
          if (open > 0) '$open rilievi senza azione',
        ].join(' · ');
      },
    );
    final pestAlert = (pest.valueOrNull?.overdueCount ?? 0) > 0 ||
        (pest.valueOrNull?.openFindings.isNotEmpty ?? false);

    return PageScaffold(
      title: m?.companyName ?? 'Oggi',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(today, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _TaskCard(
            icon: Icons.thermostat,
            title: 'Rilevazioni temperatura',
            subtitle: tempSubtitle,
            alert: tempAlert,
            onTap: () => context.go('/temperature'),
          ),
          _TaskCard(
            icon: Icons.cleaning_services,
            title: 'Pulizie e sanificazione',
            subtitle: cleaningSubtitle,
            alert: cleaningAlert,
            onTap: () => context.go('/pulizie'),
          ),
          _TaskCard(
            icon: Icons.local_shipping,
            title: 'Merci in arrivo / ricevute',
            subtitle: receivingSubtitle,
            alert: receivingAlert,
            onTap: () => context.go('/merci'),
          ),
          _TaskCard(
            icon: Icons.restaurant_menu,
            title: 'Menu e allergeni',
            subtitle: menuSubtitle,
            alert: menuAlert,
            onTap: () => context.push('/menu'),
          ),
          _TaskCard(
            icon: Icons.bug_report,
            title: 'Controllo infestanti',
            subtitle: pestSubtitle,
            alert: pestAlert,
            onTap: () => context.push('/infestanti'),
          ),
          if (pending > 0)
            _TaskCard(
              icon: Icons.cloud_upload_outlined,
              title: 'Da inviare',
              subtitle: '$pending registrazion${pending == 1 ? 'e' : 'i'} salvat${pending == 1 ? 'a' : 'e'} '
                  'sul dispositivo. Tocca per riprovare.',
              alert: true,
              onTap: () => ref.read(pendingCountProvider.notifier).flush(),
            ),
          _TaskCard(
            icon: Icons.notifications_active_outlined,
            title: 'Avvisi e scadenze',
            subtitle: alerts.isEmpty
                ? 'Tutto in regola'
                : '${alerts.length} avvis${alerts.length == 1 ? 'o' : 'i'}'
                    '${critical > 0 ? ' · $critical urgent${critical == 1 ? 'e' : 'i'}' : ''}',
            alert: critical > 0,
            onTap: () => context.push('/avvisi'),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.alert = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: alert ? cs.errorContainer : null,
      child: ListTile(
        minVerticalPadding: 16,
        leading: Icon(icon, size: 32, color: alert ? cs.onErrorContainer : null),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
