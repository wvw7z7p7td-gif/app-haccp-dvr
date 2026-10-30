import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../haccp/cleaning/cleaning_models.dart';
import '../haccp/cleaning/cleaning_providers.dart';
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
          ),
          _TaskCard(
            icon: Icons.cleaning_services,
            title: 'Pulizie e sanificazione',
            subtitle: cleaningSubtitle,
            alert: cleaningAlert,
          ),
          const _TaskCard(
            icon: Icons.event_busy,
            title: 'Scadenze imminenti',
            subtitle: 'Disponibile con il modulo Formazione e DPI',
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool alert;

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
      ),
    );
  }
}
