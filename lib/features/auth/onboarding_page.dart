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
    } catch (_) {
      setState(() => _error = 'Non e\' stato possibile creare l\'azienda. Riprova.');
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
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
