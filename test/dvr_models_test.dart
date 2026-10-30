import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/safety/dvr/dvr_models.dart';

DvrRisk _r({int p = 2, int s = 2, String? measures, List<DvrAction> actions = const [], int? rp, int? rs}) =>
    DvrRisk(
      id: 'r',
      title: 't',
      hazardId: 'h',
      hazardName: 'H',
      probability: p,
      severity: s,
      measures: measures,
      residualProbability: rp,
      residualSeverity: rs,
      actions: actions,
    );

void main() {
  test('soglie livello rischio come nel database', () {
    expect(riskLevelFor(1), RiskLevel.low);
    expect(riskLevelFor(2), RiskLevel.low);
    expect(riskLevelFor(3), RiskLevel.medium);
    expect(riskLevelFor(4), RiskLevel.medium);
    expect(riskLevelFor(6), RiskLevel.high);
    expect(riskLevelFor(8), RiskLevel.high);
    expect(riskLevelFor(9), RiskLevel.veryHigh);
    expect(riskLevelFor(16), RiskLevel.veryHigh);
  });

  test('punteggio e residuo', () {
    final r = _r(p: 3, s: 3, rp: 2, rs: 2);
    expect(r.score, 9);
    expect(r.level, RiskLevel.veryHigh);
    expect(r.residualScore, 4);
    expect(r.residualLevel, RiskLevel.medium);
    expect(_r().residualScore, isNull);
  });

  test('rischio alto senza misure ne\' azioni richiede attenzione', () {
    expect(_r(p: 3, s: 3).needsAttention, isTrue);
    expect(_r(p: 3, s: 3, measures: 'Guanti').needsAttention, isFalse);
    expect(_r(p: 1, s: 2).needsAttention, isFalse);
    final withAction = _r(p: 3, s: 3, actions: [
      const DvrAction(id: 'a', riskId: 'r', description: 'x', status: ActionStatus.open)
    ]);
    expect(withAction.needsAttention, isFalse);
  });

  test('azione scaduta solo se non completata', () {
    final today = DateTime(2026, 10, 30);
    final late = DvrAction(
        id: 'a', riskId: 'r', description: 'x', status: ActionStatus.open, dueOn: DateTime(2026, 10, 1));
    final done = DvrAction(
        id: 'b', riskId: 'r', description: 'x', status: ActionStatus.done, dueOn: DateTime(2026, 10, 1));
    final todayDue = DvrAction(
        id: 'c', riskId: 'r', description: 'x', status: ActionStatus.open, dueOn: DateTime(2026, 10, 30));
    expect(late.isOverdue(today), isTrue);
    expect(done.isOverdue(today), isFalse);
    expect(todayDue.isOverdue(today), isFalse);
  });

  test('figure obbligatorie mancanti e revisione in scadenza', () {
    final today = DateTime(2026, 10, 30);
    final data = DvrData(
      hazards: const [],
      risks: const [],
      officers: [
        const SafetyOfficer(id: '1', role: SafetyRole.employer, name: 'A'),
        SafetyOfficer(id: '2', role: SafetyRole.rspp, name: 'B', endsOn: DateTime(2026, 1, 1)),
      ],
      versions: const [],
      areas: const [],
      roles: const [],
    );
    expect(data.missingOfficers(today), [SafetyRole.rspp]);
    final v = DvrVersion(id: 'v', version: '1', status: 'active', nextReviewOn: DateTime(2026, 11, 10));
    expect(v.reviewDue(today), isTrue);
    expect(DvrVersion(id: 'v', version: '1', status: 'draft', nextReviewOn: DateTime(2026, 11, 10)).reviewDue(today),
        isFalse);
  });
}
