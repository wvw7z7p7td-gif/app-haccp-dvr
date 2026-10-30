import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/haccp/cleaning/cleaning_models.dart';

CleaningPlan _plan({
  String id = 'p1',
  CleaningFrequency f = CleaningFrequency.daily,
  List<int> weekdays = const [],
  int? dom,
  bool approval = false,
}) =>
    CleaningPlan(
      id: id,
      siteId: 's',
      name: 'Piano $id',
      frequency: f,
      weekdays: weekdays,
      dayOfMonth: dom,
      requiresApproval: approval,
      items: const [],
    );

CleaningLog _log({
  required String planId,
  required DateTime day,
  CleaningStatus status = CleaningStatus.done,
  bool requiresApproval = false,
  bool approved = false,
}) =>
    CleaningLog(
      id: '$planId-${day.toIso8601String()}-${status.name}',
      planId: planId,
      planName: 'Piano $planId',
      dueDate: day,
      status: status,
      performedAt: day,
      requiresApproval: requiresApproval,
      approved: approved,
    );

void main() {
  test('dbDate e dateOnly', () {
    expect(dbDate(DateTime(2026, 3, 5, 14, 30)), '2026-03-05');
    expect(dateOnly(DateTime(2026, 3, 5, 14, 30)), DateTime(2026, 3, 5));
  });

  test('piano giornaliero: sempre previsto; a evento: mai', () {
    expect(_plan().isDueOn(DateTime(2026, 10, 30)), isTrue);
    expect(_plan(f: CleaningFrequency.onEvent).isDueOn(DateTime(2026, 10, 30)), isFalse);
  });

  test('piano settimanale usa i giorni ISO (1 = lunedi)', () {
    final p = _plan(f: CleaningFrequency.weekly, weekdays: [1, 5]);
    expect(p.isDueOn(DateTime(2026, 10, 26)), isTrue); // lunedi'
    expect(p.isDueOn(DateTime(2026, 10, 30)), isTrue); // venerdi'
    expect(p.isDueOn(DateTime(2026, 10, 28)), isFalse); // mercoledi'
    expect(_plan(f: CleaningFrequency.weekly).isDueOn(DateTime(2026, 10, 26)), isFalse);
  });

  test('piano mensile al 31 cade l\'ultimo giorno dei mesi corti', () {
    final p = _plan(f: CleaningFrequency.monthly, dom: 31);
    expect(p.isDueOn(DateTime(2026, 2, 28)), isTrue);
    expect(p.isDueOn(DateTime(2026, 2, 27)), isFalse);
    expect(p.isDueOn(DateTime(2026, 4, 30)), isTrue);
    expect(p.isDueOn(DateTime(2026, 10, 31)), isTrue);
    expect(_plan(f: CleaningFrequency.monthly, dom: 15).isDueOn(DateTime(2026, 10, 15)), isTrue);
  });

  test('scheduleLabel', () {
    expect(_plan(f: CleaningFrequency.weekly, weekdays: [5, 1]).scheduleLabel, 'Lun, Ven');
    expect(_plan(f: CleaningFrequency.monthly, dom: 3).scheduleLabel, 'Il giorno 3 del mese');
  });

  test('CleaningData: eseguite, non eseguite, controfirme in sospeso', () {
    final today = DateTime(2026, 10, 30);
    final a = _plan(id: 'a');
    final b = _plan(id: 'b', approval: true);
    final c = _plan(id: 'c');
    final data = CleaningData(plans: [a, b, c], logs: [
      _log(planId: 'a', day: today),
      _log(planId: 'b', day: today, requiresApproval: true),
      _log(planId: 'c', day: today, status: CleaningStatus.skipped),
      _log(planId: 'b', day: DateTime(2026, 10, 29), requiresApproval: true, approved: true),
    ]);
    expect(data.dueOn(today).length, 3);
    expect(data.doneOn(today), 2);
    expect(data.skippedOn(today), 1);
    expect(data.pendingApprovals.length, 1);
    expect(data.pendingApprovals.single.planId, 'b');
    expect(data.latestOn('a', today)?.status, CleaningStatus.done);
    expect(data.latestOn('a', DateTime(2026, 10, 1)), isNull);
  });

  test('ordinamento per momento della giornata', () {
    expect(shiftRank('Apertura') < shiftRank('Chiusura'), isTrue);
    expect(shiftRank(null), shiftOptions.length);
  });
}
