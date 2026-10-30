import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/safety/incidents/incident_models.dart';

IncidentAction _a(IncidentStep s) =>
    IncidentAction(id: s.name, step: s, description: 'x', performedAt: DateTime(2026, 10, 1));

Incident _i({
  IncidentKind kind = IncidentKind.injury,
  Severity sev = Severity.lostTime,
  int days = 5,
  List<IncidentAction> actions = const [],
}) =>
    Incident(
      id: 'i',
      kind: kind,
      occurredAt: DateTime(2026, 10, 1),
      description: 'd',
      severity: sev,
      daysLost: days,
      inailRequired: inailReportRequired(kind, sev, days),
      actions: actions,
    );

void main() {
  test('denuncia INAIL: oltre 3 giorni o grave, mai per near miss', () {
    expect(inailReportRequired(IncidentKind.injury, Severity.lostTime, 3), isFalse);
    expect(inailReportRequired(IncidentKind.injury, Severity.lostTime, 4), isTrue);
    expect(inailReportRequired(IncidentKind.injury, Severity.serious, 0), isTrue);
    expect(inailReportRequired(IncidentKind.nearMiss, Severity.none, 0), isFalse);
  });

  test('chiusura: serve indagine/azione e, se prevista, denuncia', () {
    expect(_i().canClose, isFalse);
    expect(_i(actions: [_a(IncidentStep.investigation)]).canClose, isFalse);
    expect(_i(actions: [_a(IncidentStep.investigation), _a(IncidentStep.inailReport)]).canClose, isTrue);
    expect(_i(kind: IncidentKind.nearMiss, sev: Severity.none, days: 0, actions: [_a(IncidentStep.corrective)]).canClose,
        isTrue);
  });

  test('passi pendenti e disponibili', () {
    final fresh = _i();
    expect(fresh.pendingSteps(), [IncidentStep.investigation, IncidentStep.inailReport]);
    expect(fresh.availableSteps, [IncidentStep.investigation, IncidentStep.corrective, IncidentStep.inailReport]);
    final ready = _i(actions: [_a(IncidentStep.corrective), _a(IncidentStep.inailReport)]);
    expect(ready.availableSteps.last, IncidentStep.closure);
    expect(ready.availableSteps, isNot(contains(IncidentStep.inailReport)));
    final closed = _i(actions: [_a(IncidentStep.corrective), _a(IncidentStep.inailReport), _a(IncidentStep.closure)]);
    expect(closed.closed, isTrue);
    expect(closed.availableSteps, isEmpty);
    expect(closed.pendingSteps(), isEmpty);
  });

  test('statistiche ultimi 12 mesi', () {
    final today = DateTime(2026, 10, 30);
    final d = IncidentData(incidents: [
      _i(days: 5),
      Incident(
          id: 'n', kind: IncidentKind.nearMiss, occurredAt: DateTime(2026, 9, 1), description: 'x',
          severity: Severity.none, daysLost: 0, inailRequired: false, actions: const []),
      Incident(
          id: 'old', kind: IncidentKind.injury, occurredAt: DateTime(2024, 1, 1), description: 'x',
          severity: Severity.medical, daysLost: 2, inailRequired: false, actions: [_a(IncidentStep.closure)]),
    ]);
    final s = d.stats(today);
    expect(s.injuries, 1);
    expect(s.nearMisses, 1);
    expect(s.daysLost, 5);
    expect(s.open, 2);
    expect(d.inailPending, 1);
  });
}
