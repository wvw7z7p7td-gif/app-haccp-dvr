import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/alerts/alert_models.dart';
import 'package:haccp_safety/features/safety/incidents/incident_models.dart';
import 'package:haccp_safety/features/safety/people/people_models.dart';

void main() {
  final today = DateTime(2026, 10, 30);

  test('nessuna fonte: nessun avviso', () {
    expect(buildAlerts(today: today), isEmpty);
  });

  test('scadenze: gravita\' per giorni residui, ordine critico > warning > info', () {
    final people = PeopleData(
      employees: const [], roles: const [], trainingTypes: const [], trainingRecords: const [],
      ppeTypes: const [], ppeAssignments: const [],
      deadlines: [
        DeadlineItem(kind: 'training', label: 'Antincendio', dueOn: DateTime(2026, 11, 20)),
        DeadlineItem(kind: 'ppe', label: 'Guanti', dueOn: DateTime(2026, 11, 3)),
        DeadlineItem(kind: 'dvr_review', label: 'Revisione DVR 1', dueOn: DateTime(2026, 10, 1)),
        DeadlineItem(kind: 'training', label: 'Lontana', dueOn: DateTime(2027, 6, 1)),
      ],
    );
    final a = buildAlerts(today: today, people: people);
    expect(a.length, 3);
    expect(a.map((x) => x.severity), [AlertSeverity.critical, AlertSeverity.warning, AlertSeverity.info]);
    expect(a.first.route, '/dvr');
    expect(a.first.detail, 'scaduto da 29 gg');
    expect(a[1].detail, 'scade tra 4 gg');
  });

  test('INAIL pendente e\' critico', () {
    final i = Incident(
      id: 'i', kind: IncidentKind.injury, occurredAt: DateTime(2026, 10, 20), description: 'd',
      severity: Severity.serious, daysLost: 10, inailRequired: true, actions: const [],
    );
    final a = buildAlerts(today: today, incidents: IncidentData(incidents: [i]));
    expect(a.first.severity, AlertSeverity.critical);
    expect(a.first.route, '/eventi');
    expect(a.any((x) => x.title == 'Eventi da chiudere'), isTrue);
  });
}
