import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';

import '../../../core/offline/offline_providers.dart';
import '../../../core/offline/pending_queue.dart';
import '../../../shared/widgets/operator_selector.dart';
import 'temperature_models.dart';
import 'temperature_providers.dart';

/// Restituisce la rilevazione salvata, o null se annullata.
Future<TempReading?> showReadingSheet(BuildContext context, ControlPoint point) {
  return showModalBottomSheet<TempReading>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReadingSheet(point: point),
  );
}

class _ReadingSheet extends ConsumerStatefulWidget {
  const _ReadingSheet({required this.point});
  final ControlPoint point;

  @override
  ConsumerState<_ReadingSheet> createState() => _ReadingSheetState();
}

class _ReadingSheetState extends ConsumerState<_ReadingSheet> {
  final _value = TextEditingController();
  final _notes = TextEditingController();
  final _op = OperatorSelection();
  // Stabile tra i tentativi: un doppio invio non crea due registrazioni.
  final _id = const Uuid().v4();
  late final DateTime _measuredAt = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _nudge(double delta) {
    final p = widget.point;
    final base = parseTemp(_value.text) ??
        ((p.minC != null && p.maxC != null) ? (p.minC! + p.maxC!) / 2 : 0.0);
    setState(() => _value.text = (base + delta).toStringAsFixed(1).replaceAll('.', ','));
  }

  Future<void> _save() async {
    final v = parseTemp(_value.text);
    if (v == null || v < -100 || v > 300) {
      setState(() => _error = 'Inserisci una temperatura valida.');
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
      final repo = ref.read(temperatureRepoProvider)!;
      final saved = await repo.insertReading(
        id: _id,
        point: widget.point,
        value: v,
        measuredAt: _measuredAt,
        employeeId: _op.employee?.id,
        notes: _notes.text,
      );
      ref.invalidate(tempOverviewProvider);
      ref.invalidate(tempHistoryProvider(widget.point.id));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (isPermanentRejection(e)) {
        setState(() => _error = 'Registrazione rifiutata dal server. Controlla i dati.');
      } else {
        // Nessuna connessione: la rilevazione resta sul dispositivo e parte appena si torna online.
        await _queueOffline(v);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _queueOffline(double v) async {
    final queue = ref.read(pendingQueueProvider);
    final m = ref.read(activeMembershipProvider);
    if (queue == null || m == null) {
      setState(() => _error = 'Registrazione NON salvata (connessione assente). Riprova.');
      return;
    }
    final notes = _notes.text.trim();
    await queue.add(PendingOp(
      table: 'temp_readings',
      queuedAt: DateTime.now(),
      payload: {
        'id': _id,
        'company_id': m.companyId,
        'site_id': widget.point.siteId,
        'control_point_id': widget.point.id,
        'value_c': v,
        'measured_at': _measuredAt.toUtc().toIso8601String(),
        'employee_id': _op.employee?.id,
        'source': 'manual',
        'notes': notes.isEmpty ? null : notes,
      },
    ));
    await ref.read(pendingCountProvider.notifier).refreshCount();
    if (!mounted) return;
    final out = widget.point.isOutOfRange(v);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(out
          ? 'Offline: rilevazione salvata sul dispositivo. ATTENZIONE: valore fuori limite, '
              'gestisci subito il prodotto e registra l\'azione correttiva appena torni online.'
          : 'Offline: rilevazione salvata sul dispositivo, verra\' inviata appena torna la connessione.'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final v = parseTemp(_value.text);
    final out = v != null && widget.point.isOutOfRange(v);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nuova rilevazione', style: t.textTheme.titleLarge),
          Text('${widget.point.name} · limiti ${widget.point.rangeLabel}'),
          const SizedBox(height: 16),
          Row(children: [
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: '-0,5',
              onPressed: () => _nudge(-0.5),
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _value,
                autofocus: true,
                textAlign: TextAlign.center,
                style: t.textTheme.displaySmall,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9,.]'))],
                decoration: const InputDecoration(suffixText: '°C'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: '+0,5',
              onPressed: () => _nudge(0.5),
              icon: const Icon(Icons.add),
            ),
          ]),
          if (v != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                out
                    ? 'Fuori dai limiti: dovrai registrare un\'azione correttiva.'
                    : 'Nei limiti.',
                textAlign: TextAlign.center,
                style: TextStyle(color: out ? cs.error : cs.primary),
              ),
            ),
          const SizedBox(height: 16),
          OperatorSelector(selection: _op),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Note (facoltative)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salva rilevazione'),
          ),
        ]),
      ),
    );
  }
}
