import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cleaning_models.dart';
import 'cleaning_providers.dart';

Future<void> showCleaningLogDetail(BuildContext context, CleaningLog log) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LogDetail(log: log),
  );
}

class _LogDetail extends ConsumerWidget {
  const _LogDetail({required this.log});
  final CleaningLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final detail = ref.watch(cleaningLogDetailProvider(log.id));
    final date = DateFormat('dd/MM/yyyy', 'it_IT').format(log.dueDate);
    final time = DateFormat('dd/MM/yyyy HH:mm', 'it_IT').format(log.performedAt);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(log.planName, style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Giorno $date · ${log.status.label}'),
        Text('Registrata il $time${log.employeeName != null ? ' da ${log.employeeName}' : ''}'),
        if (log.notes != null) ...[
          const SizedBox(height: 8),
          Text('Note: ${log.notes}'),
        ],
        const SizedBox(height: 16),
        detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Dettagli non disponibili.'),
          data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (d.items.isNotEmpty) ...[
              Text('Operazioni', style: t.textTheme.titleMedium),
              for (final i in d.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(i.done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: i.done ? t.colorScheme.primary : null),
                  title: Text(i.text),
                ),
              const SizedBox(height: 8),
            ],
            if (d.signatureUrl != null) ...[
              Text('Firma operatore', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              _Signature(url: d.signatureUrl!),
              const SizedBox(height: 16),
            ],
            if (log.requiresApproval)
              if (d.approverName != null) ...[
                Text(
                  'Controfirmata da ${d.approverName}'
                  '${d.approvedAt != null ? ' il ${DateFormat('dd/MM/yyyy HH:mm', 'it_IT').format(d.approvedAt!)}' : ''}',
                  style: t.textTheme.titleMedium,
                ),
                if (d.approvalSignatureUrl != null) ...[
                  const SizedBox(height: 8),
                  _Signature(url: d.approvalSignatureUrl!),
                ],
              ] else
                Text('In attesa di controfirma del responsabile.',
                    style: TextStyle(color: t.colorScheme.error)),
          ]),
        ),
      ]),
    );
  }
}

class _Signature extends StatelessWidget {
  const _Signature({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 110,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Text('Firma non disponibile.',
            style: TextStyle(color: Colors.black54)),
      ),
    );
  }
}
