import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../haccp/temperatures/temperature_models.dart' show parseTemp;
import 'duvri_models.dart';
import 'duvri_providers.dart';
import 'duvri_sign_sheet.dart';

final _d = DateFormat('dd/MM/yyyy');
final _eur = NumberFormat.currency(locale: 'it_IT', symbol: '€');

class DuvriPage extends ConsumerWidget {
  const DuvriPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(duvriDataProvider);
    final d = data.valueOrNull ?? DuvriData.empty;
    return DefaultTabController(
      length: 2,
      child: PageScaffold(
        title: 'DUVRI e appaltatori',
        bottom: const TabBar(tabs: [Tab(text: 'Appaltatori'), Tab(text: 'DUVRI')]),
        floatingActionButton: isAdmin
            ? Builder(builder: (context) {
                final tab = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tab,
                  builder: (context, _) => tab.index == 0
                      ? FloatingActionButton.extended(
                          onPressed: () => _contractorDialog(context, ref),
                          icon: const Icon(Icons.business),
                          label: const Text('Nuovo appaltatore'))
                      : FloatingActionButton.extended(
                          onPressed: d.contractors.isEmpty ? null : () => _newDuvriDialog(context, ref, d),
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Nuovo DUVRI')),
                );
              })
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare i dati.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(duvriDataProvider), child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _ContractorsTab(data: d),
            _DuvriTab(data: d, isAdmin: isAdmin),
          ]),
        ),
      ),
    );
  }
}

class _ContractorsTab extends ConsumerWidget {
  const _ContractorsTab({required this.data});
  final DuvriData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.contractors.isEmpty) {
      return const Center(child: Text('Nessun appaltatore. Registra le imprese che lavorano nei tuoi locali.'));
    }
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.contractors.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = data.contractors[i];
        final missing = c.missingRequired(today);
        return ListTile(
          leading: Icon(missing.isEmpty ? Icons.verified_outlined : Icons.report_problem_outlined,
              color: missing.isEmpty ? null : cs.error),
          title: Text(c.name),
          subtitle: Text(missing.isEmpty
              ? 'Documenti in regola${c.nextExpiry(today) == null ? '' : ' · prima scadenza ${_d.format(c.nextExpiry(today)!)}'}'
              : 'Mancano: ${missing.map((m) => m.label).join(', ')}'),
          onTap: () => _contractorSheet(context, c.id),
        );
      },
    );
  }
}

Future<void> _contractorSheet(BuildContext context, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ContractorSheet(id: id),
  );
}

class _ContractorSheet extends ConsumerWidget {
  const _ContractorSheet({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(duvriDataProvider).valueOrNull ?? DuvriData.empty;
    final c = data.contractor(id);
    if (c == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(c.name, style: Theme.of(context).textTheme.titleLarge),
        Text([
          if (c.vat != null) 'P.IVA ${c.vat}',
          if (c.activity != null) c.activity!,
          if (c.contact != null) c.contact!,
          if (c.phone != null) c.phone!,
        ].join(' · ')),
        const Divider(height: 24),
        Text('Idoneita\' tecnico-professionale', style: Theme.of(context).textTheme.titleMedium),
        for (final t in ContractorDocType.values.where((t) => t.required))
          Builder(builder: (context) {
            final docs = c.docs.where((d) => d.type == t).toList()
              ..sort((a, b) => (b.expiresOn ?? DateTime(2100)).compareTo(a.expiresOn ?? DateTime(2100)));
            final best = docs.isEmpty ? null : docs.first;
            final v = best?.validity(today) ?? DocValidity.missing;
            final (label, color) = switch (v) {
              DocValidity.valid => ('Valido', cs.secondary),
              DocValidity.expiring => ('In scadenza', cs.tertiary),
              DocValidity.expired => ('Scaduto', cs.error),
              DocValidity.missing => ('Mancante', cs.error),
            };
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.label),
              subtitle: best?.expiresOn == null ? null : Text('scade il ${_d.format(best!.expiresOn!)}'),
              trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            );
          }),
        if (isAdmin) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Aggiungi documento'),
            onPressed: () => _addDocDialog(context, ref, c),
          ),
          TextButton(
            onPressed: () => _contractorDialog(context, ref, existing: c),
            child: const Text('Modifica anagrafica'),
          ),
        ],
      ]),
    );
  }
}

