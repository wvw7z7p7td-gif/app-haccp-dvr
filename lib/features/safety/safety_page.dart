import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/page_scaffold.dart';
import 'duvri/duvri_providers.dart';
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
    final duvri = ref.watch(duvriDataProvider);
    final duvriInfo = duvri.when(
      loading: () => 'Caricamento…',
      error: (_, __) => 'Dati non disponibili',
      data: (d) {
        final bad = d.nonCompliantContractors(today);
        final soon = d.docsExpiringSoon(today);
        final toClose = d.duvris.where((x) => x.needsClosing(today)).length;
        return [
          '${d.contractors.length} appaltatori',
          if (bad > 0) '$bad con documenti da sistemare',
          if (soon > 0) '$soon documenti in scadenza',
          if (toClose > 0) '$toClose DUVRI da chiudere',
        ].join(' · ');
      },
    );
    final duvriAlert = duvri.maybeWhen(
      data: (d) =>
          d.nonCompliantContractors(today) > 0 ||
          d.docsExpiringSoon(today) > 0 ||
          d.duvris.any((x) => x.needsClosing(today)),
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
        Card(
          color: duvriAlert ? cs.errorContainer : null,
          child: ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.handshake_outlined, size: 32),
            title: const Text('DUVRI e imprese appaltatrici'),
            subtitle: Text(duvriInfo),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/duvri'),
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
