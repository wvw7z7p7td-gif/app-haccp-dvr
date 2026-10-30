import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'receiving_models.dart';
import 'receiving_repository.dart';

final receivingRepoProvider = Provider<ReceivingRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return ReceivingRepository(ref.watch(supabaseProvider), m.companyId);
});

final receivingDataProvider = FutureProvider.autoDispose<ReceivingData>((ref) async {
  final repo = ref.watch(receivingRepoProvider);
  if (repo == null) return ReceivingData.empty;
  return repo.load();
});

final catalogProductsProvider = FutureProvider.autoDispose<List<CatalogProduct>>((ref) async {
  final repo = ref.watch(receivingRepoProvider);
  if (repo == null) return const [];
  return repo.products();
});

final lotSearchProvider =
    FutureProvider.autoDispose.family<List<LotHit>, String>((ref, q) async {
  final repo = ref.watch(receivingRepoProvider);
  if (repo == null) return const [];
  return repo.searchLot(q);
});
