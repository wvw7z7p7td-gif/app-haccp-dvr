import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'dvr_models.dart';
import 'dvr_repository.dart';

final dvrRepoProvider = Provider<DvrRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return DvrRepository(ref.watch(supabaseProvider), m.companyId);
});

final dvrDataProvider = FutureProvider.autoDispose<DvrData>((ref) async {
  final repo = ref.watch(dvrRepoProvider);
  if (repo == null) return DvrData.empty;
  return repo.load();
});
