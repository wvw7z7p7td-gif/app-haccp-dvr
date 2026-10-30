import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/data/site_repository.dart';
import '../../../shared/widgets/operator_selector.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'incident_models.dart';
import 'incident_providers.dart';

final _dt = DateFormat('dd/MM/yyyy HH:mm');

class IncidentPage extends ConsumerWidget {
  const IncidentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    final data = ref.watch(incidentDataProvider);
    return PageScaffold(
      title: 'Infortuni e quasi incidenti',
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => const _ReportSheet(),
              ),
              icon: const Icon(Icons.report_gmailerrorred),
              label: const Text('Segnala'),
            )
          : null,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Impossibile caricare gli eventi.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(incidentDataProvider), child: const Text('Riprova')),
          ]),
        ),
        data: (d) => _body(context, ref, d),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, IncidentData d) {
    final cs = Theme.of(context).colorScheme;
    final s = d.stats(DateTime.now());
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(incidentDataProvider);
        await ref.read(incidentDataProvider.future);
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            Chip(label: Text('${s.injuries} infortuni (12 mesi)')),
            Chip(label: Text('${s.nearMisses} quasi incidenti')),
            Chip(label: Text('${s.daysLost} giorni persi')),
            if (s.open > 0)
              Chip(
                  backgroundColor: cs.tertiaryContainer,
                  label: Text('${s.open} da chiudere', style: TextStyle(color: cs.onTertiaryContainer))),
          ]),
        ),
        if (d.inailPending > 0)
          Card(
            color: cs.errorContainer,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              leading: Icon(Icons.gavel, color: cs.onErrorContainer),
              title: Text(
                  '${d.inailPending} denunc${d.inailPending == 1 ? 'a' : 'e'} INAIL da registrare '
                  '(entro 48 ore dal ricevimento del certificato medico).',
                  style: TextStyle(color: cs.onErrorContainer)),
            ),
          ),
        if (d.incidents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nessun evento registrato. Segnala anche i quasi incidenti: servono a prevenire gli infortuni.')),
          ),
        for (final i in d.incidents)
          ListTile(
            leading: Icon(i.kind == IncidentKind.injury ? Icons.healing : Icons.warning_amber_rounded,
                color: i.closed ? null : cs.error),
            title: Text(i.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              i.kind.label,
              _dt.format(i.occurredAt),
              if (i.employeeName != null) i.employeeName!,
              if (i.kind == IncidentKind.injury) i.severity.label,
              if (i.daysLost > 0) '${i.daysLost} gg',
            ].join(' · ')),
            trailing: i.closed
                ? const Icon(Icons.lock_outline, size: 18)
                : Text(i.pendingSteps().isEmpty ? 'Da chiudere' : 'In corso',
                    style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => _DetailSheet(id: i.id),
            ),
          ),
      ]),
    );
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet();
  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _id = const Uuid().v4();
  DateTime _when = DateTime.now();
  final _desc = TextEditingController();
  final _area = TextEditingController();
  final _body = TextEditingController();
  final _days = TextEditingController(text: '0');
  final _op = OperatorSelection();
  IncidentKind _kind = IncidentKind.nearMiss;
  Severity _severity = Severity.firstAid;
  String? _injuredId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_desc, _area, _body, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
        context: context, initialDate: _when, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t == null) return;
    var w = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (w.isAfter(DateTime.now())) w = DateTime.now();
    setState(() => _when = w);
  }

  Future<void> _save() async {
    if (_desc.text.trim().length < 5) return setState(() => _error = 'Descrivi cosa e\' successo.');
    final injury = _kind == IncidentKind.injury;
    if (injury && _injuredId == null) return setState(() => _error = 'Seleziona la persona infortunata.');
    final days = int.tryParse(_days.text.trim()) ?? 0;
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
      final sites = await ref.read(sitesProvider.future);
      await ref.read(incidentRepoProvider)!.report(
            id: _id,
            kind: _kind,
            occurredAt: _when,
            description: _desc.text,
            severity: injury ? _severity : Severity.none,
            daysLost: injury ? days : 0,
            employeeId: injury ? _injuredId : null,
            reportedBy: _op.employee?.id,
            area: _area.text,
            bodyPart: injury ? _body.text : null,
            siteId: sites.length == 1 ? sites.first.id : null,
          );
      ref.invalidate(incidentDataProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Segnalazione NON salvata (connessione assente o errore). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final employees = ref.watch(employeesProvider).valueOrNull ?? const <EmployeeRef>[];
    final injury = _kind == IncidentKind.injury;
    final days = int.tryParse(_days.text.trim()) ?? 0;
    final inail = inailReportRequired(_kind, _severity, days);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Segnala un evento', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<IncidentKind>(
            showSelectedIcon: false,
            segments: [for (final k in IncidentKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('Quando: ${_dt.format(_when)}'),
            onPressed: _pickWhen,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Cosa e\' successo'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _area, decoration: const InputDecoration(labelText: 'Dove (area / reparto)')),
          if (injury) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _injuredId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Persona infortunata'),
              items: [for (final e in employees) DropdownMenuItem(value: e.id, child: Text(e.fullName))],
              onChanged: (v) => setState(() => _injuredId = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: _body, decoration: const InputDecoration(labelText: 'Parte del corpo')),
            const SizedBox(height: 8),
            DropdownButtonFormField<Severity>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Gravita\''),
              items: [
                for (final s in Severity.values.where((s) => s != Severity.none))
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _severity = v ?? _severity),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Giorni di assenza previsti'),
              onChanged: (_) => setState(() {}),
            ),
            if (inail)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Sara\' richiesta la denuncia all\'INAIL.',
                    style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600)),
              ),
          ],
          const SizedBox(height: 12),
          OperatorSelector(selection: _op, label: 'Chi segnala'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Registra')),
        ]),
      ),
    );
  }
}

