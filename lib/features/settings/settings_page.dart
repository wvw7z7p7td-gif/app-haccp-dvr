import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/models/app_role.dart';
import 'invites_section.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider).valueOrNull ?? const <Membership>[];
    final active = ref.watch(activeMembershipProvider);
    final user = ref.watch(sessionProvider)?.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.email ?? '—'),
            subtitle: Text(active?.role.label ?? ''),
          ),
          const Divider(),
          if (memberships.length > 1) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Azienda attiva'),
            ),
            RadioGroup<String>(
              groupValue: active?.companyId,
              onChanged: (v) => ref.read(activeCompanyIdProvider.notifier).state = v,
              child: Column(children: [
                for (final m in memberships)
                  RadioListTile<String>(
                    value: m.companyId,
                    title: Text(m.companyName),
                    subtitle: Text(m.role.label),
                  ),
              ]),
            ),
            const Divider(),
          ],
          if (active?.role.isAdmin == true) ...[
            InvitesSection(companyId: active!.companyId),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Esci'),
            onTap: () async {
              await ref.read(supabaseProvider).auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
