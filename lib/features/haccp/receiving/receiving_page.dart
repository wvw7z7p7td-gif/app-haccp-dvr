import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/providers.dart';
import '../../../shared/widgets/page_scaffold.dart';
import 'receipt_sheet.dart';
import 'recall_sheet.dart';
import 'receiving_models.dart';
import 'receiving_providers.dart';

final _dt = DateFormat('dd/MM/yyyy HH:mm');
final _d = DateFormat('dd/MM/yyyy');

class ReceivingPage extends ConsumerWidget {
  const ReceivingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(receivingDataProvider);
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: 'Merci e tracciabilita\'',
        bottom: const TabBar(tabs: [
          Tab(text: 'Ricevimenti'),
          Tab(text: 'Cerca lotto'),
          Tab(text: 'Fornitori'),
        ]),
        floatingActionButton: canWrite
            ? FloatingActionButton.extended(
                onPressed: () => showReceiptSheet(context),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Nuovo ricevimento'),
              )
            : null,
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossibile caricare i ricevimenti.'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => ref.invalidate(receivingDataProvider),
                  child: const Text('Riprova')),
            ]),
          ),
          data: (d) => TabBarView(children: [
            _ReceiptsTab(data: d),
            const _LotSearchTab(),
            _SuppliersTab(data: d),
          ]),
        ),
      ),
    );
  }
}

Widget _outcomeChip(BuildContext context, ReceiptOutcome o) {
  final cs = Theme.of(context).colorScheme;
  final (bg, fg) = switch (o) {
    ReceiptOutcome.accepted => (cs.secondaryContainer, cs.onSecondaryContainer),
    ReceiptOutcome.reservation => (cs.tertiaryContainer, cs.onTertiaryContainer),
    ReceiptOutcome.rejected => (cs.errorContainer, cs.onErrorContainer),
  };
  return Chip(
    visualDensity: VisualDensity.compact,
    backgroundColor: bg,
    side: BorderSide.none,
    label: Text(o.label, style: TextStyle(color: fg)),
  );
}

class _ReceiptsTab extends ConsumerWidget {
  const _ReceiptsTab({required this.data});
  final ReceivingData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.receipts.isEmpty) {
      return const Center(child: Text('Nessun ricevimento negli ultimi 90 giorni.'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(receivingDataProvider);
        await ref.read(receivingDataProvider.future);
      },
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: data.receipts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = data.receipts[i];
          return ListTile(
            leading: Icon(
              r.hasIssues ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: r.hasIssues ? Theme.of(context).colorScheme.error : null,
            ),
            title: Text(r.supplierName),
            subtitle: Text([
              _dt.format(r.receivedAt),
              if (r.docNumber != null) 'DDT ${r.docNumber}',
              '${r.lines.length} prodott${r.lines.length == 1 ? 'o' : 'i'}',
              if (r.rejectedCount > 0) '${r.rejectedCount} respint${r.rejectedCount == 1 ? 'o' : 'i'}',
              if (r.reservationCount > 0) '${r.reservationCount} con riserva',
            ].join(' · ')),
            trailing: r.photoPath != null ? const Icon(Icons.attach_file) : null,
            onTap: () => showReceiptDetail(context, r),
          );
        },
      ),
    );
  }
}

Future<void> showReceiptDetail(BuildContext context, GoodsReceipt r) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReceiptDetail(receipt: r),
  );
}

