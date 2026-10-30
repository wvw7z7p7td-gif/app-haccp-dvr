import 'package:flutter/material.dart';

/// Contenuto provvisorio per i moduli non ancora implementati.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.icon, required this.title, required this.hint});

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: t.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
