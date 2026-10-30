// Modelli puri per allergeni e menu (Reg. UE 1169/2011).

enum AllergenState { none, contains, traces }

class Allergen {
  const Allergen({required this.id, required this.code, required this.name, required this.sort});
  final String id;
  final String code;
  final String name;
  final int sort;

  factory Allergen.fromMap(Map<String, dynamic> m) => Allergen(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        sort: (m['sort_order'] as num).toInt(),
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    this.category,
    this.ingredients,
    this.notes,
    this.active = true,
    this.reviewedAt,
    this.contains = const {},
    this.traces = const {},
  });

  final String id;
  final String name;
  final String? category;
  final String? ingredients;
  final String? notes;
  final bool active;
  final DateTime? reviewedAt;
  final Set<String> contains; // id allergeni
  final Set<String> traces;

  /// Allergeni mai verificati o ingredienti cambiati dopo l'ultima verifica.
  bool get needsReview => reviewedAt == null;

  AllergenState stateOf(String allergenId) => contains.contains(allergenId)
      ? AllergenState.contains
      : traces.contains(allergenId)
          ? AllergenState.traces
          : AllergenState.none;

  factory MenuItem.fromMap(Map<String, dynamic> m) {
    final contains = <String>{};
    final traces = <String>{};
    for (final r in (m['menu_item_allergens'] as List?) ?? const []) {
      final row = r as Map<String, dynamic>;
      (row['level'] == 'traces' ? traces : contains).add(row['allergen_id'] as String);
    }
    return MenuItem(
      id: m['id'] as String,
      name: m['name'] as String,
      category: m['category'] as String?,
      ingredients: m['ingredients'] as String?,
      notes: m['notes'] as String?,
      active: (m['active'] as bool?) ?? true,
      reviewedAt: m['allergens_reviewed_at'] == null
          ? null
          : DateTime.parse(m['allergens_reviewed_at'] as String),
      contains: contains,
      traces: traces,
    );
  }
}

enum Suitability { safe, traces, contains, unverified }

/// Idoneita' di un piatto per chi deve evitare [avoid].
/// Un piatto con allergeni NON verificati non e' mai dichiarato sicuro.
Suitability suitabilityFor(MenuItem item, Set<String> avoid) {
  if (avoid.isEmpty) return Suitability.safe;
  if (item.needsReview) return Suitability.unverified;
  if (item.contains.any(avoid.contains)) return Suitability.contains;
  if (item.traces.any(avoid.contains)) return Suitability.traces;
  return Suitability.safe;
}

class MenuData {
  const MenuData({required this.allergens, required this.items});
  final List<Allergen> allergens;
  final List<MenuItem> items;

  static const empty = MenuData(allergens: [], items: []);

  int get toReview => items.where((i) => i.active && i.needsReview).length;

  Allergen? allergen(String id) {
    for (final a in allergens) {
      if (a.id == id) return a;
    }
    return null;
  }
}
