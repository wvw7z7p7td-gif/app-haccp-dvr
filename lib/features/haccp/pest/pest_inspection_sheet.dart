import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/data/site_repository.dart';
import '../../../shared/widgets/operator_selector.dart';
import 'pest_models.dart';
import 'pest_providers.dart';
import 'pest_repository.dart';

/// Giro di controllo sulle postazioni attive. true se salvato.
Future<bool?> showPestInspectionSheet(BuildContext context, PestData data) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _InspectionSheet(data: data),
  );
}

class _Row {
  _Row(this.station) : itemId = const Uuid().v4();
  final PestStation station;
  final String itemId;
  FindingStatus status = FindingStatus.ok;
  int catches = 0;
  final notes = TextEditingController();
}

class _InspectionSheet extends ConsumerStatefulWidget {
  const _InspectionSheet({required this.data});
  final PestData data;
  @override
  ConsumerState<_InspectionSheet> createState() => _InspectionSheetState();
}

class _InspectionSheetState extends ConsumerState<_InspectionSheet> {
  final _id = const Uuid().v4();
  late final DateTime _at = DateTime.now();
  final _provider = TextEditingController();
  final _notes = TextEditingController();
  final _op = OperatorSelection();
  InspectionKind _kind = InspectionKind.internal;
  String? _siteId;
  Uint8List? _photo;
  List<_Row> _rows = [];
  bool _busy = false;
  String? _error;

  late final List<PestStation> _active = widget.data.stations.where((s) => s.active).toList();

  @override
  void initState() {
    super.initState();
    if (_active.isNotEmpty) _selectSite(_active.first.siteId);
  }

  void _selectSite(String siteId) {
    for (final r in _rows) {
      r.notes.dispose();
    }
    _siteId = siteId;
    _rows = [for (final s in _active.where((s) => s.siteId == siteId)) _Row(s)];
  }

  @override
  void dispose() {
    _provider.dispose();
    _notes.dispose();
    for (final r in _rows) {
      r.notes.dispose();
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1800, imageQuality: 80);
      if (f == null) return;
      final b = await f.readAsBytes();
      if (b.length > 5 * 1024 * 1024) {
        setState(() => _error = 'Foto troppo grande (max 5 MB).');
        return;
      }
      setState(() => _photo = b);
    } catch (_) {
      setState(() => _error = 'Fotocamera non disponibile.');
    }
  }

  Future<void> _save() async {
    if (_siteId == null || _rows.isEmpty) {
      setState(() => _error = 'Nessuna postazione attiva da controllare.');
      return;
    }
    if (_kind == InspectionKind.external && _provider.text.trim().isEmpty) {
      setState(() => _error = 'Indica la ditta che ha eseguito il servizio.');
      return;
    }
    for (final r in _rows) {
      if (r.status != FindingStatus.ok && r.notes.text.trim().isEmpty) {
        setState(() => _error = 'Postazione ${r.station.code}: descrivi il rilievo.');
        return;
      }
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
      await ref.read(pestRepoProvider)!.saveInspection(
            id: _id,
            siteId: _siteId!,
            kind: _kind,
            inspectedAt: _at,
            providerName: _provider.text,
            employeeId: _op.employee?.id,
            notes: _notes.text,
            photo: _photo,
            items: [
              for (final r in _rows)
                NewPestItem(
                  id: r.itemId,
                  stationId: r.station.id,
                  status: r.status,
                  catchCount: r.status == FindingStatus.activity ? r.catches : null,
                  notes: r.notes.text,
                )
            ],
          );
      ref.invalidate(pestDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Controllo NON salvato (connessione assente o errore). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const <SiteRef>[];
    final siteIds = _active.map((s) => s.siteId).toSet();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Controllo infestanti', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<InspectionKind>(
            showSelectedIcon: false,
            segments: [for (final k in InspectionKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          if (_kind == InspectionKind.external) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _provider,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ditta di disinfestazione'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_photo == null ? 'Foto del rapporto' : 'Rifai la foto'),
                onPressed: _takePhoto,
              ),
              if (_photo != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_photo!, height: 48, width: 48, fit: BoxFit.cover),
                ),
              ],
            ]),
          ],
          if (siteIds.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _siteId,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [
                for (final id in siteIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text(sites.where((s) => s.id == id).firstOrNull?.name ?? 'Sede'),
                  ),
              ],
              onChanged: (v) => setState(() => _selectSite(v!)),
            ),
          ],
          const Divider(height: 28),
          if (_rows.isEmpty)
            const Text('Nessuna postazione attiva: creane almeno una dalla scheda "Postazioni".'),
          for (final r in _rows) _stationRow(context, r),
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
            onPressed: _busy || _rows.isEmpty ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Registra controllo'),
          ),
        ]),
      ),
    );
  }

  Widget _stationRow(BuildContext context, _Row r) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r.station.code} · ${r.station.kind.label}', style: t.textTheme.titleSmall),
          if (r.station.location != null) Text(r.station.location!),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final s in FindingStatus.values)
              ChoiceChip(
                label: Text(s.label),
                selected: r.status == s,
                onSelected: (_) => setState(() => r.status = s),
              ),
          ]),
          if (r.status == FindingStatus.activity)
            Row(children: [
              const Text('Catture:'),
              IconButton(
                  onPressed: r.catches > 0 ? () => setState(() => r.catches--) : null,
                  icon: const Icon(Icons.remove_circle_outline)),
              Text('${r.catches}', style: t.textTheme.titleMedium),
              IconButton(
                  onPressed: () => setState(() => r.catches++),
                  icon: const Icon(Icons.add_circle_outline)),
            ]),
          if (r.status != FindingStatus.ok)
            TextField(
              controller: r.notes,
              decoration: const InputDecoration(labelText: 'Descrizione del rilievo (obbligatoria)'),
            ),
        ]),
      ),
    );
  }
}
