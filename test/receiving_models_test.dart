import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/haccp/receiving/receiving_models.dart';

void main() {
  final today = DateTime(2026, 10, 30);

  test('consegna regolare: tutti gli esiti, proposto accettato', () {
    final c = evaluateLine(
        tempC: 3, maxC: 4, expiry: DateTime(2026, 11, 5), receivedOn: today);
    expect(c.hasProblem, isFalse);
    expect(c.suggested, ReceiptOutcome.accepted);
    expect(c.allowed.length, 3);
  });

  test('fuori temperatura: mai accettato senza riserva', () {
    final c = evaluateLine(tempC: 9, maxC: 4, receivedOn: today);
    expect(c.tempOut, isTrue);
    expect(c.allowed, isNot(contains(ReceiptOutcome.accepted)));
    expect(c.suggested, ReceiptOutcome.rejected);
  });

  test('scadenza superata: solo respinto; TMC superato: anche con riserva', () {
    final a = evaluateLine(
        expiry: DateTime(2026, 10, 29), kind: ExpiryKind.useBy, receivedOn: today);
    expect(a.expired, isTrue);
    expect(a.allowed, [ReceiptOutcome.rejected]);
    final b = evaluateLine(
        expiry: DateTime(2026, 10, 29), kind: ExpiryKind.bestBefore, receivedOn: today);
    expect(b.allowed, contains(ReceiptOutcome.reservation));
    expect(b.allowed, isNot(contains(ReceiptOutcome.accepted)));
  });

  test('scade oggi: non e\' scaduto; limite inferiore rispettato', () {
    expect(evaluateLine(expiry: today, receivedOn: today).expired, isFalse);
    expect(evaluateLine(tempC: -20, minC: -18, receivedOn: today).tempOut, isTrue);
    expect(evaluateLine(tempC: -18, minC: -18, receivedOn: today).tempOut, isFalse);
  });

  test('statistiche fornitore', () {
    const s = SupplierStats(
        supplierId: 'x', receipts: 5, lines: 20, rejected: 1, reservations: 1);
    expect(s.nonConformityRate, closeTo(0.1, 1e-9));
    const z = SupplierStats(supplierId: 'x', receipts: 0, lines: 0, rejected: 0, reservations: 0);
    expect(z.nonConformityRate, 0);
  });
}
