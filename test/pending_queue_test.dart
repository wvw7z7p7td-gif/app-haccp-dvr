import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haccp_safety/core/offline/pending_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PendingOp _op(String id) =>
    PendingOp(table: 't', payload: {'id': id}, queuedAt: DateTime(2026, 10, 31));

void main() {
  photoTests();
  test('persistenza e ordine FIFO', () async {
    final s = MemoryStore();
    final q = PendingQueue(s, 'k');
    await q.add(_op('1'));
    await q.add(_op('2'));
    expect(await PendingQueue(s, 'k').count(), 2);
    final sent = <String>[];
    final r = await q.flush((o) async => sent.add(o.payload['id'] as String));
    expect(sent, ['1', '2']);
    expect(r.sent, 2);
    expect(r.remaining, 0);
  });

  test('errore di rete: si ferma e conserva tutto il resto in ordine', () async {
    final q = PendingQueue(MemoryStore(), 'k');
    for (final i in ['1', '2', '3']) {
      await q.add(_op(i));
    }
    final sent = <String>[];
    final r = await q.flush((o) async {
      if (o.payload['id'] == '2') throw const SocketException('offline');
      sent.add(o.payload['id'] as String);
    });
    expect(sent, ['1']);
    expect(r.remaining, 2);
    final again = <String>[];
    await q.flush((o) async => again.add(o.payload['id'] as String));
    expect(again, ['2', '3']);
  });

  test('duplicato = successo; rifiuto del server = scartato senza bloccare', () async {
    final q = PendingQueue(MemoryStore(), 'k');
    for (final i in ['dup', 'bad', 'ok']) {
      await q.add(_op(i));
    }
    final r = await q.flush((o) async {
      final id = o.payload['id'];
      if (id == 'dup') throw const PostgrestException(message: 'dup', code: '23505');
      if (id == 'bad') throw const PostgrestException(message: 'check', code: '23514');
    });
    expect(r.sent, 2);
    expect(r.rejected, 1);
    expect(r.remaining, 0);
  });

  test('dati corrotti: coda vuota, nessuna eccezione', () async {
    final s = MemoryStore()..data['k'] = '{non json';
    expect(await PendingQueue(s, 'k').count(), 0);
  });
}

void photoTests() {
  test('la foto in coda sopravvive alla serializzazione', () async {
    final s = MemoryStore();
    final q = PendingQueue(s, 'k');
    await q.add(PendingOp(
      table: 't',
      payload: {'id': '1'},
      queuedAt: DateTime(2026, 10, 31),
      uploadBucket: 'temp-photos',
      uploadPath: 'c/temp/1.jpg',
      uploadB64: 'AAEC',
    ));
    late PendingOp got;
    await PendingQueue(s, 'k').flush((o) async => got = o);
    expect(got.uploadB64, 'AAEC');
    expect(got.uploadBucket, 'temp-photos');
    expect(got.uploadPath, 'c/temp/1.jpg');
  });

  test('errore 4xx di storage e\' permanente, 5xx e 429 no', () {
    expect(isPermanentRejection(const StorageException('x', statusCode: '403')), isTrue);
    expect(isPermanentRejection(const StorageException('x', statusCode: '503')), isFalse);
    expect(isPermanentRejection(const StorageException('x', statusCode: '429')), isFalse);
  });
}