Future<void> _contractorDialog(BuildContext context, WidgetRef ref, {Contractor? existing}) async {
  final name = TextEditingController(text: existing?.name);
  final vat = TextEditingController(text: existing?.vat);
  final activity = TextEditingController(text: existing?.activity);
  final contact = TextEditingController(text: existing?.contact);
  final phone = TextEditingController(text: existing?.phone);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Nuovo appaltatore' : 'Modifica appaltatore'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Ragione sociale')),
          TextField(controller: vat, decoration: const InputDecoration(labelText: 'Partita IVA')),
          TextField(controller: activity, decoration: const InputDecoration(labelText: 'Attivita\' svolta')),
          TextField(controller: contact, decoration: const InputDecoration(labelText: 'Referente')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefono')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) return;
            await ref.read(duvriRepoProvider)!.saveContractor(
                id: existing?.id,
                name: name.text,
                vat: vat.text,
                activity: activity.text,
                contact: contact.text,
                phone: phone.text,
                email: existing?.email);
            ref.invalidate(duvriDataProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Salva'),
        ),
      ],
    ),
  );
  for (final c in [name, vat, activity, contact, phone]) {
    c.dispose();
  }
}

Future<void> _addDocDialog(BuildContext context, WidgetRef ref, Contractor c) async {
  final id = const Uuid().v4();
  var type = ContractorDocType.durc;
  DateTime? expires;
  Uint8List? file;
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nuovo documento'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<ContractorDocType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final t in ContractorDocType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => type = v ?? type,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(expires == null ? 'Data di scadenza (se prevista)' : _d.format(expires!)),
              onPressed: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 120)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime(2100));
                if (p != null) setS(() => expires = p);
              },
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Foto'),
                onPressed: () async => _pick(ImageSource.camera, (b) => setS(() => file = b), (e) => setS(() => error = e)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galleria'),
                onPressed: () async => _pick(ImageSource.gallery, (b) => setS(() => file = b), (e) => setS(() => error = e)),
              ),
            ]),
            if (file != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Documento allegato ✓')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (file == null) return setS(() => error = 'Allega la foto o la scansione del documento.');
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await ref.read(duvriRepoProvider)!.addDocument(
                          id: id, contractorId: c.id, type: type, file: file!, expiresOn: expires);
                      ref.invalidate(duvriDataProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (_) {
                      setS(() {
                        busy = false;
                        error = 'Documento NON salvato. Riprova.';
                      });
                    }
                  },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pick(ImageSource src, void Function(Uint8List) ok, void Function(String) fail) async {
  try {
    final f = await ImagePicker().pickImage(source: src, maxWidth: 2200, imageQuality: 82);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (b.length > 10 * 1024 * 1024) return fail('File troppo grande (max 10 MB).');
    ok(b);
  } catch (_) {
    fail('Fotocamera o galleria non disponibile.');
  }
}

class _DuvriTab extends StatelessWidget {
  const _DuvriTab({required this.data, required this.isAdmin});
  final DuvriData data;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (data.duvris.isEmpty) {
      return const Center(child: Text('Nessun DUVRI. Si crea per ogni appalto con possibili interferenze.'));
    }
    final today = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: data.duvris.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final x = data.duvris[i];
        return ListTile(
          leading: Icon(switch (x.stage) {
            DuvriStage.draft => Icons.edit_note,
            DuvriStage.issued => Icons.draw_outlined,
            DuvriStage.signed => Icons.verified_outlined,
            DuvriStage.closed => Icons.lock_outline,
          }),
          title: Text('${x.contractorName} · ${x.activity}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            x.stageLabel,
            if (x.startsOn != null) 'dal ${_d.format(x.startsOn!)}',
            if (x.endsOn != null) 'al ${_d.format(x.endsOn!)}',
          ].join(' · ')),
          trailing: x.needsClosing(today) ? Text('Da chiudere', style: TextStyle(color: cs.error)) : null,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _DuvriDetail(id: x.id),
          ),
        );
      },
    );
  }
}

