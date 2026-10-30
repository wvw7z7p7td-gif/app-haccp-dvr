import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'menu_item_sheet.dart';
import 'menu_models.dart';
import 'menu_providers.dart';

class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});
  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage> {
  final Set<String> _avoid = {};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(menuDataProvider);
    return PageScaffold(
      title: 'Menu e allergeni',
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => showMenuItemSheet(context, data: data.valueOrNull ?? MenuData.empty),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo piatto'),
            )
          : null,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Impossibile caricare il menu.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => ref.invalidate(menuDataProvider), child: const Text('Riprova')),
          ]),
        ),
        data: (d) => _body(context, d, isAdmin),
      ),
    );
  }

  Widget _body(BuildContext context, MenuData d, bool isAdmin) {
    final cs = Theme.of(context).colorScheme;
    final q = _search.trim().toLowerCase();
    var items = d.items.where((i) => i.active && (q.isEmpty || i.name.toLowerCase().contains(q))).toList();
    if (_avoid.isNotEmpty) {
      int rank(MenuItem i) => switch (suitabilityFor(i, _avoid)) {
            Suitability.safe => 0,
            Suitability.traces => 1,
            Suitability.unverified => 2,
            Suitability.contains => 3,
          };
      items.sort((a, b) => rank(a).compareTo(rank(b)));
    }

    return Column(children: [
      if (d.toReview > 0)
        MaterialBanner(
          backgroundColor: cs.tertiaryContainer,
          leading: Icon(Icons.rule, color: cs.onTertiaryContainer),
          content: Text(
              '${d.toReview} piatt${d.toReview == 1 ? 'o' : 'i'} con allergeni da verificare: '
              'non vengono mai indicati come sicuri.',
              style: TextStyle(color: cs.onTertiaryContainer)),
          actions: const [SizedBox.shrink()],
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cerca piatto'),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Il cliente deve evitare:', style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final a in d.allergens)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: FilterChip(
                  label: Text(a.name),
                  selected: _avoid.contains(a.id),
                  onSelected: (v) => setState(() => v ? _avoid.add(a.id) : _avoid.remove(a.id)),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: items.isEmpty
            ? Center(child: Text(d.items.isEmpty ? 'Nessun piatto in menu.' : 'Nessun risultato.'))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(menuDataProvider);
                  await ref.read(menuDataProvider.future);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _tile(context, d, items[i], isAdmin),
                ),
              ),
      ),
    ]);
  }

  Widget _tile(BuildContext context, MenuData d, MenuItem item, bool isAdmin) {
    final cs = Theme.of(context).colorScheme;
    final suit = suitabilityFor(item, _avoid);
    final names = [
      for (final a in d.allergens)
        if (item.contains.contains(a.id)) a.name.split(' ').first,
    ];
    Widget? badge;
    if (_avoid.isNotEmpty || item.needsReview) {
      final (text, bg, fg) = switch (suit) {
        Suitability.safe => ('Adatto', cs.secondaryContainer, cs.onSecondaryContainer),
        Suitability.traces => ('Tracce', cs.tertiaryContainer, cs.onTertiaryContainer),
        Suitability.contains => ('Contiene', cs.errorContainer, cs.onErrorContainer),
        Suitability.unverified => ('Da verificare', cs.tertiaryContainer, cs.onTertiaryContainer),
      };
      badge = Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: bg,
        side: BorderSide.none,
        label: Text(item.needsReview && _avoid.isEmpty ? 'Da verificare' : text, style: TextStyle(color: fg)),
      );
    }
    return ListTile(
      title: Text(item.name),
      subtitle: Text([
        if (item.category != null) item.category!,
        if (item.needsReview) 'allergeni non verificati' else if (names.isEmpty) 'nessun allergene' else names.join(', '),
      ].join(' · ')),
      trailing: badge,
      onTap: () => showMenuItemSheet(context, data: d, existing: item, readOnly: !isAdmin),
    );
  }
}
