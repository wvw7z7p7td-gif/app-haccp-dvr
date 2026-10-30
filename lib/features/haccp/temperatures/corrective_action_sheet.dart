import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/operator_selector.dart';
import 'temperature_models.dart';
import 'temperature_providers.dart';

const _causes = [
  'Porta lasciata aperta',
  'Guasto / malfunzionamento',
  'Sbrinamento in corso',
  'Sovraccarico di prodotto',
  'Mancanza di corrente',
  'Altro',
];

/// Flusso per uno scostamento. Restituisce true se l'operatore chiede di
/// ripetere subito la rilevazione, false/null altrimenti. Se l'operatore
/// sceglie "Rimanda", lo scostamento resta segnalato come da gestire.
Future<bool?> showCorrectiveActionSheet(
  BuildContext context, {
  required ControlPoint point,
  required TempReading reading,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => _CorrectiveSheet(point: point, reading: reading),
  );
}

class _CorrectiveSheet extends ConsumerStatefulWidget {
  const _CorrectiveSheet({required this.point, required this.reading});
  final ControlPoint point;
  final TempReading reading;

  @override
  ConsumerState<_CorrectiveSheet> createState() => _CorrectiveSheetState();
}

class _CorrectiveSheetState extends ConsumerState<_CorrectiveSheet> {
  final _action = TextEditingController();
  final _notes = TextEditingController();
  final _op = OperatorSelection();
  final _id = const Uuid().v4();
  String? _cause;
  ProductFate _fate = ProductFate.notApplicable;
  bool _retest = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _action.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_action.text.trim().length < 5) {
      setState(() => _error = 'Descrivi l\'azione svolta.');
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
      await ref.read(temperatureRepoProvider)!.insertCorrectiveAction(
            id: _id,
            readingId: widget.reading.id,
            cause: _cause,
            actionTaken: _action.text,
            fate: _fate,
            employeeId: _op.employee?.id,
            notes: _notes.text,
          );
      ref.invalidate(tempOverviewProvider);
      ref.invalidate(tempHistoryProvider(widget.point.id));
      if (mounted) Navigator.of(context).pop(_retest);
    } catch (_) {
      setState(() => _error =
          'Azione NON salvata (connessione assente o errore). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.warning_amber, color: cs.error),
            const SizedBox(width: 8),
            Expanded(child: Text('Scostamento di temperatura', style: t.textTheme.titleLarge)),
          ]),
          const SizedBox(height: 4),
          Text('${widget.point.name}: rilevati ${formatTemp(widget.reading.valueC)} '
              '(limiti ${widget.point.rangeLabel})'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _cause,
            decoration: const InputDecoration(labelText: 'Causa probabile'),
            items: [for (final c in _causes) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _cause = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _action,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Azione correttiva svolta *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProductFate>(
            initialValue: _fate,
            decoration: const InputDecoration(labelText: 'Destino del prodotto'),
            items: [
              for (final f in ProductFate.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _fate = v ?? _fate),
          ),
          const SizedBox(height: 12),
          OperatorSelector(selection: _op),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Note (facoltative)'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _retest,
            onChanged: (v) => setState(() => _retest = v ?? true),
            title: const Text('Ripeti subito la rilevazione'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Registra azione correttiva'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Rimanda (resta da gestire)'),
          ),
        ]),
      ),
    );
  }
}
