import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'menu_models.dart';
import 'menu_repository.dart';

final menuRepoProvider = Provider<MenuRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return MenuRepository(ref.watch(supabaseProvider), m.companyId);
});

final menuDataProvider = FutureProvider.autoDispose<MenuData>((ref) async {
  final repo = ref.watch(menuRepoProvider);
  if (repo == null) return MenuData.empty;
  return repo.load();
});
