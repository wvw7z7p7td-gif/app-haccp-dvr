
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/data/site_repository.dart';
import '../../../shared/widgets/operator_selector.dart';
import '../temperatures/temperature_models.dart' show parseTemp;
import 'receiving_models.dart';
import 'receiving_providers.dart';
import 'receiving_repository.dart';

/// Registra un ricevimento merci. Restituisce true se salvato.
Future<bool?> showReceiptSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ReceiptSheet(),
  );
}

class _LineDraft {
  _LineDraft() : id = const Uuid().v4();
  final String id;
  final name = TextEditingController();
  final nameFocus = FocusNode();
  final lot = TextEditingController();
  final qty = TextEditingController();
  final unit = TextEditingController(text: 'kg');
  final temp = TextEditingController();
  final minC = TextEditingController();
  final maxC = TextEditingController();
  final notes = TextEditingController();
  String? productId;
  DateTime? expiry;
  ExpiryKind kind = ExpiryKind.useBy;
  bool packagingOk = true;
  bool labelOk = true;
  ReceiptOutcome? outcome; // null = proposto dal sistema

  void dispose() {
    for (final c in [name, lot, qty, unit, temp, minC, maxC, notes]) {
      c.dispose();
    }
    nameFocus.dispose();
  }

  LineCheck check(DateTime receivedOn) => evaluateLine(
        tempC: parseTemp(temp.text),
        minC: parseTemp(minC.text),
        maxC: parseTemp(maxC.text),
        expiry: expiry,
        kind: kind,
        receivedOn: receivedOn,
      );

  ReceiptOutcome effective(LineCheck c) {
    if (outcome != null && c.allowed.contains(outcome)) return outcome!;
    if (!packagingOk || !labelOk) {
      return c.allowed.contains(ReceiptOutcome.reservation)
          ? ReceiptOutcome.reservation
          : c.suggested;
    }
    return c.suggested;
  }
}

