import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/haccp/pest/pest_models.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);

  test('postazione mai controllata: in ritardo; disattiva: mai', () {
    expect(isStationOverdue(active: true, lastInspectedAt: null, everyDays: 7, now: now), isTrue);
    expect(isStationOverdue(active: false, lastInspectedAt: null, everyDays: 7, now: now), isFalse);
  });

  test('ritardo in base alla frequenza', () {
    expect(isStationOverdue(active: true, lastInspectedAt: DateTime(2026, 10, 25), everyDays: 7, now: now),
        isFalse);
    expect(isStationOverdue(active: true, lastInspectedAt: DateTime(2026, 10, 20), everyDays: 7, now: now),
        isTrue);
  });

  test('un rilievo non conforme senza azioni va gestito', () {
    final item = PestItem.fromMap({'id': 'a', 'station_id': 's', 'status': 'activity', 'catch_count': 2});
    expect(item.needsAction, isTrue);
    final done = PestItem.fromMap({
      'id': 'b',
      'station_id': 's',
      'status': 'activity',
      'pest_corrective_actions': [
        {'action': 'Esca sostituita'}
      ],
    });
    expect(done.needsAction, isFalse);
    expect(PestItem.fromMap({'id': 'c', 'station_id': 's', 'status': 'ok'}).needsAction, isFalse);
  });
}
