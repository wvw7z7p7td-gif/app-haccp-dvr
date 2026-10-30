import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/site_repository.dart';
import 'temperature_models.dart';
import 'temperature_providers.dart';

Future<void> showControlPointSheet(BuildContext context, {ControlPoint? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ControlPointSheet(existing: existing),
  );
}

class _ControlPointSheet extends ConsumerStatefulWidget {
  const _ControlPointSheet({this.existing});
  final ControlPoint? existing;

  @override
  ConsumerState<_ControlPointSheet> createState() => _ControlPointSheetState();
}

class _ControlPointSheetState extends ConsumerState<_ControlPointSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _min = TextEditingController(text: _fmt(widget.existing?.minC));
  late final _max = TextEditingController(text: _fmt(widget.existing?.maxC));
  final _newSite = TextEditingController();
  late ControlPointKind _kind = widget.existing?.kind ?? ControlPointKind.fridge;
  late int _perDay = widget.existing?.readingsPerDay ?? 2;
  String? _siteId;
  bool _busy = false;
  String? _error;

  static String _fmt(double? v) => v == null ? '' : v.toStringAsFixed(1).replaceAll('.', ',');

  // Suggerimenti indicativi: i limiti vanno definiti nel piano di autocontrollo.
  void _applyKind(ControlPointKind k) {
    setState(() {
      _kind = k;
      if (widget.existing != null) return;
      final List<double?> lim = switch (k) {
        ControlPointKind.fridge => [0.0, 4.0],
        ControlPointKind.freezer => [null, -18.0],
        ControlPointKind.display => [0.0, 4.0],
        ControlPointKind.blastChiller => [null, 3.0],
        ControlPointKind.hotHolding => [65.0, null],
        ControlPointKind.other => [null, null],
      };
      final mn = lim[0], mx = lim[1];
      _min.text = _fmt(mn);
      _max.text = _fmt(mx);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    _newSite.dispose();
    super.dispose();
  }

  Future<void> _save(List<SiteRef> sites) async {
    final name = _name.text.trim();
    final mn = parseTemp(_min.text);
    final mx = parseTemp(_max.text);
    if (name.isEmpty) return setState(() => _error = 'Inserisci un nome.');
    if (_min.text.trim().isNotEmpty && mn == null ||
        _max.text.trim().isNotEmpty && mx == null) {
      return setState(() => _error = 'Limiti non validi.');
    }
    if (mn != null && mx != null && mn > mx) {
      return setState(() => _error = 'Il minimo supera il massimo.');
    }
    final isNew = widget.existing == null;
    if (isNew && sites.isNotEmpty && _siteId == null && sites.length > 1) {
      return setState(() => _error = 'Seleziona la sede.');
    }
    if (isNew && sites.isEmpty && _newSite.text.trim().isEmpty) {
      return setState(() => _error = 'Inserisci il nome della sede (es. "Locale principale").');
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(temperatureRepoProvider)!;
      var siteId = widget.existing?.siteId ?? _siteId ?? (sites.isNotEmpty ? sites.first.id : null);
      if (siteId == null) siteId = await ref.read(siteRepoProvider)!.createSite(_newSite.text);
      await repo.saveControlPoint(
        id: widget.existing?.id,
        siteId: siteId,
        name: name,
        kind: _kind,
        minC: mn,
        maxC: mx,
        readingsPerDay: _perDay,
      );
      ref.invalidate(sitesProvider);
      ref.invalidate(tempOverviewProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Salvataggio non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disattivare il punto di controllo?'),
        content: const Text('Lo storico delle rilevazioni resta conservato.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disattiva')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(temperatureRepoProvider)!.deactivateControlPoint(widget.existing!.id);
    ref.invalidate(tempOverviewProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const <SiteRef>[];
    final isNew = widget.existing == null;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9,.]'))];
    const numKb = TextInputType.numberWithOptions(decimal: true, signed: true);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Nuovo punto di controllo' : 'Modifica punto di controllo',
              style: t.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome (es. Cella carni)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ControlPointKind>(
            value: _kind,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              for (final k in ControlPointKind.values)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (k) => k == null ? null : _applyKind(k),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _min,
                keyboardType: numKb,
                inputFormatters: decimal,
                decoration: const InputDecoration(labelText: 'Minimo °C'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _max,
                keyboardType: numKb,
                inputFormatters: decimal,
                decoration: const InputDecoration(labelText: 'Massimo °C'),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Valori suggeriti a titolo indicativo: i limiti vanno stabiliti nel piano '
              'di autocontrollo. Una modifica vale per le rilevazioni future.',
              style: t.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _perDay,
            decoration: const InputDecoration(labelText: 'Rilevazioni al giorno'),
            items: [
              for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text('$i')),
            ],
            onChanged: (v) => setState(() => _perDay = v ?? _perDay),
          ),
          if (isNew && sites.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _siteId,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [for (final s in sites) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) => setState(() => _siteId = v),
            ),
          ],
          if (isNew && sites.isEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _newSite,
              decoration: const InputDecoration(labelText: 'Nome della sede / locale'),
            ),
          ],
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
                : const Text('Salva'),
          ),
          if (!isNew)
            TextButton(
              onPressed: _busy ? null : _deactivate,
              child: Text('Disattiva punto di controllo',
                  style: TextStyle(color: t.colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}
