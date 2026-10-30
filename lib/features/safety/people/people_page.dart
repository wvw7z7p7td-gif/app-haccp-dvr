import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/signature_pad.dart';
import 'people_models.dart';
import 'people_providers.dart';

final _d = DateFormat('dd/MM/yyyy');

(String, Color) _validityLabel(ColorScheme cs, Validity v) => switch (v) {
      Validity.valid => ('In regola', cs.secondary),
      Validity.expiring => ('In scadenza', cs.tertiary),
      Validity.expired => ('Scaduto', cs.error),
      Validity.missing => ('Mancante', cs.error),
    };

class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(peopleDataProvider);
    return DefaultTabController(
      length: 4,
      child: PageScaffold(
        title: 'Persone, formazione e DPI',
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Persone'),
          Tab(text: 'Scadenze'),
          Tab(text: 'Mansioni'),
          Tab(text: 'Catalogo'),
        ]),
        floatingActionButton: isAdmin
            ? Builder(builder: (context) {
                final tab = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tab,
                  builder: (context, _) => switch (tab.index) {
                    0 => FloatingActionButton.extended(
                        onPressed: () => _employeeDialog(context, ref, data.valueOrNull ?? PeopleData.empty),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Nuova persona')),
                    2 => FloatingActionButton.extended(
                        onPressed: () => _roleDialog(context, ref),
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Nuova mansione')),
                    _ => const SizedBox.shrink(),
                  },
                );
              })
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare i dati.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(peopleDataProvider), child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _PeopleTab(data: d),
            _DeadlinesTab(data: d),
            _RolesTab(data: d, isAdmin: isAdmin),
            _CatalogTab(data: d, isAdmin: isAdmin),
          ]),
        ),
      ),
    );
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({required this.data});
  final PeopleData data;

  @override
  Widget build(BuildContext context) {
    if (data.employees.isEmpty) {
      return const Center(child: Text('Nessuna persona registrata. Aggiungi il personale per gestire formazione e DPI.'));
    }
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.employees.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = data.employees[i];
        final iss = data.issuesFor(e, today);
        final bad = iss.training + iss.ppe;
        return ListTile(
          leading: CircleAvatar(child: Text(e.firstName.isEmpty ? '?' : e.firstName[0].toUpperCase())),
          title: Text('${e.fullName}${e.active ? '' : ' (non attivo)'}'),
          subtitle: Text([
            data.roleOf(e)?.name ?? 'Nessuna mansione',
            if (e.isSupervisor) 'responsabile',
          ].join(' · ')),
          trailing: bad > 0
              ? Text('$bad da sistemare', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))
              : (iss.expiring > 0 ? Text('${iss.expiring} in scadenza', style: TextStyle(color: cs.tertiary)) : null),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _EmployeeSheet(id: e.id),
          ),
        );
      },
    );
  }
}

