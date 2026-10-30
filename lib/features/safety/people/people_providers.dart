import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'people_models.dart';
import 'people_repository.dart';

final peopleRepoProvider = Provider<PeopleRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return PeopleRepository(ref.watch(supabaseProvider), m.companyId);
});

final peopleDataProvider = FutureProvider.autoDispose<PeopleData>((ref) async {
  final repo = ref.watch(peopleRepoProvider);
  if (repo == null) return PeopleData.empty;
  return repo.load();
});
