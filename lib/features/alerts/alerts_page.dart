import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/page_scaffold.dart';
import '../haccp/pest/pest_providers.dart';
import '../haccp/temperatures/temperature_providers.dart';
import '../safety/incidents/incident_providers.dart';
import '../safety/people/people_providers.dart';
import 'alert_models.dart';
import 'alert_providers.dart';

class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final cs = Theme.of(context).colorScheme;
    return PageScaffold(
      title: 'Avvisi',
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(tempOverviewProvider)
            ..invalidate(pestDataProvider)
            ..invalidate(peopleDataProvider)
            ..invalidate(incidentDataProvider);
          await ref.read(peopleDataProvider.future);
        },
        child: ListView(children: [
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Tutto in regola: nessun avviso.')),
            ),
          for (final a in alerts)
            ListTile(
              leading: Icon(
                switch (a.severity) {
                  AlertSeverity.critical => Icons.error,
                  AlertSeverity.warning => Icons.warning_amber_rounded,
                  AlertSeverity.info => Icons.info_outline,
                },
                color: switch (a.severity) {
                  AlertSeverity.critical => cs.error,
                  AlertSeverity.warning => cs.tertiary,
                  AlertSeverity.info => cs.outline,
                },
              ),
              title: Text(a.title),
              subtitle: Text(a.detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(a.route),
            ),
        ]),
      ),
    );
  }
}
