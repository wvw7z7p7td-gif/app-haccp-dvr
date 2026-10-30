import 'package:flutter/material.dart';

import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/placeholder_view.dart';

class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: 'Sicurezza sul lavoro',
      body: PlaceholderView(
        icon: Icons.health_and_safety,
        title: 'DVR, formazione e DPI',
        hint: 'Prossimo passo: scadenzario formazione/DPI e archivio DVR.',
      ),
    );
  }
}
