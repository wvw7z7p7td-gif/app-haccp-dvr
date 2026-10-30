import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/page_scaffold.dart';
import 'dvr/dvr_providers.dart';

class SafetyPage extends ConsumerWidget {
  const SafetyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dvr = ref.watch(dvrDataProvider);
    final today = DateTime.now();
    final dvrInfo = dvr.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        final cur = d.current;
        final parts = <String>[
          cur == null ? 'nessuna versione in vigore' : 'versione ${cur.version} in vigore',
          '${d.risks.length} rischi',
          if (d.overdueActions(today) > 0) '${d.overdueActions(today)} azioni scadute',
        ];
        return parts.join(' · ');
      },
    );
    final dvrAlert = dvr.maybeWhen(
      data: (d) =>
          d.current == null ||
          d.current!.reviewDue(today) ||
          d.overdueActions(today) > 0 ||
          d.missingOfficers(today).isNotEmpty,
      orElse: () => false,
    );
    final cs = Theme.of(context).colorScheme;
    return PageScaffold(
      title: 'Sicurezza sul lavoro',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: dvrAlert ? cs.errorContainer : null,
          child: ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.assignment_outlined, size: 32),
            title: const Text('DVR - Valutazione dei rischi'),
            subtitle: Text(dvrInfo),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/dvr'),
          ),
        ),
        const Card(
          child: ListTile(
            minVerticalPadding: 16,
            leading: Icon(Icons.handshake_outlined, size: 32),
            title: Text('DUVRI e imprese appaltatrici'),
            subtitle: Text('In arrivo'),
          ),
        ),
        const Card(
          child: ListTile(
            minVerticalPadding: 16,
            leading: Icon(Icons.school_outlined, size: 32),
            title: Text('Formazione, DPI e scadenze'),
            subtitle: Text('In arrivo'),
          ),
        ),
      ]),
    );
  }
}
