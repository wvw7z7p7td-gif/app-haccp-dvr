import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/providers.dart';
import '../router/destinations.dart';
import 'breakpoints.dart';

/// Shell di navigazione adattiva:
///  - smartphone (<600): NavigationBar in basso
///  - tablet portrait (600-1024): NavigationRail compatta
///  - tablet landscape (>=1024): NavigationRail estesa con etichette
/// Le voci visibili dipendono dal ruolo nell'azienda attiva.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider);
    final active = ref.watch(activeMembershipProvider);

    if (memberships.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (memberships.hasError) {
      return _Message(
        icon: Icons.error_outline,
        text: 'Impossibile caricare i dati dell\'account.',
        actionLabel: 'Riprova',
        onAction: () => ref.invalidate(membershipsProvider),
      );
    }
    if (active == null) {
      return _Message(
        icon: Icons.business_outlined,
        text: 'Nessuna azienda associata a questo account.\nChiedi al titolare di invitarti.',
        actionLabel: 'Esci',
        onAction: () => ref.read(supabaseProvider).auth.signOut(),
      );
    }

    final items = kDestinations.where((d) => d.roles.contains(active.role)).toList();
    final current = navigationShell.currentIndex;
    var selected = items.indexWhere((d) => d.branchIndex == current);
    if (selected < 0) selected = 0;

    void onSelect(int i) => navigationShell.goBranch(
          items[i].branchIndex,
          initialLocation: items[i].branchIndex == current,
        );

    final width = MediaQuery.sizeOf(context).width;

    if (width < Breakpoints.medium) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in items)
              NavigationDestination(
                icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }

    final extended = width >= Breakpoints.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: selected,
            onDestinationSelected: onSelect,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: extended
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(active.companyName,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    )
                  : const Icon(Icons.storefront_outlined),
            ),
            destinations: [
              for (final d in items)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, required this.actionLabel, required this.onAction});

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