class _EmployeeSheet extends ConsumerWidget {
  const _EmployeeSheet({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(activeMembershipProvider);
    final isAdmin = m?.role.isAdmin ?? false;
    final canWrite = m?.role.canWrite ?? false;
    final data = ref.watch(peopleDataProvider).valueOrNull ?? PeopleData.empty;
    final e = data.employee(id);
    if (e == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    final role = data.roleOf(e);
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context);
    final records = data.trainingRecords.where((r) => r.employeeId == id).toList();
    final ppe = data.ppeAssignments.where((a) => a.employeeId == id).toList();

    Widget statusRow(String title, Validity v, {String? sub}) {
      final (label, color) = _validityLabel(cs, v);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        subtitle: sub == null ? null : Text(sub),
        trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(e.fullName, style: t.textTheme.titleLarge),
        Text(role?.name ?? 'Nessuna mansione assegnata'),
        const Divider(height: 24),
        Text('Formazione richiesta', style: t.textTheme.titleMedium),
        if (role == null || role.trainingIds.isEmpty) const Text('Nessun requisito.'),
        for (final tid in role?.trainingIds ?? const <String>{})
          statusRow(data.trainingType(tid)?.name ?? '—', data.trainingStatus(id, tid, today)),
        const SizedBox(height: 8),
        Text('DPI previsti', style: t.textTheme.titleMedium),
        if (role == null || role.ppeIds.isEmpty) const Text('Nessun requisito.'),
        for (final pid in role?.ppeIds ?? const <String>{})
          statusRow(data.ppeType(pid)?.name ?? '—', data.ppeStatus(id, pid, today)),
        const Divider(height: 24),
        Text('Attestati', style: t.textTheme.titleMedium),
        if (records.isEmpty) const Text('Nessun attestato registrato.'),
        for (final r in records)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(data.trainingType(r.typeId)?.name ?? '—'),
            subtitle: Text([
              'del ${_d.format(r.issuedOn)}',
              if (r.expiresOn != null) 'scade il ${_d.format(r.expiresOn!)}',
              if (r.provider != null) r.provider!,
            ].join(' · ')),
          ),
        const SizedBox(height: 8),
        Text('Consegne DPI', style: t.textTheme.titleMedium),
        if (ppe.isEmpty) const Text('Nessuna consegna registrata.'),
        for (final a in ppe)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(data.ppeType(a.typeId)?.name ?? '—'),
            subtitle: Text([
              'consegnato il ${_d.format(a.deliveredOn)}',
              if (a.size != null) 'tg. ${a.size}',
              if (a.expiresOn != null) 'sostituire entro ${_d.format(a.expiresOn!)}',
              if (a.returnedOn != null) 'restituito il ${_d.format(a.returnedOn!)}',
            ].join(' · ')),
            trailing: isAdmin && a.returnedOn == null
                ? TextButton(
                    onPressed: () async {
                      await ref.read(peopleRepoProvider)!.returnPpe(a.id);
                      ref.invalidate(peopleDataProvider);
                    },
                    child: const Text('Restituito'))
                : null,
          ),
        const SizedBox(height: 12),
        if (canWrite) ...[
          FilledButton.tonalIcon(
            icon: const Icon(Icons.school_outlined),
            label: const Text('Registra formazione'),
            onPressed: data.trainingTypes.isEmpty ? null : () => _trainingDialog(context, ref, data, e),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Consegna DPI'),
            onPressed: data.ppeTypes.isEmpty ? null : () => _deliverSheet(context, data, e),
          ),
        ],
        if (isAdmin) ...[
          TextButton(onPressed: () => _employeeDialog(context, ref, data, existing: e), child: const Text('Modifica')),
          TextButton(onPressed: () => _pinDialog(context, ref, e), child: const Text('Imposta PIN')),
        ],
      ]),
    );
  }
}

Future<void> _employeeDialog(BuildContext context, WidgetRef ref, PeopleData data, {Employee? existing}) async {
  final first = TextEditingController(text: existing?.firstName);
  final last = TextEditingController(text: existing?.lastName);
  String? roleId = existing?.jobRoleId;
  var supervisor = existing?.isSupervisor ?? false;
  var active = existing?.active ?? true;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(existing == null ? 'Nuova persona' : 'Modifica persona'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Cognome')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: roleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mansione'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nessuna')),
                for (final r in data.roles) DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => roleId = v,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Responsabile (puo\' controfirmare)'),
              value: supervisor,
              onChanged: (v) => setS(() => supervisor = v),
            ),
            if (existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In servizio'),
                value: active,
                onChanged: (v) => setS(() => active = v),
              ),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
                return setS(() => error = 'Nome e cognome sono obbligatori.');
              }
              try {
                await ref.read(peopleRepoProvider)!.saveEmployee(
                    id: existing?.id,
                    firstName: first.text,
                    lastName: last.text,
                    jobRoleId: roleId,
                    isSupervisor: supervisor,
                    active: active,
                    hireDate: existing?.hireDate);
                ref.invalidate(peopleDataProvider);
                ref.invalidate(employeesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                setS(() => error = 'Salvataggio non riuscito. Riprova.');
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
  first.dispose();
  last.dispose();
}

Future<void> _pinDialog(BuildContext context, WidgetRef ref, Employee e) async {
  final pin = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('PIN di ${e.fullName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Il PIN serve a firmare le registrazioni sul tablet condiviso.'),
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            decoration: const InputDecoration(labelText: 'PIN (4-8 cifre)'),
          ),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (pin.text.length < 4) return setS(() => error = 'Almeno 4 cifre.');
              try {
                await ref.read(peopleRepoProvider)!.setPin(e.id, pin.text);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                setS(() => error = 'PIN non impostato. Riprova.');
              }
            },
            child: const Text('Imposta'),
          ),
        ],
      ),
    ),
  );
  pin.dispose();
}