Future<void> _newDuvriDialog(BuildContext context, WidgetRef ref, DuvriData data) async {
  var contractorId = data.contractors.first.id;
  final activity = TextEditingController();
  final areas = TextEditingController();
  DateTime? from;
  DateTime? to;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nuovo DUVRI'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: contractorId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Appaltatore'),
              items: [for (final c in data.contractors) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => contractorId = v ?? contractorId,
            ),
            TextField(controller: activity, decoration: const InputDecoration(labelText: 'Attivita\' appaltata')),
            TextField(controller: areas, decoration: const InputDecoration(labelText: 'Aree interessate')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final p = await showDatePicker(
                        context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (p != null) setS(() => from = p);
                  },
                  child: Text(from == null ? 'Inizio' : _d.format(from!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final p = await showDatePicker(
                        context: ctx, initialDate: from ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (p != null) setS(() => to = p);
                  },
                  child: Text(to == null ? 'Fine' : _d.format(to!)),
                ),
              ),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (activity.text.trim().isEmpty) return setS(() => error = 'Descrivi l\'attivita\'.');
              if (from != null && to != null && to!.isBefore(from!)) {
                return setS(() => error = 'La fine precede l\'inizio.');
              }
              try {
                await ref.read(duvriRepoProvider)!.createDuvri(
                    contractorId: contractorId, activity: activity.text, areas: areas.text, startsOn: from, endsOn: to);
                ref.invalidate(duvriDataProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                setS(() => error = 'DUVRI NON creato. Riprova.');
              }
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    ),
  );
  activity.dispose();
  areas.dispose();
}

class _DuvriDetail extends ConsumerWidget {
  const _DuvriDetail({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(activeMembershipProvider)?.role.isAdmin ?? false;
    final data = ref.watch(duvriDataProvider).valueOrNull ?? DuvriData.empty;
    final x = data.duvris.where((d) => d.id == id).firstOrNull;
    if (x == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    final contractor = data.contractor(x.contractorId);
    final today = DateTime.now();
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final repo = ref.read(duvriRepoProvider)!;
    final draft = x.stage == DuvriStage.draft;
    final missing = contractor?.missingRequired(today) ?? const <ContractorDocType>[];

    Future<void> run(Future<void> Function() f, String errorText) async {
      try {
        await f();
        ref.invalidate(duvriDataProvider);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText)));
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${x.contractorName}', style: t.textTheme.titleLarge),
        Text(x.activity),
        Text([
          x.stageLabel,
          if (x.areas != null) x.areas!,
          if (x.startsOn != null) 'dal ${_d.format(x.startsOn!)}',
          if (x.endsOn != null) 'al ${_d.format(x.endsOn!)}',
        ].join(' · ')),
        if (x.snapshotSha != null)
          Text('Impronta ${x.snapshotSha!.substring(0, 16)}…', style: t.textTheme.bodySmall),
        if (x.override != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Emesso con documenti mancanti: ${x.override}', style: TextStyle(color: cs.error)),
          ),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: Text('Interferenze e misure', style: t.textTheme.titleMedium)),
          Text('Costi sicurezza ${_eur.format(x.totalCost)}'),
        ]),
        if (x.interferences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(x.noInterference ? 'Dichiarata assenza di interferenze.' : 'Nessuna interferenza elencata.'),
          ),
        for (final i in x.interferences)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i.description),
            subtitle: Text([
              'Misura: ${i.measures}',
              if (i.area != null) i.area!,
              if (i.responsible != null) i.responsible!,
              if (i.costEur > 0) _eur.format(i.costEur),
            ].join(' · ')),
            trailing: isAdmin && draft
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => run(() => repo.removeInterference(i.id), 'Impossibile rimuovere.'))
                : null,
          ),
        if (isAdmin && draft) ...[
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi interferenza'),
            onPressed: () => _interferenceDialog(context, ref, x.id),
          ),
          if (x.interferences.isEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dichiaro che non ci sono interferenze'),
              value: x.noInterference,
              onChanged: (v) => run(() => repo.setNoInterference(x.id, v), 'Impossibile aggiornare.'),
            ),
        ],
        const Divider(height: 24),
        if (missing.isNotEmpty && draft)
          Card(
            color: cs.errorContainer,
            child: ListTile(
              leading: Icon(Icons.report_problem_outlined, color: cs.onErrorContainer),
              title: Text('Documenti appaltatore mancanti: ${missing.map((m) => m.label).join(', ')}',
                  style: TextStyle(color: cs.onErrorContainer)),
            ),
          ),
        if (isAdmin && draft)
          FilledButton(
            onPressed: x.readyToIssue ? () => _issueDialog(context, ref, x, missing) : null,
            child: const Text('Emetti DUVRI'),
          ),
        if (isAdmin && x.stage == DuvriStage.issued)
          FilledButton.icon(
            icon: const Icon(Icons.draw),
            label: const Text('Firma'),
            onPressed: () => showDuvriSignSheet(context, x),
          ),
        if (isAdmin && (x.stage == DuvriStage.signed))
          OutlinedButton(
            onPressed: () => run(() => repo.close(x.id), 'Impossibile chiudere.'),
            child: const Text('Chiudi (lavori terminati)'),
          ),
      ]),
    );
  }
}

