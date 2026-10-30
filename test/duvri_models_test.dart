import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/safety/duvri/duvri_models.dart';

ContractorDoc _doc(ContractorDocType t, {DateTime? exp, String? file = 'f'}) =>
    ContractorDoc(id: '${t.name}${exp ?? ''}', type: t, expiresOn: exp, filePath: file);

void main() {
  final today = DateTime(2026, 10, 30);

  test('validita documento: senza file non vale, scaduto, in scadenza', () {
    expect(_doc(ContractorDocType.durc, exp: DateTime(2027, 5, 1)).validity(today), DocValidity.valid);
    expect(_doc(ContractorDocType.durc, exp: DateTime(2026, 11, 15)).validity(today), DocValidity.expiring);
    expect(_doc(ContractorDocType.durc, exp: DateTime(2026, 10, 29)).validity(today), DocValidity.expired);
    expect(_doc(ContractorDocType.durc, exp: DateTime(2027, 5, 1), file: null).validity(today), DocValidity.missing);
    expect(_doc(ContractorDocType.chamber).validity(today), DocValidity.valid);
  });

  test('conformita: servono i 4 documenti obbligatori', () {
    final c = Contractor(id: 'c', name: 'X', docs: [
      _doc(ContractorDocType.durc, exp: DateTime(2027, 1, 1)),
      _doc(ContractorDocType.insurance, exp: DateTime(2027, 1, 1)),
    ]);
    expect(c.missingRequired(today), [ContractorDocType.chamber, ContractorDocType.fitness]);
    expect(c.isCompliant(today), isFalse);

    final ok = Contractor(id: 'c', name: 'X', docs: [
      for (final t in ContractorDocType.values.where((t) => t.required)) _doc(t, exp: DateTime(2027, 1, 1)),
    ]);
    expect(ok.isCompliant(today), isTrue);
    expect(ok.nextExpiry(today), DateTime(2027, 1, 1));
  });

  test('un documento scaduto non basta, uno valido piu\' recente si', () {
    final c = Contractor(id: 'c', name: 'X', docs: [
      for (final t in ContractorDocType.values.where((t) => t.required)) _doc(t, exp: DateTime(2027, 1, 1)),
      _doc(ContractorDocType.durc, exp: DateTime(2026, 1, 1)),
    ]);
    expect(c.isCompliant(today), isTrue);
    final bad = Contractor(id: 'c', name: 'X', docs: [
      for (final t in ContractorDocType.values.where((t) => t.required)) _doc(t, exp: DateTime(2027, 1, 1)),
    ]..removeWhere((d) => d.type == ContractorDocType.durc)..add(_doc(ContractorDocType.durc, exp: DateTime(2026, 1, 1))));
    expect(bad.missingRequired(today), [ContractorDocType.durc]);
  });

  Duvri duvri({String status = 'draft', DateTime? issued, bool none = false, List<Interference> i = const [], Set<String> s = const {}, DateTime? ends}) =>
      Duvri(id: 'd', contractorId: 'c', contractorName: 'X', activity: 'a', status: status,
          noInterference: none, interferences: i, signedParties: s, issuedAt: issued, endsOn: ends);
  const inter = Interference(id: 'i', description: 'd', measures: 'm', costEur: 10.5);

  test('fasi del DUVRI', () {
    expect(duvri().stage, DuvriStage.draft);
    expect(duvri(issued: today).stage, DuvriStage.issued);
    expect(duvri(issued: today, s: {'employer'}).stageLabel, 'Firmato da una parte');
    expect(duvri(status: 'signed', issued: today).stage, DuvriStage.signed);
    expect(duvri(status: 'closed', issued: today).stage, DuvriStage.closed);
  });

  test('pronto per emissione: interferenze oppure dichiarazione, mai entrambe o nulla', () {
    expect(duvri().readyToIssue, isFalse);
    expect(duvri(i: [inter]).readyToIssue, isTrue);
    expect(duvri(none: true).readyToIssue, isTrue);
    expect(duvri(none: true, i: [inter]).readyToIssue, isFalse);
    expect(duvri(i: [inter, inter]).totalCost, 21.0);
  });

  test('da chiudere solo se firmato e terminato', () {
    expect(duvri(status: 'signed', issued: today, ends: DateTime(2026, 10, 1)).needsClosing(today), isTrue);
    expect(duvri(status: 'signed', issued: today, ends: DateTime(2026, 12, 1)).needsClosing(today), isFalse);
    expect(duvri(status: 'closed', issued: today, ends: DateTime(2026, 10, 1)).needsClosing(today), isFalse);
  });
}