Future<void> _trainingDialog(BuildContext context, WidgetRef ref, PeopleData data, Employee e) async {
  final id = const Uuid().v4();
  final required = data.roleOf(e)?.trainingIds ?? const <String>{};
  final types = [...data.trainingTypes]..sort((a, b) {
      final ra = required.contains(a.id) ? 0 : 1;
      final rb = required.contains(b.id) ? 0 : 1;
      return ra != rb ? ra.compareTo(rb) : a.name.compareTo(b.name);
    });
  String typeId = types.first.id;
  DateTime issued = DateTime.now();
  DateTime? expires;
  final provider = TextEditingController();
  final hours = TextEditingController();
  Uint8List? cert;
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final type = data.trainingType(typeId);
        final auto = type?.validityMonths;
        return AlertDialog(
          title: Text('Formazione · ${e.fullName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: typeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Corso'),
                items: [for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setS(() => typeId = v ?? typeId),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Data attestato: ${_d.format(issued)}'),
                onPressed: () async {
                  final p = await showDatePicker(
                      context: ctx, initialDate: issued, firstDate: DateTime(1990), lastDate: DateTime.now());
                  if (p != null) setS(() => issued = p);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_busy),
                label: Text(expires == null
                    ? (auto == null ? 'Nessuna scadenza' : 'Scadenza automatica ($auto mesi)')
                    : 'Scade il ${_d.format(expires!)}'),
                onPressed: () async {
                  final p = await showDatePicker(
                      context: ctx, initialDate: issued.add(const Duration(days: 365)), firstDate: issued, lastDate: DateTime(2100));
                  if (p != null) setS(() => expires = p);
                },
              ),
              TextField(controller: provider, decoration: const InputDecoration(labelText: 'Ente formatore')),
              TextField(
                controller: hours,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Ore'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(cert == null ? 'Foto dell\'attestato' : 'Attestato allegato ✓'),
                onPressed: () async {
                  try {
                    final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 82);
                    if (f != null) {
                      final b = await f.readAsBytes();
                      setS(() => cert = b);
                    }
                  } catch (_) {
                    setS(() => error = 'Fotocamera non disponibile.');
                  }
                },
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref.read(peopleRepoProvider)!.addTraining(
                            id: id,
                            employeeId: e.id,
                            typeId: typeId,
                            issuedOn: issued,
                            expiresOn: expires,
                            provider: provider.text,
                            hours: hours.text.trim().isEmpty ? null : double.tryParse(hours.text.replaceAll(',', '.')),
                            certificate: cert);
                        ref.invalidate(peopleDataProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (_) {
                        setS(() {
                          busy = false;
                          error = 'Non salvato (controlla le date e la connessione).';
                        });
                      }
                    },
              child: const Text('Salva'),
            ),
          ],
        );
      },
    ),
  );
  provider.dispose();
  hours.dispose();
}

Future<void> _deliverSheet(BuildContext context, PeopleData data, Employee e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DeliverSheet(data: data, employee: e),
  );
}

