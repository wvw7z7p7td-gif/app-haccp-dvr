import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'cleaning_models.dart';
import 'cleaning_repository.dart';

final cleaningRepoProvider = Provider<CleaningRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return CleaningRepository(ref.watch(supabaseProvider), m.companyId);
});

final cleaningDataProvider = FutureProvider.autoDispose<CleaningData>((ref) async {
  final repo = ref.watch(cleaningRepoProvider);
  if (repo == null) return CleaningData.empty;
  return repo.load();
});

final cleaningLogDetailProvider =
    FutureProvider.autoDispose.family<CleaningLogDetail, String>((ref, logId) async {
  final repo = ref.watch(cleaningRepoProvider)!;
  return repo.logDetail(logId);
});
