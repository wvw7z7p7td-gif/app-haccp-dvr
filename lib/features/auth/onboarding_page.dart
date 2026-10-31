import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';

/// Primo accesso: l'utente non appartiene ancora ad alcuna azienda.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _name = TextEditingController();
  final _vat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _vat.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInvites(silent: true));
  }

  /// Se un amministratore ti ha invitato con questa email, entri nella sua azienda.
  Future<void> _checkInvites({bool silent = false}) async {
    setState(() => _busy = true);
    try {
      final n = await ref.read(supabaseProvider).rpc('accept_invites');
      if (n is int && n > 0) {
        ref.invalidate(membershipsProvider);
        return;
      }
      if (!silent && mounted) setState(() => _error = 'Nessun invito trovato per questa email.');
    } catch (_) {
      if (!silent && mounted) setState(() => _error = 'Controllo non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Inserisci il nome dell\'attivita\'.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('create_company', params: {
        'p_name': _name.text.trim(),
        'p_vat': _vat.text.trim().isEmpty ? null : _vat.text.trim(),
      });
      ref.invalidate(membershipsProvider);
    } catch (e) {
      setState(() => _error = e.toString().contains('NOT_ALLOWED')
          ? 'Questo account non puo\' creare una nuova attivita\'. '
              'Se lavori in un\'attivita\' esistente, chiedi all\'amministratore di invitarti con questa email.'
          : 'Non e\' stato possibile creare l\'azienda. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benvenuto'),
        actions: [
          TextButton(
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
            child: const Text('Esci'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Crea la tua attivita\'', style: t.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Sarai l\'amministratore. Potrai aggiungere dipendenti e consulenti dopo.'),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome attivita\' (es. Bar Centrale)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _vat,
                  decoration: const InputDecoration(labelText: 'Partita IVA (facoltativa)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Crea e inizia'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _checkInvites,
                  child: const Text('Sono stato invitato: controlla inviti'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