Future<void> _interferenceDialog(BuildContext context, WidgetRef ref, String duvriId) async {
  final desc = TextEditingController();
  final measures = TextEditingController();
  final area = TextEditingController();
  final who = TextEditingController();
  final cost = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nuova interferenza'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Situazione di interferenza')),
            TextField(controller: measures, maxLines: 2, decoration: const InputDecoration(labelText: 'Misura di prevenzione')),
            TextField(controller: area, decoration: const InputDecoration(labelText: 'Area')),
            TextField(controller: who, decoration: const InputDecoration(labelText: 'Responsabile')),
            TextField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
              decoration: const InputDecoration(labelText: 'Costo della sicurezza (€)'),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (desc.text.trim().isEmpty || measures.text.trim().isEmpty) {
                return setS(() => error = 'Descrizione e misura sono obbligatorie.');
              }
              final c = cost.text.trim().isEmpty ? 0.0 : parseTemp(cost.text);
              if (c == null || c < 0) return setS(() => error = 'Importo non valido.');
              try {
                await ref.read(duvriRepoProvider)!.addInterference(
                    duvriId: duvriId, description: desc.text, measures: measures.text,
                    area: area.text, responsible: who.text, costEur: c);
                ref.invalidate(duvriDataProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                setS(() => error = 'Interferenza NON salvata. Riprova.');
              }
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    ),
  );
  for (final c in [desc, measures, area, who, cost]) {
    c.dispose();
  }
}

Future<void> _issueDialog(BuildContext context, WidgetRef ref, Duvri x, List<ContractorDocType> missing) async {
  final reason = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Emetti DUVRI'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Contenuto, interferenze e costi vengono congelati e non saranno piu\' modificabili. '
                'Poi potranno firmare committente e appaltatore.'),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Mancano: ${missing.map((m) => m.label).join(', ')}.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Motivo per procedere comunque', helperText: 'Resta registrato nel documento.'),
              ),
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              if (missing.isNotEmpty && reason.text.trim().isEmpty) {
                return setS(() => error = 'Indica il motivo per procedere con documenti mancanti.');
              }
              try {
                await ref.read(duvriRepoProvider)!.issue(x.id, overrideReason: reason.text);
                ref.invalidate(duvriDataProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                setS(() => error = 'Emissione non riuscita. Riprova.');
              }
            },
            child: const Text('Emetti'),
          ),
        ],
      ),
    ),
  );
  reason.dispose();
}