class _ReceiptDetail extends ConsumerWidget {
  const _ReceiptDetail({required this.receipt});
  final GoodsReceipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final r = receipt;
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    final repo = ref.watch(receivingRepoProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(r.supplierName, style: t.textTheme.titleLarge),
        Text([
          _dt.format(r.receivedAt),
          if (r.docNumber != null) 'DDT ${r.docNumber} del ${_d.format(r.docDate)}',
          if (r.operatorName != null) 'registrato da ${r.operatorName}',
        ].join(' · ')),
        if (!r.vehicleOk)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Mezzo di trasporto NON conforme',
                style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600)),
          ),
        if (r.notes != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.notes!)),
        if (r.photoPath != null && repo != null)
          FutureBuilder<String?>(
            future: repo.photoUrl(r.photoPath!),
            builder: (context, snap) => snap.data == null
                ? const SizedBox(height: 8)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(snap.data!, height: 220, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Text('Foto non disponibile')),
                    ),
                  ),
          ),
        const Divider(height: 24),
        for (final l in r.lines) _LineTile(line: l, canWrite: canWrite),
      ]),
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.line, required this.canWrite});
  final ReceiptLine line;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final repo = ref.watch(receivingRepoProvider);
    final l = line;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.productName, style: t.textTheme.titleMedium)),
          _outcomeChip(context, l.outcome),
        ]),
        Text([
          'Lotto ${l.lotCode ?? '—'}',
          if (l.expiry != null) '${l.expiryKind.label} ${_d.format(l.expiry!)}',
          if (l.quantity != null) '${l.quantity} ${l.unit ?? ''}'.trim(),
          if (l.tempC != null) '${l.tempC} °C',
        ].join(' · ')),
        if (l.tempOut || l.expired || !l.packagingOk || !l.labelOk)
          Text(
            [
              if (l.expired) 'scaduto',
              if (l.tempOut) 'temperatura fuori limite',
              if (!l.packagingOk) 'imballo danneggiato',
              if (!l.labelOk) 'etichetta non conforme',
            ].join(' · '),
            style: TextStyle(color: t.colorScheme.error),
          ),
        if (l.notes != null) Text('Motivo: ${l.notes}'),
        if (repo != null)
          FutureBuilder<List<String>>(
            future: repo.recallsFor(l.id),
            builder: (context, snap) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final s in snap.data ?? const <String>[]) Text('↳ $s')],
            ),
          ),
        if (canWrite && l.outcome != ReceiptOutcome.rejected)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Registra ritiro / smaltimento'),
              onPressed: () async {
                await showRecallSheet(context, l);
              },
            ),
          ),
      ]),
    );
  }
}

class _LotSearchTab extends ConsumerStatefulWidget {
  const _LotSearchTab();
  @override
  ConsumerState<_LotSearchTab> createState() => _LotSearchTabState();
}

class _LotSearchTabState extends ConsumerState<_LotSearchTab> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = ref.watch(activeMembershipProvider)?.role.canWrite ?? false;
    final hits = _query.length < 2 ? null : ref.watch(lotSearchProvider(_query));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Lotto o prodotto',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => setState(() => _query = _ctrl.text.trim()),
            ),
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
      ),
      Expanded(
        child: hits == null
            ? const Center(child: Text('Digita almeno 2 caratteri.'))
            : hits.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Ricerca non riuscita.')),
                data: (list) => list.isEmpty
                    ? const Center(child: Text('Nessun lotto trovato.'))
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final h = list[i];
                          final l = h.line;
                          return ListTile(
                            title: Text('${l.productName} · lotto ${l.lotCode ?? '—'}'),
                            subtitle: Text([
                              h.supplierName,
                              'ricevuto ${_d.format(h.receivedAt)}',
                              if (h.docNumber != null) 'DDT ${h.docNumber}',
                              if (l.expiry != null) '${l.expiryKind.label} ${_d.format(l.expiry!)}',
                            ].join(' · ')),
                            trailing: _outcomeChip(context, l.outcome),
                            onTap: canWrite && l.outcome != ReceiptOutcome.rejected
                                ? () => showRecallSheet(context, l)
                                : null,
                          );
                        },
                      ),
              ),
      ),
    ]);
  }
}

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab({required this.data});
  final ReceivingData data;

  @override
  Widget build(BuildContext context) {
    if (data.suppliers.isEmpty) {
      return const Center(child: Text('Nessun fornitore. Si creano dal primo ricevimento.'));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      itemCount: data.suppliers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = data.suppliers[i];
        final st = data.stats[s.id];
        final rate = st?.nonConformityRate ?? 0;
        return ListTile(
          title: Text(s.name),
          subtitle: Text(st == null || st.receipts == 0
              ? 'Nessuna consegna negli ultimi 12 mesi'
              : '${st.receipts} consegne · ${st.rejected} respinti · ${st.reservations} con riserva (12 mesi)'),
          trailing: st == null || st.lines == 0
              ? null
              : Text('${(rate * 100).round()}% NC',
                  style: TextStyle(
                      color: rate >= 0.1 ? cs.error : null, fontWeight: FontWeight.w600)),
        );
      },
    );
  }
}