class _ReceiptSheet extends ConsumerStatefulWidget {
  const _ReceiptSheet();
  @override
  ConsumerState<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends ConsumerState<_ReceiptSheet> {
  final _receiptId = const Uuid().v4(); // stabile tra i tentativi
  late final DateTime _receivedAt = DateTime.now();
  final _docNumber = TextEditingController();
  final _notes = TextEditingController();
  final _newSupplier = TextEditingController();
  final _op = OperatorSelection();
  final _lines = <_LineDraft>[_LineDraft()];
  String? _supplierId;
  String? _siteId;
  DateTime _docDate = DateTime.now();
  bool _vehicleOk = true;
  Uint8List? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _docNumber.dispose();
    _notes.dispose();
    _newSupplier.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1800, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _error = 'Foto troppo grande (max 5 MB).');
        return;
      }
      setState(() => _photo = bytes);
    } catch (_) {
      setState(() => _error = 'Fotocamera non disponibile.');
    }
  }

  Future<void> _pickDate(DateTime? initial, ValueChanged<DateTime> onPicked,
      {DateTime? first, DateTime? last}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime(2100),
    );
    if (d != null) onPicked(d);
  }

  String? _validate(List<Supplier> suppliers) {
    final creating = _supplierId == '__new__';
    if (_supplierId == null) return 'Seleziona il fornitore.';
    if (creating && _newSupplier.text.trim().isEmpty) return 'Inserisci il nome del fornitore.';
    if (_lines.isEmpty) return 'Aggiungi almeno un prodotto.';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final n = i + 1;
      if (l.name.text.trim().isEmpty) return 'Prodotto $n: inserisci il nome.';
      if (l.temp.text.trim().isNotEmpty && parseTemp(l.temp.text) == null) {
        return 'Prodotto $n: temperatura non valida.';
      }
      if (l.qty.text.trim().isNotEmpty && parseTemp(l.qty.text) == null) {
        return 'Prodotto $n: quantita\' non valida.';
      }
      final c = l.check(_receivedAt);
      final out = l.effective(c);
      if (out != ReceiptOutcome.accepted && l.notes.text.trim().isEmpty) {
        return 'Prodotto $n: indica il motivo (${out.label.toLowerCase()}).';
      }
    }
    return null;
  }

  Future<void> _save(List<Supplier> suppliers) async {
    final err = _validate(suppliers);
    if (err != null) {
      setState(() => _error = err);
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
      final repo = ref.read(receivingRepoProvider)!;

      if (_supplierId == '__new__') {
        final s = await repo.createSupplier(_newSupplier.text);
        _supplierId = s.id; // un nuovo tentativo non lo ricrea
      }

      var siteId = _siteId;
      if (siteId == null) {
        final sites = await ref.read(sitesProvider.future);
        siteId = sites.isNotEmpty
            ? sites.first.id
            : await ref.read(siteRepoProvider)!.createSite('Sede principale');
        _siteId = siteId;
      }

      final catalog = ref.read(catalogProductsProvider).valueOrNull ?? const <CatalogProduct>[];
      final lines = <NewReceiptLine>[];
      for (final l in _lines) {
        final minC = parseTemp(l.minC.text);
        final maxC = parseTemp(l.maxC.text);
        // Prodotto nuovo con limiti: lo salvo in anagrafica per le consegne successive.
        if (l.productId == null && (minC != null || maxC != null)) {
          final existing = catalog
              .where((p) => p.name.toLowerCase() == l.name.text.trim().toLowerCase())
              .firstOrNull;
          l.productId = existing?.id ??
              await repo.createProduct(
                name: l.name.text,
                supplierId: _supplierId,
                minC: minC,
                maxC: maxC,
              );
        }
        final c = l.check(_receivedAt);
        lines.add(NewReceiptLine(
          id: l.id,
          productId: l.productId,
          productName: l.name.text,
          lotCode: l.lot.text,
          expiry: l.expiry,
          expiryKind: l.kind,
          quantity: parseTemp(l.qty.text),
          unit: l.unit.text,
          tempC: parseTemp(l.temp.text),
          minC: minC,
          maxC: maxC,
          packagingOk: l.packagingOk,
          labelOk: l.labelOk,
          outcome: l.effective(c),
          notes: l.notes.text,
        ));
      }

      await repo.saveReceipt(
        receiptId: _receiptId,
        siteId: siteId,
        supplierId: _supplierId!,
        docDate: _docDate,
        receivedAt: _receivedAt,
        docNumber: _docNumber.text,
        employeeId: _op.employee?.id,
        vehicleOk: _vehicleOk,
        notes: _notes.text,
        photo: _photo,
        lines: lines,
      );
      ref.invalidate(receivingDataProvider);
      ref.invalidate(catalogProductsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error =
          'Ricevimento NON salvato (connessione assente o dati non validi). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final df = DateFormat('dd/MM/yyyy');
    final data = ref.watch(receivingDataProvider).valueOrNull ?? ReceivingData.empty;
    final suppliers = data.suppliers;
    final catalog = ref.watch(catalogProductsProvider).valueOrNull ?? const <CatalogProduct>[];
    final sites = ref.watch(sitesProvider).valueOrNull ?? const <SiteRef>[];
    final receivedOn = _receivedAt;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nuovo ricevimento merci', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _supplierId,
            decoration: const InputDecoration(labelText: 'Fornitore'),
            items: [
              for (final s in suppliers) DropdownMenuItem(value: s.id, child: Text(s.name)),
              const DropdownMenuItem(value: '__new__', child: Text('+ Nuovo fornitore…')),
            ],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
          if (_supplierId == '__new__')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _newSupplier,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ragione sociale del fornitore'),
              ),
            ),
          if (sites.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _siteId ?? sites.first.id,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [for (final s in sites) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) => _siteId = v,
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _docNumber,
                decoration: const InputDecoration(labelText: 'N. DDT / fattura'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(df.format(_docDate)),
              onPressed: () => _pickDate(_docDate, (d) => setState(() => _docDate = d),
                  last: DateTime.now()),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mezzo di trasporto e igiene conformi'),
            value: _vehicleOk,
            onChanged: (v) => setState(() => _vehicleOk = v),
          ),
          Row(children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_photo == null ? 'Foto del documento' : 'Rifai la foto'),
              onPressed: _takePhoto,
            ),
            if (_photo != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_photo!, height: 56, width: 56, fit: BoxFit.cover),
              ),
            ],
          ]),
          const Divider(height: 28),
          for (var i = 0; i < _lines.length; i++)
            _LineEditor(
              key: ValueKey(_lines[i].id),
              index: i + 1,
              draft: _lines[i],
              catalog: catalog,
              supplierId: _supplierId,
              receivedOn: receivedOn,
              canRemove: _lines.length > 1,
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _lines.removeAt(i).dispose()),
              onPickExpiry: () => _pickDate(
                _lines[i].expiry,
                (d) => setState(() => _lines[i].expiry = d),
                first: DateTime.now().subtract(const Duration(days: 365)),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi prodotto'),
            onPressed: () => setState(() => _lines.add(_LineDraft())),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Note generali (facoltative)'),
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
            onPressed: _busy ? null : () => _save(suppliers),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Registra ricevimento'),
          ),
        ]),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.catalog,
    required this.supplierId,
    required this.receivedOn,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onPickExpiry,
  });

  final int index;
  final _LineDraft draft;
  final List<CatalogProduct> catalog;
  final String? supplierId;
  final DateTime receivedOn;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onPickExpiry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final df = DateFormat('dd/MM/yyyy');
    final check = draft.check(receivedOn);
    final outcome = draft.effective(check);
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9,.]'))];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Prodotto $index', style: t.textTheme.titleSmall),
            const Spacer(),
            if (canRemove)
              IconButton(
                  tooltip: 'Rimuovi', onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
          RawAutocomplete<CatalogProduct>(
            textEditingController: draft.name,
            focusNode: draft.nameFocus,
            displayStringForOption: (p) => p.name,
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<CatalogProduct>.empty();
              return catalog
                  .where((p) =>
                      p.name.toLowerCase().contains(q) &&
                      (p.supplierId == null || p.supplierId == supplierId))
                  .take(6);
            },
            onSelected: (p) {
              draft.productId = p.id;
              draft.minC.text = p.minC == null ? '' : p.minC.toString().replaceAll('.', ',');
              draft.maxC.text = p.maxC == null ? '' : p.maxC.toString().replaceAll('.', ',');
              onChanged();
            },
            fieldViewBuilder: (ctx, controller, focus, _) => TextField(
              controller: controller,
              focusNode: focus,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Prodotto'),
              onChanged: (_) {
                draft.productId = null; // testo modificato a mano: non piu' legato al catalogo
                onChanged();
              },
            ),
            optionsViewBuilder: (ctx, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in options)
                        ListTile(dense: true, title: Text(o.name), onTap: () => onSelected(o)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: draft.lot,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Lotto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: draft.qty,
                keyboardType: decimal,
                inputFormatters: numFmt,
                decoration: const InputDecoration(labelText: 'Quantita\''),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                controller: draft.unit,
                decoration: const InputDecoration(labelText: 'Unita\''),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SegmentedButton<ExpiryKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in ExpiryKind.values) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {draft.kind},
              onSelectionChanged: (s) {
                draft.kind = s.first;
                onChanged();
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(draft.expiry == null ? 'Data' : df.format(draft.expiry!),
                    overflow: TextOverflow.ellipsis),
                onPressed: onPickExpiry,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: draft.temp,
                keyboardType: decimal,
                inputFormatters: numFmt,
                decoration: const InputDecoration(labelText: 'Temp. rilevata', suffixText: '°C'),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.minC,
                keyboardType: decimal,
                inputFormatters: numFmt,
                decoration: const InputDecoration(labelText: 'Min', suffixText: '°C'),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.maxC,
                keyboardType: decimal,
                inputFormatters: numFmt,
                decoration: const InputDecoration(labelText: 'Max', suffixText: '°C'),
                onChanged: (_) => onChanged(),
              ),
            ),
          ]),
          Wrap(spacing: 16, children: [
            FilterChip(
              label: const Text('Imballo integro'),
              selected: draft.packagingOk,
              onSelected: (v) {
                draft.packagingOk = v;
                onChanged();
              },
            ),
            FilterChip(
              label: const Text('Etichetta conforme'),
              selected: draft.labelOk,
              onSelected: (v) {
                draft.labelOk = v;
                onChanged();
              },
            ),
          ]),
          if (check.hasProblem)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (check.expired) 'Scaduto',
                  if (check.tempOut) 'Temperatura fuori limite',
                ].join(' · '),
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final o in check.allowed)
              ChoiceChip(
                label: Text(o.label),
                selected: outcome == o,
                onSelected: (_) {
                  draft.outcome = o;
                  onChanged();
                },
              ),
          ]),
          if (outcome != ReceiptOutcome.accepted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: draft.notes,
                decoration: const InputDecoration(labelText: 'Motivo (obbligatorio)'),
                onChanged: (_) => onChanged(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: draft.notes,
                decoration: const InputDecoration(labelText: 'Note (facoltative)'),
              ),
            ),
        ]),
      ),
    );
  }
}