class _DeliverSheet extends ConsumerStatefulWidget {
  const _DeliverSheet({required this.data, required this.employee});
  final PeopleData data;
  final Employee employee;
  @override
  ConsumerState<_DeliverSheet> createState() => _DeliverSheetState();
}

class _DeliverSheetState extends ConsumerState<_DeliverSheet> {
  final _id = const Uuid().v4();
  final _size = TextEditingController();
  final _serial = TextEditingController();
  final _sig = SignatureController();
  late String _typeId = widget.data.roleOf(widget.employee)?.ppeIds.firstOrNull ?? widget.data.ppeTypes.first.id;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _size.dispose();
    _serial.dispose();
    _sig.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final png = await _sig.toPng();
    if (png == null) return setState(() => _error = 'La firma del lavoratore e\' obbligatoria.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(peopleRepoProvider)!.deliverPpe(
            id: _id,
            employeeId: widget.employee.id,
            typeId: _typeId,
            deliveredOn: DateTime.now(),
            signaturePng: png,
            size: _size.text,
            serial: _serial.text,
          );
      ref.invalidate(peopleDataProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Consegna NON registrata (connessione assente o errore). Riprova.');
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
          Text('Consegna DPI', style: t.textTheme.titleLarge),
          Text(widget.employee.fullName),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _typeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'DPI'),
            items: [for (final p in widget.data.ppeTypes) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _typeId = v ?? _typeId),
          ),
          Row(children: [
            Expanded(child: TextField(controller: _size, decoration: const InputDecoration(labelText: 'Taglia'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _serial, decoration: const InputDecoration(labelText: 'Matricola / lotto'))),
          ]),
          const SizedBox(height: 12),
          const Text('Firma del lavoratore per ricevuta:'),
          const SizedBox(height: 4),
          SignaturePad(controller: _sig),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Registra consegna')),
        ]),
      ),
    );
  }
}

class _DeadlinesTab extends StatelessWidget {
  const _DeadlinesTab({required this.data});
  final PeopleData data;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final items = data.deadlinesWithin(today, 90);
    if (items.isEmpty) return const Center(child: Text('Nessuna scadenza nei prossimi 90 giorni.'));
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final x = items[i];
        final left = x.daysLeft(today);
        final emp = x.employeeId == null ? null : data.employee(x.employeeId!);
        return ListTile(
          leading: Icon(left < 0 ? Icons.error_outline : Icons.event, color: left < 0 ? cs.error : null),
          title: Text(x.label),
          subtitle: Text([x.kindLabel, if (emp != null) emp.fullName, _d.format(x.dueOn)].join(' · ')),
          trailing: Text(
            left < 0 ? 'Scaduto da ${-left} gg' : (left == 0 ? 'Oggi' : 'tra $left gg'),
            style: TextStyle(color: left < 0 ? cs.error : (left <= 30 ? cs.tertiary : null), fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

Future<void> _roleDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nuova mansione'),
      content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (es. Cuoco, Cameriere)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) return;
            await ref.read(peopleRepoProvider)!.createRole(name.text);
            ref.invalidate(peopleDataProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Crea'),
        ),
      ],
    ),
  );
  name.dispose();
}

class _RolesTab extends ConsumerWidget {
  const _RolesTab({required this.data, required this.isAdmin});
  final PeopleData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.roles.isEmpty) {
      return const Center(child: Text('Nessuna mansione. Creane una e scegli formazione e DPI richiesti.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.roles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = data.roles[i];
        return ListTile(
          title: Text(r.name),
          subtitle: Text('${r.trainingIds.length} corsi · ${r.ppeIds.length} DPI richiesti'),
          trailing: isAdmin ? const Icon(Icons.edit_outlined) : null,
          onTap: isAdmin ? () => _requirementsDialog(context, ref, data, r) : null,
        );
      },
    );
  }
}

