import 'package:supabase_flutter/supabase_flutter.dart';

import 'menu_models.dart';

class MenuRepository {
  MenuRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  Future<MenuData> load() async {
    final al = await _db.from('allergens').select().order('sort_order');
    final rows = await _db
        .from('menu_items')
        .select('*, menu_item_allergens(allergen_id, level)')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return MenuData(
      allergens: al.map(Allergen.fromMap).toList(),
      items: rows.map(MenuItem.fromMap).toList(),
    );
  }

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Crea o aggiorna il piatto e conferma la matrice allergeni (id dal client: idempotente).
  Future<void> save({
    required String id,
    required bool isNew,
    required String name,
    required Set<String> contains,
    required Set<String> traces,
    String? category,
    String? ingredients,
    String? notes,
    bool active = true,
  }) async {
    final fields = {
      'name': name.trim(),
      'category': _nn(category),
      'ingredients': _nn(ingredients),
      'notes': _nn(notes),
      'active': active,
    };
    if (isNew) {
      try {
        await _db.from('menu_items').insert({'id': id, 'company_id': companyId, ...fields});
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
    } else {
      await _db.from('menu_items').update(fields).eq('id', id);
    }
    // Dopo l'update: la funzione registra la verifica (e l'update degli ingredienti l'avrebbe azzerata).
    await _db.rpc('set_menu_item_allergens', params: {
      'p_item': id,
      'p_contains': contains.toList(),
      'p_traces': traces.toList(),
    });
  }

  Future<void> archive(String id) =>
      _db.from('menu_items').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
}
