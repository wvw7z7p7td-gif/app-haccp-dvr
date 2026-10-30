import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/operator_selector.dart';
import '../../../shared/widgets/signature_pad.dart';
import 'cleaning_models.dart';
import 'cleaning_providers.dart';

/// Registra l'esecuzione di un piano. Restituisce true se salvata.
Future<bool?> showCleaningExecutionSheet(
  BuildContext context, {
  required CleaningPlan plan,
  required DateTime dueDate,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ExecutionSheet(plan: plan, dueDate: dueDate),
  );
}

class _ExecutionSheet extends ConsumerStatefulWidget {
  const _ExecutionSheet({required this.plan, required this.dueDate});
  final CleaningPlan plan;
  final DateTime dueDate;

  @override
  ConsumerState<_ExecutionSheet> createState() => _ExecutionSheetState();
}

class _ExecutionSheetState extends ConsumerState<_ExecutionSheet> {
  static const _uuid = Uuid();
  // Id stabili tra i tentativi: un nuovo invio non duplica la registrazione.
  late final String _logId = _uuid.v4();
  late final Map<String, String> _itemIds = {for (final i in widget.plan.items) i.id: _uuid.v4()};
  late final Map<String, bool> _checked = {for (final i in widget.plan.items) i.id: false};
  final _notes = TextEditingController();
  final _op = OperatorSelection();
  final _sig = SignatureController();
  final DateTime _performedAt = DateTime.now();
  CleaningStatus _status = CleaningStatus.done;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    _sig.dispose();
    super.dispose();
  }

  void _fail(String msg) => setState(() => _error = msg);

  Future<void> _save() async {
    final plan = widget.plan;
    if (_status == CleaningStatus.done) {
      if (_checked.values.any((v) => !v)) {
        return _fail('Spunta tutte le voci, oppure segna l\'attivita\' come non eseguita.');
      }
    } else if (_notes.text.trim().length < 5) {
      return _fail('Indica il motivo nelle note.');
    }
    final png = await _sig.toPng();
    if (_status == CleaningStatus.done && png == null) {
      return _fail('La firma dell\'operatore e\' obbligatoria.');
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opError = await verifyOperator(ref, _op);
      if (opError != null) return _fail(opError);
      await ref.read(cleaningRepoProvider)!.saveLog(
            logId: _logId,
            plan: plan,
            dueDate: widget.dueDate,
            status: _status,
            performedAt: _performedAt,
            itemIds: _itemIds,
            employeeId: _op.employee?.id,
            notes: _notes.text,
            signaturePng: png,
          );
      ref.invalidate(cleaningDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _fail('Registrazione NON salvata (connessione assente o errore). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final plan = widget.plan;
    final done = _status == CleaningStatus.done;
    final info = <String>[
      if (plan.productName != null) 'Prodotto: ${plan.productName}',
      if (plan.dilution != null) 'Diluizione: ${plan.dilution}',
      if (plan.contactTimeMin != null) 'Tempo di contatto: ${plan.contactTimeMin} min',
      if (plan.method != null) 'Metodo: ${plan.method}',
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(plan.name, style: t.textTheme.titleLarge),
          Text([plan.scheduleLabel, if (plan.shift != null) plan.shift!].join(' · ')),
          if (info.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in info) Text(l)],
                ),
              ),
            ),
          const SizedBox(height: 16),
          SegmentedButton<CleaningStatus>(
            showSelectedIcon: false,
            segments: [
              for (final s in CleaningStatus.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {_status},
            onSelectionChanged: (v) => setState(() => _status = v.first),
          ),
          if (done && plan.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Operazioni', style: t.textTheme.titleMedium)),
              TextButton(
                onPressed: () => setState(() => _checked.updateAll((_, __) => true)),
                child: const Text('Spunta tutto'),
              ),
            ]),
            for (final item in plan.items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _checked[item.id] ?? false,
                title: Text(item.description),
                onChanged: (v) => setState(() => _checked[item.id] = v ?? false),
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: done ? 'Note (facoltative)' : 'Motivo *',
            ),
          ),
          const SizedBox(height: 12),
          OperatorSelector(selection: _op),
          const SizedBox(height: 16),
          Text(done ? 'Firma dell\'operatore *' : 'Firma dell\'operatore (facoltativa)',
              style: t.textTheme.titleSmall),
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
                : const Text('Salva e firma'),
          ),
          if (plan.requiresApproval && done)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Questa attivita\' richiede la controfirma di un responsabile.',
                  style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            ),
        ]),
      ),
    );
  }
}