Future<void> _requirementsDialog(BuildContext context, WidgetRef ref, PeopleData data, JobRole role) async {
  final training = {...role.trainingIds};
  final ppe = {...role.ppeIds};
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Requisiti · ${role.name}'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            const Text('Formazione richiesta', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final t in data.trainingTypes)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(t.name),
                value: training.contains(t.id),
                onChanged: (v) => setS(() => v == true ? training.add(t.id) : training.remove(t.id)),
              ),
            const SizedBox(height: 8),
            const Text('DPI richiesti', style: TextStyle(fontWeight: FontWeight.w600)),
            if (data.ppeTypes.isEmpty) const Text('Crea prima i DPI nel Catalogo.'),
            for (final p in data.ppeTypes)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                value: ppe.contains(p.id),
                onChanged: (v) => setS(() => v == true ? ppe.add(p.id) : ppe.remove(p.id)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              await ref.read(peopleRepoProvider)!.saveRoleRequirements(role.id, training, ppe);
              ref.invalidate(peopleDataProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
}

const _ppeTemplates = [
  ('Guanti antitaglio', 2, 'EN 388', 12),
  ('Scarpe antiscivolo', 2, 'EN ISO 20345', 24),
  ('Grembiule e manopole termiche', 1, 'EN 407', 12),
  ('Occhiali di protezione', 2, 'EN 166', 24),
  ('Cuffie / tappi antirumore', 3, 'EN 352', 24),
  ('Guanti per prodotti chimici', 3, 'EN 374', 6),
];

class _CatalogTab extends ConsumerWidget {
  const _CatalogTab({required this.data, required this.isAdmin});
  final PeopleData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('DPI', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      if (data.ppeTypes.isEmpty) const ListTile(title: Text('Nessun DPI in catalogo.')),
      for (final p in data.ppeTypes)
        ListTile(
          title: Text(p.name),
          subtitle: Text([
            if (p.category != null) 'cat. ${'I' * p.category!}'.replaceAll('IIII', 'IV'),
            if (p.standard != null) p.standard!,
            if (p.replaceAfterMonths != null) 'sostituzione ogni ${p.replaceAfterMonths} mesi',
          ].join(' · ')),
        ),
      if (isAdmin)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            for (final t in _ppeTemplates.where((t) => !data.ppeTypes.any((p) => p.name == t.$1)))
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(t.$1),
                onPressed: () async {
                  await ref.read(peopleRepoProvider)!.savePpeType(
                      name: t.$1, category: t.$2, standard: t.$3, replaceAfterMonths: t.$4);
                  ref.invalidate(peopleDataProvider);
                },
              ),
          ]),
        ),
      const Divider(height: 32),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text('Corsi di formazione', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      for (final t in data.trainingTypes)
        ListTile(
          title: Text(t.name),
          subtitle: Text(t.validityMonths == null ? 'Senza scadenza' : 'valido ${t.validityMonths} mesi'),
          trailing: t.custom ? const Text('personalizzato') : null,
        ),
      if (isAdmin)
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Nuovo corso'),
          onPressed: () => _trainingTypeDialog(context, ref),
        ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Le durate di validita\' sono indicative: verifica con il tuo RSPP e con la normativa regionale.',
            style: TextStyle(fontSize: 12)),
      ),
    ]);
  }
}

Future<void> _trainingTypeDialog(BuildContext context, WidgetRef ref) async {
  final code = TextEditingController();
  final name = TextEditingController();
  final months = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nuovo corso'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Codice breve')),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
        TextField(
          controller: months,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Validita\' in mesi (vuoto = nessuna scadenza)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () async {
            if (code.text.trim().isEmpty || name.text.trim().isEmpty) return;
            await ref.read(peopleRepoProvider)!.saveTrainingType(
                code: code.text, name: name.text, validityMonths: int.tryParse(months.text));
            ref.invalidate(peopleDataProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Salva'),
        ),
      ],
    ),
  );
  code.dispose();
  name.dispose();
  months.dispose();
}
