import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/operator_selector.dart';
import '../../../shared/widgets/signature_pad.dart';
import 'cleaning_models.dart';
import 'cleaning_providers.dart';

Future<bool?> showCleaningApprovalSheet(BuildContext context, {required CleaningLog log}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ApprovalSheet(log: log),
  );
}

class _ApprovalSheet extends ConsumerStatefulWidget {
  const _ApprovalSheet({required this.log});
  final CleaningLog log;

  @override
  ConsumerState<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends ConsumerState<_ApprovalSheet> {
  final _approvalId = const Uuid().v4();
  final _op = OperatorSelection();
  final _sig = SignatureController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sig.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final png = await _sig.toPng();
    if (png == null) {
      setState(() => _error = 'La firma del responsabile e\' obbligatoria.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final err = await verifyOperator(ref, _op, supervisorsOnly: true);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      await ref.read(cleaningRepoProvider)!.approve(
            approvalId: _approvalId,
            logId: widget.log.id,
            employeeId: _op.employee!.id,
            signaturePng: png,
          );
      ref.invalidate(cleaningDataProvider);
      ref.invalidate(cleaningLogDetailProvider(widget.log.id));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Controfirma NON salvata: ${_reason(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // I controlli del database (responsabile, stessa persona) hanno messaggi chiari.
  String _reason(Object e) {
    final msg = e.toString();
    if (msg.contains('responsabile') || msg.contains('stesso operatore')) {
      final m = RegExp(r'message: ([^,}]+)').firstMatch(msg);
      return m?.group(1) ?? 'controllo non superato.';
    }
    return 'connessione assente o errore. Riprova.';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final log = widget.log;
    final when = DateFormat('dd/MM/yyyy', 'it_IT').format(log.dueDate);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Controfirma', style: t.textTheme.titleLarge),
          Text('${log.planName} · $when'
              '${log.employeeName != null ? ' · eseguita da ${log.employeeName}' : ''}'),
          const SizedBox(height: 16),
          OperatorSelector(
            selection: _op,
            label: 'Responsabile',
            supervisorsOnly: true,
            excludeEmployeeId: log.employeeId,
          ),
          const SizedBox(height: 16),
          Text('Firma del responsabile *', style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          SignaturePad(controller: _sig),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Controfirma'),
          ),
        ]),
      ),
    );
  }
}
