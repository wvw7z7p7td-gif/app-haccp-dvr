import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/site_repository.dart';
import 'pest_models.dart';
import 'pest_providers.dart';

Future<bool?> showPestStationSheet(BuildContext context, {PestStation? existing, required bool isAdmin}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _StationSheet(existing: existing, isAdmin: isAdmin),
  );
}

class _StationSheet extends ConsumerStatefulWidget {
  const _StationSheet({required this.existing, required this.isAdmin});
  final PestStation? existing;
  final bool isAdmin;
  @override
  ConsumerState<_StationSheet> createState() => _StationSheetState();
}

class _StationSheetState extends ConsumerState<_StationSheet> {
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _days = TextEditingController(text: '${widget.existing?.checkEveryDays ?? 7}');
  late PestKind _kind = widget.existing?.kind ?? PestKind.rodentBait;
  late bool _active = widget.existing?.active ?? true;
  String? _siteId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _location.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final days = int.tryParse(_days.text.trim());
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci il codice della postazione (es. E1).');
      return;
    }
    if (days == null || days < 1 || days > 365) {
      setState(() => _error = 'Frequenza non valida (1-365 giorni).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var siteId = widget.existing?.siteId ?? _siteId;
      if (siteId == null) {
        final sites = await ref.read(sitesProvider.future);
        siteId = sites.isNotEmpty
            ? sites.first.id
            : await ref.read(siteRepoProvider)!.createSite('Sede principale');
      }
      await ref.read(pestRepoProvider)!.saveStation(
            id: widget.existing?.id,
            siteId: siteId,
            code: _code.text,
            kind: _kind,
            everyDays: days,
            location: _location.text,
            active: _active,
          );
      ref.invalidate(pestDataProvider);
      ref.invalidate(sitesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      final dup = e.toString().contains('23505');
      setState(() => _error = dup
          ? 'Esiste gia\' una postazione con questo codice nella sede.'
          : 'Postazione NON salvata (connessione assente o permessi). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const <SiteRef>[];
    final isNew = widget.existing == null;
    // L'operatore puo' creare postazioni; solo il titolare modifica quelle esistenti.
    final canEdit = isNew || widget.isAdmin;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Nuova postazione' : 'Postazione ${widget.existing!.code}',
              style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: canEdit,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Codice (es. E1, L2)'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<PestKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [for (final k in PestKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: canEdit ? (v) => setState(() => _kind = v ?? _kind) : null,
          ),
          const SizedBox(height: 8),
          if (isNew && sites.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _siteId ?? sites.first.id,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [for (final s in sites) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) => _siteId = v,
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _location,
            enabled: canEdit,
            decoration: const InputDecoration(labelText: 'Posizione (es. retro cucina, vicino al lavello)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _days,
            enabled: canEdit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Controllo ogni (giorni)'),
          ),
          if (!isNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Postazione attiva'),
              value: _active,
              onChanged: canEdit ? (v) => setState(() => _active = v) : null,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          if (canEdit) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Salva')),
          ],
        ]),
      ),
    );
  }
}
