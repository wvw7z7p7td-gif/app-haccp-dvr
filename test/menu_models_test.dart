import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/features/haccp/menu/menu_models.dart';

MenuItem _item({Set<String> contains = const {}, Set<String> traces = const {}, bool reviewed = true}) =>
    MenuItem(
      id: 'i',
      name: 'Piatto',
      reviewedAt: reviewed ? DateTime(2026, 10, 1) : null,
      contains: contains,
      traces: traces,
    );

void main() {
  test('senza filtro tutto e\' mostrabile', () {
    expect(suitabilityFor(_item(), {}), Suitability.safe);
  });

  test('contiene > tracce > sicuro', () {
    final it = _item(contains: {'glutine'}, traces: {'latte'});
    expect(suitabilityFor(it, {'glutine'}), Suitability.contains);
    expect(suitabilityFor(it, {'latte'}), Suitability.traces);
    expect(suitabilityFor(it, {'uova'}), Suitability.safe);
    expect(suitabilityFor(it, {'latte', 'glutine'}), Suitability.contains);
  });

  test('allergeni non verificati: mai sicuro', () {
    final it = _item(reviewed: false);
    expect(it.needsReview, isTrue);
    expect(suitabilityFor(it, {'glutine'}), Suitability.unverified);
  });

  test('fromMap legge i livelli', () {
    final it = MenuItem.fromMap({
      'id': 'x',
      'name': 'Y',
      'allergens_reviewed_at': '2026-10-30T10:00:00Z',
      'menu_item_allergens': [
        {'allergen_id': 'a', 'level': 'contains'},
        {'allergen_id': 'b', 'level': 'traces'},
      ],
    });
    expect(it.stateOf('a'), AllergenState.contains);
    expect(it.stateOf('b'), AllergenState.traces);
    expect(it.stateOf('c'), AllergenState.none);
    expect(it.needsReview, isFalse);
  });
}
