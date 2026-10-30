import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'duvri_models.dart';
import 'duvri_repository.dart';

final duvriRepoProvider = Provider<DuvriRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return DuvriRepository(ref.watch(supabaseProvider), m.companyId);
});

final duvriDataProvider = FutureProvider.autoDispose<DuvriData>((ref) async {
  final repo = ref.watch(duvriRepoProvider);
  if (repo == null) return DuvriData.empty;
  return repo.load();
});
