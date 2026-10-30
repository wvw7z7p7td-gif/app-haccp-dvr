import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'sync_status_chip.dart';

/// Scaffold comune alle pagine principali: titolo, stato sync, accesso impostazioni.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.bottom,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: bottom,
        actions: [
          const SyncStatusChip(),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/impostazioni'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
