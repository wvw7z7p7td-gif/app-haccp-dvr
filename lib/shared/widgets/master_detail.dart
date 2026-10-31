import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';

/// Lista + dettaglio: affiancati su tablet (>=840), a navigazione push su smartphone.
class MasterDetail<T> extends StatefulWidget {
  const MasterDetail({
    super.key,
    required this.items,
    required this.titleOf,
    required this.detailBuilder,
    this.subtitleOf,
    this.leadingOf,
    this.itemBuilder,
    this.sectionOf,
    this.emptyLabel = 'Nessun elemento',
    this.placeholder = 'Seleziona un elemento',
  });

  final List<T> items;
  final String Function(T) titleOf;
  final String Function(T)? subtitleOf;
  final Widget Function(T)? leadingOf;

  /// Se presente sostituisce il ListTile con una card personalizzata.
  /// [open] apre il dettaglio (affiancato su tablet, pagina su smartphone).
  final Widget Function(BuildContext context, T item, bool selected, VoidCallback open)? itemBuilder;

  /// Se presente, mostra un'intestazione quando la sezione cambia (elementi gia' ordinati).
  final String Function(T)? sectionOf;
  final Widget Function(BuildContext, T) detailBuilder;
  final String emptyLabel;
  final String placeholder;

  @override
  State<MasterDetail<T>> createState() => _MasterDetailState<T>();
}

class _MasterDetailState<T> extends State<MasterDetail<T>> {
  T? _selected;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return Center(child: Text(widget.emptyLabel));

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= Breakpoints.masterDetail;

      void open(T item) {
        if (wide) {
          setState(() => _selected = item);
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (ctx) => Scaffold(
              appBar: AppBar(title: Text(widget.titleOf(item))),
              body: widget.detailBuilder(ctx, item),
            ),
          ));
        }
      }

      final Widget list = widget.itemBuilder != null
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final item = widget.items[i];
                final section = widget.sectionOf?.call(item);
                final prev = i == 0 ? null : widget.sectionOf?.call(widget.items[i - 1]);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (section != null && section != prev)
                    Padding(
                      padding: EdgeInsets.fromLTRB(4, i == 0 ? 8 : 20, 4, 8),
                      child: Text(section,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: widget.itemBuilder!(context, item, wide && item == _selected, () => open(item)),
                  ),
                ]);
              },
            )
          : ListView.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                return ListTile(
                  minVerticalPadding: 12,
                  selected: wide && item == _selected,
                  leading: widget.leadingOf?.call(item),
                  title: Text(widget.titleOf(item)),
                  subtitle: widget.subtitleOf == null ? null : Text(widget.subtitleOf!(item)),
                  trailing: wide ? null : const Icon(Icons.chevron_right),
                  onTap: () => open(item),
                );
              },
            );

      if (!wide) return list;

      return Row(children: [
        SizedBox(width: 360, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? Center(child: Text(widget.placeholder))
              : widget.detailBuilder(context, _selected as T),
        ),
      ]);
    });
  }
}
