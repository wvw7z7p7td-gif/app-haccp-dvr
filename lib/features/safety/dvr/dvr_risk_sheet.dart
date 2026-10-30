import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/site_repository.dart';
import 'dvr_models.dart';
import 'dvr_providers.dart';

Color levelColor(ColorScheme cs, RiskLevel l) => switch (l) {
      RiskLevel.low => cs.secondary,
      RiskLevel.medium => cs.tertiary,
      RiskLevel.high => cs.error,
      RiskLevel.veryHigh => cs.error,
    };

/// Crea o modifica un rischio. true se salvato.
Future<bool?> showRiskSheet(BuildContext context, DvrData data, {DvrRisk? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RiskSheet(data: data, existing: existing),
  );
}

class _RiskSheet extends ConsumerStatefulWidget {
  const _RiskSheet({required this.data, required this.existing});
  final DvrData data;
  final DvrRisk? existing;
  @override
  ConsumerState<_RiskSheet> createState() => _RiskSheetState();
}

class _RiskSheetState extends ConsumerState<_RiskSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _measures = TextEditingController(text: widget.existing?.measures);
  final _newArea = TextEditingController();
  final _newRole = TextEditingController();
  late String? _hazardId = widget.existing?.hazardId;
  late String? _areaId = widget.existing?.areaId;
  late String? _roleId = widget.existing?.jobRoleId;
  late int _p = widget.existing?.probability ?? 2;
  late int _s = widget.existing?.severity ?? 2;
  late int? _rp = widget.existing?.residualProbability;
  late int? _rs = widget.existing?.residualSeverity;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _desc, _measures, _newArea, _newRole]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_hazardId == null) return setState(() => _error = 'Seleziona il tipo di pericolo.');
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Descrivi il rischio in breve.');
    if ((_rp == null) != (_rs == null)) {
      return setState(() => _error = 'Indica probabilita\' e danno residui, oppure nessuno dei due.');
    }
    if (_rp != null && _rp! * _rs! > _p * _s) {
      return setState(() => _error = 'Il rischio residuo non puo\' superare quello iniziale.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(dvrRepoProvider)!;
      final sites = await ref.read(sitesProvider.future);
      final siteId = widget.existing?.siteId ?? (sites.isNotEmpty ? sites.first.id : null);
      var areaId = _areaId;
      if (areaId == '__new__') {
        if (siteId == null || _newArea.text.trim().isEmpty) {
          setState(() => _error = 'Inserisci il nome della nuova area.');
          return;
        }
        areaId = await repo.createArea(siteId, _newArea.text);
        _areaId = areaId;
      }
      var roleId = _roleId;
      if (roleId == '__new__') {
        if (_newRole.text.trim().isEmpty) {
          setState(() => _error = 'Inserisci il nome della nuova mansione.');
          return;
        }
        roleId = await repo.createRole(_newRole.text);
        _roleId = roleId;
      }
      await repo.saveRisk(
        id: widget.existing?.id,
        hazardId: _hazardId!,
        title: _title.text,
        description: _desc.text,
        probability: _p,
        severity: _s,
        siteId: siteId,
        areaId: areaId,
        jobRoleId: roleId,
        measures: _measures.text,
        residualProbability: _rp,
        residualSeverity: _rs,
      );
      ref.invalidate(dvrDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Rischio NON salvato (connessione assente o permessi). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _scale(String label, int value, Map<int, String> labels, ValueChanged<int?> onChanged,
      {bool optional = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      Wrap(spacing: 8, children: [
        for (final e in labels.entries)
          ChoiceChip(
            label: Text('${e.key} · ${e.value}'),
            selected: value == e.key,
            onSelected: (sel) => onChanged(sel ? e.key : (optional ? null : value)),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final score = _p * _s;
    final level = riskLevelFor(score);
    final rScore = (_rp != null && _rs != null) ? _rp! * _rs! : null;
    final d = widget.data;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'Nuovo rischio' : 'Modifica rischio', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _hazardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pericolo'),
            items: [
              for (final h in d.hazards)
                DropdownMenuItem(value: h.id, child: Text('${h.category} · ${h.name}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _hazardId = v),
          ),
          if (_hazardId != null && d.hazards.where((h) => h.id == _hazardId).firstOrNull?.example != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Es.: ${d.hazards.firstWhere((h) => h.id == _hazardId).example}',
                  style: t.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Rischio (es. Tagli con coltelli in cucina)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _areaId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Area'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutta l\'attivita\'')),
                  for (final a in d.areas) DropdownMenuItem(value: a.id, child: Text(a.name)),
                  const DropdownMenuItem(value: '__new__', child: Text('+ Nuova area…')),
                ],
                onChanged: (v) => setState(() => _areaId = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _roleId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mansione'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte')),
                  for (final r in d.roles) DropdownMenuItem(value: r.id, child: Text(r.name)),
                  const DropdownMenuItem(value: '__new__', child: Text('+ Nuova mansione…')),
                ],
                onChanged: (v) => setState(() => _roleId = v),
              ),
            ),
          ]),
          if (_areaId == '__new__')
            TextField(controller: _newArea, decoration: const InputDecoration(labelText: 'Nome della nuova area')),
          if (_roleId == '__new__')
            TextField(controller: _newRole, decoration: const InputDecoration(labelText: 'Nome della nuova mansione')),
          const SizedBox(height: 12),
          _scale('Probabilita\'', _p, probabilityLabels, (v) => setState(() => _p = v ?? _p)),
          const SizedBox(height: 8),
          _scale('Danno (gravita\')', _s, severityLabels, (v) => setState(() => _s = v ?? _s)),
          const SizedBox(height: 8),
          Chip(
            backgroundColor: levelColor(cs, level).withValues(alpha: 0.15),
            side: BorderSide.none,
            label: Text('Rischio $score · ${level.label}',
                style: TextStyle(color: levelColor(cs, level), fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _measures,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Misure di prevenzione e protezione in atto',
              helperText: 'Es. DPI, formazione, procedure, manutenzione.',
            ),
          ),
          const SizedBox(height: 12),
          Text('Rischio residuo (dopo le misure, facoltativo)', style: t.textTheme.titleSmall),
          _scale('Probabilita\' residua', _rp ?? 0, probabilityLabels,
              (v) => setState(() => _rp = v), optional: true),
          const SizedBox(height: 8),
          _scale('Danno residuo', _rs ?? 0, severityLabels, (v) => setState(() => _rs = v), optional: true),
          if (rScore != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Residuo $rScore · ${riskLevelFor(rScore).label}'),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Note (facoltative)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salva'),
          ),
          if (widget.existing != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await ref.read(dvrRepoProvider)!.archiveRisk(widget.existing!.id);
                      ref.invalidate(dvrDataProvider);
                      if (context.mounted) Navigator.of(context).pop(true);
                    },
              child: const Text('Rimuovi dal DVR'),
            ),
        ]),
      ),
    );
  }
}
