import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/site_repository.dart';
import 'cleaning_models.dart';
import 'cleaning_providers.dart';

Future<void> showCleaningPlanSheet(BuildContext context, {CleaningPlan? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PlanSheet(existing: existing),
  );
}

class _ItemField {
  _ItemField({this.id, String text = ''}) : controller = TextEditingController(text: text);
  final String? id;
  final TextEditingController controller;
}

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({this.existing});
  final CleaningPlan? existing;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  final _name = TextEditingController();
  final _product = TextEditingController();
  final _dilution = TextEditingController();
  final _contact = TextEditingController();
  final _method = TextEditingController();
  final _newSite = TextEditingController();
  final List<_ItemField> _items = [];
  final List<String> _removed = [];
  CleaningFrequency _frequency = CleaningFrequency.daily;
  Set<int> _weekdays = {};
  int? _dayOfMonth;
  String? _shift;
  bool _requiresApproval = false;
  String? _siteId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _product.text = p.productName ?? '';
      _dilution.text = p.dilution ?? '';
      _contact.text = p.contactTimeMin?.toString() ?? '';
      _method.text = p.method ?? '';
      _frequency = p.frequency;
      _weekdays = {...p.weekdays};
      _dayOfMonth = p.dayOfMonth;
      _shift = shiftOptions.contains(p.shift) ? p.shift : null;
      _requiresApproval = p.requiresApproval;
      for (final i in p.items) {
        _items.add(_ItemField(id: i.id, text: i.description));
      }
    }
    if (_items.isEmpty) _items.add(_ItemField());
  }

  @override
  void dispose() {
    for (final c in [_name, _product, _dilution, _contact, _method, _newSite]) {
      c.dispose();
    }
    for (final i in _items) {
      i.controller.dispose();
    }
    super.dispose();
  }

  void _applyTemplate(CleaningTemplate t) {
    setState(() {
      _name.text = t.name;
      _frequency = t.frequency;
      _shift = t.shift;
      _weekdays = {...t.weekdays};
      _dayOfMonth = t.dayOfMonth;
      for (final i in _items) {
        i.controller.dispose();
      }
      _items
        ..clear()
        ..addAll([for (final s in t.items) _ItemField(text: s)]);
    });
  }

  Future<void> _save(List<SiteRef> sites) async {
    final isNew = widget.existing == null;
    final texts = _items.map((i) => i.controller.text.trim()).toList();
    if (_name.text.trim().isEmpty) return _fail('Inserisci un nome.');
    if (_frequency == CleaningFrequency.weekly && _weekdays.isEmpty) {
      return _fail('Seleziona almeno un giorno della settimana.');
    }
    if (_frequency == CleaningFrequency.monthly && _dayOfMonth == null) {
      return _fail('Seleziona il giorno del mese.');
    }
    if (texts.every((t) => t.isEmpty)) return _fail('Aggiungi almeno un\'operazione.');
    final contact = _contact.text.trim().isEmpty ? null : int.tryParse(_contact.text.trim());
    if (_contact.text.trim().isNotEmpty && (contact == null || contact < 0)) {
      return _fail('Tempo di contatto non valido.');
    }
    if (isNew && sites.length > 1 && _siteId == null) return _fail('Seleziona la sede.');
    if (isNew && sites.isEmpty && _newSite.text.trim().isEmpty) {
      return _fail('Inserisci il nome della sede.');
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var siteId = widget.existing?.siteId ?? _siteId ?? (sites.isNotEmpty ? sites.first.id : null);
      siteId ??= await ref.read(siteRepoProvider)!.createSite(_newSite.text);

      // Voci vuote scartate; quelle esistenti svuotate vengono rimosse.
      final drafts = <PlanItemDraft>[];
      final removed = [..._removed];
      for (final i in _items) {
        final text = i.controller.text.trim();
        if (text.isEmpty) {
          if (i.id != null) removed.add(i.id!);
        } else {
          drafts.add(PlanItemDraft(id: i.id, description: text));
        }
      }

      await ref.read(cleaningRepoProvider)!.savePlan(
            id: widget.existing?.id,
            siteId: siteId,
            name: _name.text,
            frequency: _frequency,
            weekdays: _weekdays.toList()..sort(),
            dayOfMonth: _dayOfMonth,
            shift: _shift,
            productName: _product.text,
            method: _method.text,
            dilution: _dilution.text,
            contactTimeMin: contact,
            requiresApproval: _requiresApproval,
            items: drafts,
            removedItemIds: removed,
          );
      ref.invalidate(sitesProvider);
      ref.invalidate(cleaningDataProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _fail('Salvataggio non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String m) => setState(() => _error = m);

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disattivare il piano?'),
        content: const Text('Le registrazioni gia\' fatte restano conservate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disattiva')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(cleaningRepoProvider)!.deactivatePlan(widget.existing!.id);
    ref.invalidate(cleaningDataProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const <SiteRef>[];
    final isNew = widget.existing == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Nuovo piano di pulizia' : 'Modifica piano', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (isNew) ...[
            DropdownButtonFormField<CleaningTemplate>(
              initialValue: null,
              decoration: const InputDecoration(
                labelText: 'Parti da un modello (facoltativo)',
                helperText: 'Modelli indicativi: adattali al tuo piano di autocontrollo.',
                helperMaxLines: 2,
              ),
              items: [
                for (final tpl in cleaningTemplates)
                  DropdownMenuItem(value: tpl, child: Text(tpl.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => v == null ? null : _applyTemplate(v),
            ),
            const SizedBox(height: 12),
          ],
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome *')),
          const SizedBox(height: 12),
          DropdownButtonFormField<CleaningFrequency>(
            key: ValueKey('frequency-$_frequency'),
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Frequenza'),
            items: [
              for (final f in CleaningFrequency.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _frequency = v ?? _frequency),
          ),
          if (_frequency == CleaningFrequency.weekly) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayLabels[d - 1]),
                  selected: _weekdays.contains(d),
                  onSelected: (on) => setState(() => on ? _weekdays.add(d) : _weekdays.remove(d)),
                ),
            ]),
          ],
          if (_frequency == CleaningFrequency.monthly) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('dom-$_dayOfMonth'),
              initialValue: _dayOfMonth,
              decoration: const InputDecoration(
                labelText: 'Giorno del mese',
                helperText: 'Se il mese e\' piu\' corto, cade l\'ultimo giorno.',
              ),
              items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (v) => setState(() => _dayOfMonth = v),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('shift-$_shift'),
            initialValue: _shift,
            decoration: const InputDecoration(labelText: 'Momento della giornata'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Non specificato')),
              for (final s in shiftOptions) DropdownMenuItem<String?>(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _shift = v),
          ),
          const SizedBox(height: 16),
          Text('Operazioni da eseguire', style: t.textTheme.titleMedium),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _items[i].controller,
                    decoration: InputDecoration(labelText: 'Operazione ${i + 1}'),
                  ),
                ),
                IconButton(
                  tooltip: 'Rimuovi',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _items.length == 1
                      ? null
                      : () => setState(() {
                            final removed = _items.removeAt(i);
                            if (removed.id != null) _removed.add(removed.id!);
                            removed.controller.dispose();
                          }),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _items.add(_ItemField())),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi operazione'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Prodotti e metodo (facoltativi)', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _product,
            decoration: const InputDecoration(labelText: 'Prodotto utilizzato'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _dilution,
                decoration: const InputDecoration(labelText: 'Diluizione'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _contact,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Contatto (min)'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _method,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Metodo'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _requiresApproval,
            onChanged: (v) => setState(() => _requiresApproval = v),
            title: const Text('Richiede controfirma del responsabile'),
          ),
          if (isNew && sites.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _siteId,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [for (final s in sites) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) => setState(() => _siteId = v),
            ),
          if (isNew && sites.isEmpty)
            TextField(
              controller: _newSite,
              decoration: const InputDecoration(labelText: 'Nome della sede / locale'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _save(sites),
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salva piano'),
          ),
          if (!isNew)
            TextButton(
              onPressed: _busy ? null : _deactivate,
              child: Text('Disattiva piano', style: TextStyle(color: t.colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}
