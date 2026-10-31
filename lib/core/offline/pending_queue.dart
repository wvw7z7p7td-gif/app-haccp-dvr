import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Operazione di scrittura in attesa di essere inviata (insert idempotente: l'id e' del client).
class PendingOp {
  const PendingOp({required this.table, required this.payload, required this.queuedAt});
  final String table;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() =>
      {'table': table, 'payload': payload, 'queuedAt': queuedAt.toIso8601String()};

  factory PendingOp.fromJson(Map<String, dynamic> m) => PendingOp(
        table: m['table'] as String,
        payload: Map<String, dynamic>.from(m['payload'] as Map),
        queuedAt: DateTime.parse(m['queuedAt'] as String),
      );
}

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// Invia un'operazione. Lancia: errore di rete (ritentabile) o PostgrestException.
typedef OpSender = Future<void> Function(PendingOp op);

/// Un errore e' "rifiutato dal server" (non ritentabile) solo se e' una PostgrestException
/// diversa da duplicato (23505, gia' registrata = successo). Tutto il resto e' rete.
bool isPermanentRejection(Object e) => e is PostgrestException && e.code != '23505';
bool isAlreadyStored(Object e) => e is PostgrestException && e.code == '23505';

class FlushResult {
  const FlushResult({required this.sent, required this.remaining, required this.rejected});
  final int sent;
  final int remaining;
  final int rejected;
}

/// Coda persistente FIFO. Una chiave per azienda, per non mescolare dati fra account.
class PendingQueue {
  PendingQueue(this._store, this.key);
  final KeyValueStore _store;
  final String key;
  bool _flushing = false;

  Future<List<PendingOp>> _load() async {
    final raw = await _store.read(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) PendingOp.fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PendingOp> ops) => _store.write(key, jsonEncode([for (final o in ops) o.toJson()]));

  Future<int> count() async => (await _load()).length;

  Future<void> add(PendingOp op) async => _save([...await _load(), op]);

  /// Invia in ordine. Si ferma al primo errore di rete (preserva l'ordine delle dipendenze,
  /// es. rilevazione prima dell'azione correttiva). Le operazioni rifiutate dal server
  /// vengono scartate e contate, per non bloccare le successive.
  Future<FlushResult> flush(OpSender send) async {
    if (_flushing) return FlushResult(sent: 0, remaining: await count(), rejected: 0);
    _flushing = true;
    try {
      final ops = await _load();
      var sent = 0, rejected = 0;
      final rest = <PendingOp>[];
      var offline = false;
      for (final op in ops) {
        if (offline) {
          rest.add(op);
          continue;
        }
        try {
          await send(op);
          sent++;
        } catch (e) {
          if (isAlreadyStored(e)) {
            sent++;
          } else if (isPermanentRejection(e)) {
            rejected++;
          } else {
            offline = true;
            rest.add(op);
          }
        }
      }
      await _save(rest);
      return FlushResult(sent: sent, remaining: rest.length, rejected: rejected);
    } finally {
      _flushing = false;
    }
  }
}
