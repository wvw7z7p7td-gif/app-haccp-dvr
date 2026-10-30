import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'menu_models.dart';
import 'menu_providers.dart';

/// Scheda piatto. Se [readOnly] mostra solo i dati. Restituisce true se salvato.
Future<bool?> showMenuItemSheet(
  BuildContext context, {
  required MenuData data,
  MenuItem? existing,
  bool readOnly = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MenuItemSheet(data: data, existing: existing, readOnly: readOnly),
  );
}

class _MenuItemSheet extends ConsumerStatefulWidget {
  const _MenuItemSheet({required this.data, required this.existing, required this.readOnly});
  final MenuData data;
  final MenuItem? existing;
  final bool readOnly;
  @override
  ConsumerState<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends ConsumerState<_MenuItemSheet> {
  late final String _id = widget.existing?.id ?? const Uuid().v4();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _category = TextEditingController(text: widget.existing?.category);
  late final _ingredients = TextEditingController(text: widget.existing?.ingredients);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final Set<String> _contains = {...?widget.existing?.contains};
  late final Set<String> _traces = {...?widget.existing?.traces};
  late bool _active = widget.existing?.active ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _category, _ingredients, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  AllergenState _state(String id) => _contains.contains(id)
      ? AllergenState.contains
      : _traces.contains(id)
          ? AllergenState.traces
          : AllergenState.none;

  void _cycle(String id) {
    if (widget.readOnly) return;
    setState(() {
      switch (_state(id)) {
        case AllergenState.none:
          _contains.add(id);
        case AllergenState.contains:
          _contains.remove(id);
          _traces.add(id);
        case AllergenState.traces:
          _traces.remove(id);
      }
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci il nome del piatto.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(menuRepoProvider)!.save(
            id: _id,
            isNew: widget.existing == null,
            name: _name.text,
            category: _category.text,
            ingredients: _ingredients.text,
            notes: _notes.text,
            active: _active,
            contains: _contains,
            traces: _traces,
          );
      ref.invalidate(menuDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Piatto NON salvato (connessione assente o permessi). Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final ro = widget.readOnly;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'Nuovo piatto' : (ro ? widget.existing!.name : 'Modifica piatto'),
              style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (!ro) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome del piatto'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Categoria (es. Primi, Dolci)'),
            ),
            const SizedBox(height: 8),
          ] else if (widget.existing?.category != null)
            Text(widget.existing!.category!),
          TextField(
            controller: _ingredients,
            readOnly: ro,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Ingredienti',
              helperText: 'Se li modifichi, gli allergeni vanno riconfermati.',
            ),
          ),
          const SizedBox(height: 16),
          Text('Allergeni', style: t.textTheme.titleMedium),
          Text(ro
              ? 'Rosso: contiene · Arancio: possibili tracce'
              : 'Tocca per cambiare: nessuno → contiene → tracce.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final a in widget.data.allergens)
              _AllergenChip(
                label: a.name,
                state: _state(a.id),
                onTap: () => _cycle(a.id),
                scheme: cs,
              ),
          ]),
          if (!ro) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Piatto attualmente in menu'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            TextField(
              controller: _notes,
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
                  : const Text('Salva e conferma allergeni'),
            ),
          ],
        ]),
      ),
    );
  }
}

class _AllergenChip extends StatelessWidget {
  const _AllergenChip({required this.label, required this.state, required this.onTap, required this.scheme});
  final String label;
  final AllergenState state;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (state) {
      AllergenState.none => (null, scheme.onSurfaceVariant, null),
      AllergenState.contains => (scheme.errorContainer, scheme.onErrorContainer, Icons.block),
      AllergenState.traces => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.warning_amber),
    };
    return ActionChip(
      onPressed: onTap,
      backgroundColor: bg,
      avatar: icon == null ? null : Icon(icon, size: 18, color: fg),
      label: Text(label, style: TextStyle(color: fg)),
    );
  }
}
