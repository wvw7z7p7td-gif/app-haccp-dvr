import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/signature_pad.dart';
import 'duvri_models.dart';
import 'duvri_providers.dart';

/// Firma del DUVRI da parte di una delle due parti. true se registrata.
Future<bool?> showDuvriSignSheet(BuildContext context, Duvri duvri) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SignSheet(duvri: duvri),
  );
}

class _SignSheet extends ConsumerStatefulWidget {
  const _SignSheet({required this.duvri});
  final Duvri duvri;
  @override
  ConsumerState<_SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends ConsumerState<_SignSheet> {
  final _id = const Uuid().v4();
  final _name = TextEditingController();
  final _sig = SignatureController();
  late String _party = widget.duvri.signedParties.contains('employer') ? 'contractor' : 'employer';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _sig.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Inserisci nome e cognome del firmatario.');
    final png = await _sig.toPng();
    if (png == null) return setState(() => _error = 'La firma e\' obbligatoria.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(duvriRepoProvider)!.sign(
            id: _id,
            duvriId: widget.duvri.id,
            party: _party,
            signerName: _name.text,
            png: png,
          );
      ref.invalidate(duvriDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Firma NON registrata (connessione assente o errore). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final signed = widget.duvri.signedParties;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Firma DUVRI', style: t.textTheme.titleLarge),
          Text(widget.duvri.contractorName),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: 'employer', enabled: !signed.contains('employer'), label: const Text('Committente')),
              ButtonSegment(
                  value: 'contractor', enabled: !signed.contains('contractor'), label: const Text('Appaltatore')),
            ],
            selected: {_party},
            onSelectionChanged: (s) => setState(() => _party = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome e cognome del firmatario'),
          ),
          const SizedBox(height: 12),
          SignaturePad(controller: _sig),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Firma e registra'),
          ),
        ]),
      ),
    );
  }
}
