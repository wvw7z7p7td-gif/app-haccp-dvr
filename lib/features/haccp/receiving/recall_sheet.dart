import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/operator_selector.dart';
import '../temperatures/temperature_models.dart' show parseTemp;
import 'receiving_models.dart';
import 'receiving_providers.dart';

/// Registra il ritiro / smaltimento / reso di un lotto. true se salvato.
Future<bool?> showRecallSheet(BuildContext context, ReceiptLine line) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RecallSheet(line: line),
  );
}

class _RecallSheet extends ConsumerStatefulWidget {
  const _RecallSheet({required this.line});
  final ReceiptLine line;
  @override
  ConsumerState<_RecallSheet> createState() => _RecallSheetState();
}

class _RecallSheetState extends ConsumerState<_RecallSheet> {
  final _id = const Uuid().v4();
  late final DateTime _at = DateTime.now();
  final _reason = TextEditingController();
  final _qty = TextEditingController();
  final _op = OperatorSelection();
  RecallAction _action = RecallAction.withdrawn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Indica il motivo.');
      return;
    }
    if (_qty.text.trim().isNotEmpty && parseTemp(_qty.text) == null) {
      setState(() => _error = 'Quantita\' non valida.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opError = await verifyOperator(ref, _op);
      if (opError != null) {
        setState(() => _error = opError);
        return;
      }
      await ref.read(receivingRepoProvider)!.saveRecall(
            id: _id,
            line: widget.line,
            action: _action,
            reason: _reason.text,
            performedAt: _at,
            quantity: parseTemp(_qty.text),
            employeeId: _op.employee?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Registrazione NON salvata. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = widget.line;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ritiro / smaltimento', style: t.textTheme.titleLarge),
          Text('${l.productName} · lotto ${l.lotCode ?? '—'}'),
          const SizedBox(height: 12),
          RadioGroup<RecallAction>(
            groupValue: _action,
            onChanged: (v) => setState(() => _action = v ?? _action),
            child: Column(children: [
              for (final a in RecallAction.values)
                RadioListTile<RecallAction>(
                  contentPadding: EdgeInsets.zero,
                  value: a,
                  title: Text(a.label),
                ),
            ]),
          ),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            decoration: InputDecoration(labelText: 'Quantita\' (${l.unit ?? 'unita\''})'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo (obbligatorio)'),
          ),
          const SizedBox(height: 12),
          OperatorSelector(selection: _op),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Registra'),
          ),
        ]),
      ),
    );
  }
}
