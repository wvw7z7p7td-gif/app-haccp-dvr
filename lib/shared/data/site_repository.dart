import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';

class SiteRef {
  const SiteRef({required this.id, required this.name});
  final String id;
  final String name;
}

class SiteRepository {
  SiteRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  Future<List<SiteRef>> sites() async {
    final rows = await _db
        .from('sites')
        .select('id, name')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows.map((r) => SiteRef(id: r['id'] as String, name: r['name'] as String)).toList();
  }

  Future<String> createSite(String name) async {
    final row = await _db
        .from('sites')
        .insert({'company_id': companyId, 'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }
}

final siteRepoProvider = Provider<SiteRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return SiteRepository(ref.watch(supabaseProvider), m.companyId);
});

final sitesProvider = FutureProvider.autoDispose<List<SiteRef>>((ref) async {
  final repo = ref.watch(siteRepoProvider);
  if (repo == null) return const [];
  return repo.sites();
});
