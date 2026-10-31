import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/models/app_role.dart';

class PendingInvite {
  const PendingInvite({required this.id, required this.email, required this.role});
  final String id;
  final String email;
  final AppRole role;
}

final pendingInvitesProvider =
    FutureProvider.autoDispose.family<List<PendingInvite>, String>((ref, companyId) async {
  final rows = await ref
      .read(supabaseProvider)
      .from('company_invites')
      .select('id, email, role')
      .eq('company_id', companyId)
      .isFilter('accepted_at', null)
      .order('created_at');
  return [
    for (final r in rows)
      PendingInvite(
          id: r['id'] as String, email: r['email'] as String, role: AppRole.fromDb(r['role'] as String))
  ];
});

/// Solo per l'amministratore: invita colleghi e consulenti per email.
class InvitesSection extends ConsumerStatefulWidget {
  const InvitesSection({super.key, required this.companyId});
  final String companyId;
  @override
  ConsumerState<InvitesSection> createState() => _InvitesSectionState();
}

class _InvitesSectionState extends ConsumerState<InvitesSection> {
  final _email = TextEditingController();
  AppRole _role = AppRole.employee;
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@') || email.length < 5) {
      setState(() => _msg = 'Inserisci un\'email valida.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await ref.read(supabaseProvider).from('company_invites').insert({
        'company_id': widget.companyId,
        'email': email,
        'role': _role.dbValue,
      });
      _email.clear();
      ref.invalidate(pendingInvitesProvider(widget.companyId));
      setState(() => _msg = 'Invito creato. Il collega deve registrarsi con questa email.');
    } catch (_) {
      setState(() => _msg = 'Invito non creato (forse esiste gia\').');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id) async {
    await ref.read(supabaseProvider).from('company_invites').delete().eq('id', id);
    ref.invalidate(pendingInvitesProvider(widget.companyId));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final invites = ref.watch(pendingInvitesProvider(widget.companyId)).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Invita un collega o un consulente', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<AppRole>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Ruolo'),
          items: [for (final r in AppRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _invite, child: const Text('Invita')),
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
        for (final i in invites)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i.email),
            subtitle: Text('${i.role.label} · in attesa'),
            trailing: IconButton(
              tooltip: 'Annulla invito',
              icon: const Icon(Icons.close),
              onPressed: () => _remove(i.id),
            ),
          ),
      ]),
    );
  }
}
