import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/haccp/temperatures/temperature_models.dart';

ControlPoint _p({double? min, double? max, int perDay = 2, String id = 'a'}) => ControlPoint(
      id: id,
      siteId: 's',
      name: 'Cella',
      kind: ControlPointKind.fridge,
      minC: min,
      maxC: max,
      readingsPerDay: perDay,
    );

void main() {
  test('parseTemp accetta virgola e punto, rifiuta il resto', () {
    expect(parseTemp('3,5'), 3.5);
    expect(parseTemp(' -18.0 '), -18.0);
    expect(parseTemp(''), isNull);
    expect(parseTemp('abc'), isNull);
    expect(parseTemp('NaN'), isNull);
  });

  test('isOutOfRange con limiti completi e parziali', () {
    final fridge = _p(min: 0, max: 4);
    expect(fridge.isOutOfRange(4.0), isFalse);
    expect(fridge.isOutOfRange(4.1), isTrue);
    expect(fridge.isOutOfRange(-0.1), isTrue);
    final freezer = _p(max: -18);
    expect(freezer.isOutOfRange(-20), isFalse);
    expect(freezer.isOutOfRange(-15), isTrue);
    expect(_p().isOutOfRange(99), isFalse);
  });

  test('rangeLabel', () {
    expect(_p(min: 0, max: 4).rangeLabel, '0,0 °C … 4,0 °C');
    expect(_p(max: -18).rangeLabel, '≤ -18,0 °C');
    expect(_p(min: 65).rangeLabel, '≥ 65,0 °C');
    expect(_p().rangeLabel, 'nessun limite');
  });

  test('TempOverview: rilevazioni completate non superano quelle previste', () {
    final a = _p(id: 'a', perDay: 2);
    final b = _p(id: 'b', perDay: 1);
    final o = TempOverview(
      points: [a, b],
      todayCount: const {'a': 5, 'b': 0},
      lastToday: const {},
      openDeviations: const {'a': 2},
    );
    expect(o.expectedToday, 3);
    expect(o.doneToday, 2);
    expect(o.totalOpenDeviations, 2);
  });
}
