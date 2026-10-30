import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'temperature_models.dart';
import 'temperature_repository.dart';

final temperatureRepoProvider = Provider<TemperatureRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return TemperatureRepository(ref.watch(supabaseProvider), m.companyId);
});

final tempOverviewProvider = FutureProvider.autoDispose<TempOverview>((ref) async {
  final repo = ref.watch(temperatureRepoProvider);
  if (repo == null) return TempOverview.empty;
  return repo.overview();
});

final tempHistoryProvider =
    FutureProvider.autoDispose.family<TempHistory, String>((ref, pointId) async {
  final repo = ref.watch(temperatureRepoProvider);
  if (repo == null) return const TempHistory(readings: [], withAction: {});
  return repo.history(pointId);
});
