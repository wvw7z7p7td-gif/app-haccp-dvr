import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Sessione corrente; si ricalcola a ogni evento di autenticazione.
final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession;
});

class Membership {
  const Membership({required this.companyId, required this.companyName, required this.role});

  final String companyId;
  final String companyName;
  final AppRole role;

  factory Membership.fromMap(Map<String, dynamic> map) {
    final company = map['companies'] as Map<String, dynamic>?;
    return Membership(
      companyId: map['company_id'] as String,
      companyName: (company?['name'] as String?) ?? 'Azienda',
      role: AppRole.fromDb(map['role'] as String),
    );
  }
}

/// Aziende a cui l'utente appartiene (un consulente puo' averne molte).
final membershipsProvider = FutureProvider<List<Membership>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final rows = await ref
      .read(supabaseProvider)
      .from('company_members')
      .select('company_id, role, companies(name)')
      .eq('user_id', session.user.id)
      .eq('active', true);
  return rows.map<Membership>((r) => Membership.fromMap(r)).toList();
});

final activeCompanyIdProvider = StateProvider<String?>((ref) => null);

/// Azienda attiva (default: la prima). Null se non ancora caricata o assente.
final activeMembershipProvider = Provider<Membership?>((ref) {
  final list = ref.watch(membershipsProvider).valueOrNull ?? const <Membership>[];
  if (list.isEmpty) return null;
  final id = ref.watch(activeCompanyIdProvider);
  return list.firstWhere((m) => m.companyId == id, orElse: () => list.first);
});
