import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/safety/people/people_models.dart';

void main() {
  final today = DateTime(2026, 10, 30);

  test('validita per scadenza', () {
    expect(validityFor(null, today), Validity.valid);
    expect(validityFor(DateTime(2026, 10, 29), today), Validity.expired);
    expect(validityFor(DateTime(2026, 10, 30), today), Validity.expiring);
    expect(validityFor(DateTime(2026, 11, 20), today), Validity.expiring);
    expect(validityFor(DateTime(2027, 1, 1), today), Validity.valid);
  });

  PeopleData data({
    List<TrainingRecord> tr = const [],
    List<PpeAssignment> ppe = const [],
  }) =>
      PeopleData(
        employees: const [
          Employee(id: 'e', firstName: 'Carlo', lastName: 'Cuoco', isSupervisor: false, active: true, jobRoleId: 'r'),
          Employee(id: 'n', firstName: 'Nina', lastName: 'Senza', isSupervisor: false, active: true),
        ],
        roles: const [
          JobRole(id: 'r', name: 'Cuoco', trainingIds: {'haccp'}, ppeIds: {'guanti'})
        ],
        trainingTypes: const [TrainingType(id: 'haccp', code: 'HACCP', name: 'HACCP')],
        trainingRecords: tr,
        ppeTypes: const [PpeType(id: 'guanti', name: 'Guanti')],
        ppeAssignments: ppe,
        deadlines: const [],
      );

  test('senza attestati ne\' DPI: due problemi', () {
    final d = data();
    final e = d.employee('e')!;
    final i = d.issuesFor(e, today);
    expect(i.training, 1);
    expect(i.ppe, 1);
    expect(d.totalIssues(today), 2);
    expect(d.issuesFor(d.employee('n')!, today).training, 0); // nessuna mansione = nessun requisito
  });

  test('conta l\'attestato piu\' recente', () {
    final d = data(tr: [
      TrainingRecord(id: '1', employeeId: 'e', typeId: 'haccp', issuedOn: DateTime(2020, 1, 1), expiresOn: DateTime(2023, 1, 1)),
      TrainingRecord(id: '2', employeeId: 'e', typeId: 'haccp', issuedOn: DateTime(2026, 9, 1), expiresOn: DateTime(2029, 9, 1)),
    ]);
    expect(d.trainingStatus('e', 'haccp', today), Validity.valid);
    final old = data(tr: [
      TrainingRecord(id: '1', employeeId: 'e', typeId: 'haccp', issuedOn: DateTime(2020, 1, 1), expiresOn: DateTime(2023, 1, 1)),
    ]);
    expect(old.trainingStatus('e', 'haccp', today), Validity.expired);
    expect(old.issuesFor(old.employee('e')!, today).training, 1);
  });

  test('DPI restituito non conta; senza scadenza e\' valido', () {
    final returned = data(ppe: [
      PpeAssignment(id: 'a', employeeId: 'e', typeId: 'guanti', deliveredOn: DateTime(2026, 1, 1), returnedOn: DateTime(2026, 5, 1)),
    ]);
    expect(returned.ppeStatus('e', 'guanti', today), Validity.missing);
    final ok = data(ppe: [
      PpeAssignment(id: 'a', employeeId: 'e', typeId: 'guanti', deliveredOn: DateTime(2026, 1, 1)),
    ]);
    expect(ok.ppeStatus('e', 'guanti', today), Validity.valid);
    final expired = data(ppe: [
      PpeAssignment(id: 'a', employeeId: 'e', typeId: 'guanti', deliveredOn: DateTime(2024, 1, 1), expiresOn: DateTime(2025, 1, 1)),
    ]);
    expect(expired.ppeStatus('e', 'guanti', today), Validity.expired);
  });

  test('scadenze entro N giorni ordinate', () {
    final d = PeopleData(
      employees: const [],
      roles: const [],
      trainingTypes: const [],
      trainingRecords: const [],
      ppeTypes: const [],
      ppeAssignments: const [],
      deadlines: [
        DeadlineItem(kind: 'ppe', label: 'B', dueOn: DateTime(2026, 11, 10)),
        DeadlineItem(kind: 'training', label: 'A', dueOn: DateTime(2026, 10, 1)),
        DeadlineItem(kind: 'dvr_review', label: 'C', dueOn: DateTime(2027, 6, 1)),
      ],
    );
    final w = d.deadlinesWithin(today, 30);
    expect(w.map((x) => x.label), ['A', 'B']);
    expect(w.first.daysLeft(today), -29);
    expect(w.first.kindLabel, 'Formazione');
  });
}
