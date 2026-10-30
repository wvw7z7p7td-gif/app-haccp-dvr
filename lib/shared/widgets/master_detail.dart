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
    this.emptyLabel = 'Nessun elemento',
    this.placeholder = 'Seleziona un elemento',
  });

  final List<T> items;
  final String Function(T) titleOf;
  final String Function(T)? subtitleOf;
  final Widget Function(T)? leadingOf;
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

      final list = ListView.separated(
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
            onTap: () {
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
            },
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
