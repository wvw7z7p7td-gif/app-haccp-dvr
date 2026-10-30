import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import 'incident_models.dart';
import 'incident_repository.dart';

final incidentRepoProvider = Provider<IncidentRepository?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return IncidentRepository(ref.watch(supabaseProvider), m.companyId);
});

final incidentDataProvider = FutureProvider.autoDispose<IncidentData>((ref) async {
  final repo = ref.watch(incidentRepoProvider);
  if (repo == null) return IncidentData.empty;
  return repo.load();
});
