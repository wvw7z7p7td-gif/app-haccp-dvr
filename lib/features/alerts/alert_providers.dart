import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../haccp/pest/pest_providers.dart';
import '../haccp/temperatures/temperature_providers.dart';
import '../safety/incidents/incident_providers.dart';
import '../safety/people/people_providers.dart';
import 'alert_models.dart';

/// Avvisi unificati. Le fonti non ancora caricate (o in errore) sono semplicemente omesse.
final alertsProvider = Provider.autoDispose<List<AppAlert>>((ref) {
  return buildAlerts(
    today: DateTime.now(),
    temps: ref.watch(tempOverviewProvider).valueOrNull,
    pest: ref.watch(pestDataProvider).valueOrNull,
    people: ref.watch(peopleDataProvider).valueOrNull,
    incidents: ref.watch(incidentDataProvider).valueOrNull,
  );
});
