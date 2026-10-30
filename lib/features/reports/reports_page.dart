import 'package:flutter/material.dart';

import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/placeholder_view.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: 'Report',
      body: PlaceholderView(
        icon: Icons.description,
        title: 'Report e modalita\' ispezione',
        hint: 'Prossimo passo: esportazione PDF dei registri per periodo.',
      ),
    );
  }
}
