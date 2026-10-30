import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'pest_models.dart';
import 'pest_repository.dart';

final pestRepoProvider = Provider<PestRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return PestRepository(ref.watch(supabaseProvider), m.companyId);
});

final pestDataProvider = FutureProvider.autoDispose<PestData>((ref) async {
  final repo = ref.watch(pestRepoProvider);
  if (repo == null) return PestData.empty;
  return repo.load();
});
