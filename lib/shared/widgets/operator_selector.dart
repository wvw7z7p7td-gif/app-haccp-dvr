import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/auth/providers.dart';

class EmployeeRef {
  const EmployeeRef({
    required this.id,
    required this.fullName,
    this.userId,
    this.isSupervisor = false,
  });
  final String id;
  final String fullName;
  final String? userId;
  final bool isSupervisor;

  @override
  bool operator ==(Object other) => other is EmployeeRef && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

final employeesProvider = FutureProvider.autoDispose<List<EmployeeRef>>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return const [];
  final rows = await ref
      .read(supabaseProvider)
      .from('employees')
      .select('id, first_name, last_name, user_id, is_supervisor')
      .eq('company_id', m.companyId)
      .eq('active', true)
      .isFilter('deleted_at', null)
      .order('last_name');
  return rows
      .map((r) => EmployeeRef(
            id: r['id'] as String,
            fullName: '${r['first_name']} ${r['last_name']}',
            userId: r['user_id'] as String?,
            isSupervisor: (r['is_supervisor'] as bool?) ?? false,
          ))
      .toList();
});

/// Stato mutabile condiviso tra il selettore e la sheet che lo ospita.
class OperatorSelection {
  EmployeeRef? employee;
  String pin = '';
}

/// Attribuisce una registrazione a una persona (tablet condiviso).
/// Chi e' autenticato con il proprio account non deve digitare il PIN.
class OperatorSelector extends ConsumerStatefulWidget {
  const OperatorSelector({
    super.key,
    required this.selection,
    this.label = 'Operatore',
    this.supervisorsOnly = false,
    this.excludeEmployeeId,
  });
  final OperatorSelection selection;
  final String label;

  /// Mostra solo i responsabili (es. per la controfirma).
  final bool supervisorsOnly;

  /// Esclude una persona (es. chi ha eseguito l'attivita' da controfirmare).
  final String? excludeEmployeeId;

  @override
  ConsumerState<OperatorSelector> createState() => _OperatorSelectorState();
}

class _OperatorSelectorState extends ConsumerState<OperatorSelector> {
  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final uid = ref.watch(sessionProvider)?.user.id;

    return employees.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const Text('Impossibile caricare l\'elenco dei dipendenti.'),
      data: (all) {
        final list = all
            .where((e) =>
                (!widget.supervisorsOnly || e.isSupervisor) && e.id != widget.excludeEmployeeId)
            .toList();
        if (widget.supervisorsOnly && list.isEmpty) {
          return const Text(
            'Nessun responsabile disponibile: in anagrafica serve almeno un '
            'dipendente contrassegnato come responsabile, diverso da chi ha eseguito.',
          );
        }
        if (list.isEmpty) {
          return const Text(
            'Nessun dipendente in anagrafica: la registrazione non sara\' '
            'attribuita a una persona.',
          );
        }
        final sel = widget.selection;
        sel.employee ??= list.where((e) => e.userId != null && e.userId == uid).firstOrNull;
        final self = sel.employee != null && sel.employee!.userId == uid;

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<EmployeeRef>(
            initialValue: sel.employee,
            decoration: InputDecoration(labelText: widget.label),
            items: [
              for (final e in list) DropdownMenuItem(value: e, child: Text(e.fullName)),
            ],
            onChanged: (v) => setState(() {
              sel.employee = v;
              sel.pin = '';
            }),
          ),
          if (sel.employee != null && !self) ...[
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(sel.employee!.id),
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'PIN operatore', counterText: ''),
              onChanged: (v) => sel.pin = v,
            ),
          ],
        ]);
      },
    );
  }
}

/// Restituisce un messaggio d'errore, oppure null se l'operatore e' valido.
Future<String?> verifyOperator(
  WidgetRef ref,
  OperatorSelection s, {
  bool supervisorsOnly = false,
}) async {
  final list = ref.read(employeesProvider).valueOrNull ?? const <EmployeeRef>[];
  final e = s.employee;
  if (supervisorsOnly) {
    if (e == null) return 'Seleziona il responsabile che controfirma.';
    if (!e.isSupervisor) return 'Solo un responsabile puo\' controfirmare.';
  } else if (list.isEmpty) {
    return null;
  }
  if (e == null) return 'Seleziona chi sta registrando.';
  final uid = ref.read(sessionProvider)?.user.id;
  if (e.userId != null && e.userId == uid) return null;
  if (s.pin.isEmpty) return 'Inserisci il PIN dell\'operatore.';
  try {
    final ok = await ref
        .read(supabaseProvider)
        .rpc('verify_employee_pin', params: {'p_employee': e.id, 'p_pin': s.pin});
    return ok == true ? null : 'PIN non corretto (o non ancora impostato).';
  } on PostgrestException catch (ex) {
    final m = RegExp(r'PIN_LOCKED:(\d+)').firstMatch(ex.message);
    if (m != null) {
      return 'Troppi tentativi errati: riprova tra ${m.group(1)} minuti '
          '(oppure l\'amministratore reimposta il PIN).';
    }
    return 'Impossibile verificare il PIN.';
  } catch (_) {
    return 'Impossibile verificare il PIN: controlla la connessione.';
  }
}