class _DetailSheet extends ConsumerWidget {
  const _DetailSheet({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    final data = ref.watch(incidentDataProvider).valueOrNull ?? IncidentData.empty;
    final i = data.incidents.where((x) => x.id == id).firstOrNull;
    if (i == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    final t = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(i.kind.label, style: t.textTheme.titleLarge),
        Text('${_dt.format(i.occurredAt)}${i.area == null ? '' : ' · ${i.area}'}'),
        const SizedBox(height: 8),
        Text(i.description),
        if (i.employeeName != null)
          Text('Infortunato: ${i.employeeName}${i.bodyPart == null ? '' : ' (${i.bodyPart})'} · ${i.severity.label}'
              '${i.daysLost > 0 ? ' · ${i.daysLost} giorni' : ''}'),
        if (i.inailRequired)
          Text(i.has(IncidentStep.inailReport) ? 'Denuncia INAIL registrata.' : 'Denuncia INAIL da registrare.',
              style: TextStyle(color: i.has(IncidentStep.inailReport) ? null : t.colorScheme.error)),
        const Divider(height: 24),
        Text('Cronologia', style: t.textTheme.titleMedium),
        if (i.actions.isEmpty) const Text('Nessuna azione registrata.'),
        for (final a in i.actions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${a.step.label}: ${a.description}'),
            subtitle: Text('${_dt.format(a.performedAt)}${a.reference == null ? '' : ' · rif. ${a.reference}'}'),
          ),
        if (canWrite && !i.closed) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in i.availableSteps)
              FilledButton.tonal(
                onPressed: () => _stepSheet(context, i, s),
                child: Text(s == IncidentStep.closure ? 'Chiudi evento' : s.label),
              ),
          ]),
          if (!i.canClose)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Per chiudere serve almeno un\'indagine o un\'azione correttiva'
                  ' (e la denuncia INAIL, se prevista).', style: TextStyle(fontSize: 12)),
            ),
        ],
      ]),
    );
  }
}

Future<void> _stepSheet(BuildContext context, Incident incident, IncidentStep step) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _StepSheet(incident: incident, step: step),
  );
}

class _StepSheet extends ConsumerStatefulWidget {
  const _StepSheet({required this.incident, required this.step});
  final Incident incident;
  final IncidentStep step;
  @override
  ConsumerState<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends ConsumerState<_StepSheet> {
  final _id = const Uuid().v4();
  late final DateTime _at = DateTime.now();
  final _desc = TextEditingController();
  final _ref = TextEditingController();
  final _op = OperatorSelection();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty) return setState(() => _error = 'Compila la descrizione.');
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
      await ref.read(incidentRepoProvider)!.addAction(
            id: _id,
            incidentId: widget.incident.id,
            step: widget.step,
            description: _desc.text,
            performedAt: _at,
            reference: _ref.text,
            employeeId: _op.employee?.id,
          );
      ref.invalidate(incidentDataProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Non registrato (controlla i requisiti per questo passaggio e la connessione).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.step.label, style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: switch (widget.step) {
                IncidentStep.investigation => 'Cause individuate',
                IncidentStep.corrective => 'Cosa e\' stato fatto per evitare che si ripeta',
                IncidentStep.inailReport => 'Note sulla denuncia',
                IncidentStep.closure => 'Motivo della chiusura',
              },
            ),
          ),
          if (widget.step == IncidentStep.inailReport)
            TextField(controller: _ref, decoration: const InputDecoration(labelText: 'Numero di protocollo')),
          const SizedBox(height: 12),
          OperatorSelector(selection: _op),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Registra')),
        ]),
      ),
    );
  }
}
