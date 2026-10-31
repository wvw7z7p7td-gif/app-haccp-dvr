import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/providers.dart';
import 'pending_queue.dart';

final pendingQueueProvider = Provider<PendingQueue?>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return null;
  return PendingQueue(PrefsStore(), 'pending_ops_${m.companyId}');
});

/// Numero di registrazioni salvate sul dispositivo e non ancora inviate.
class PendingCountNotifier extends AutoDisposeAsyncNotifier<int> {
  Timer? _timer;

  @override
  Future<int> build() async {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => flush());
    ref.onDispose(() => _timer?.cancel());
    final q = ref.watch(pendingQueueProvider);
    if (q == null) return 0;
    // Prova subito a inviare quanto rimasto da sessioni precedenti.
    final r = await q.flush(_send);
    return r.remaining;
  }

  Future<void> _send(PendingOp op) async {
    final db = ref.read(supabaseProvider);
    if (op.uploadB64 != null && op.uploadBucket != null && op.uploadPath != null) {
      try {
        await db.storage.from(op.uploadBucket!).uploadBinary(
              op.uploadPath!,
              base64Decode(op.uploadB64!),
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
      } on StorageException catch (e) {
        if (e.statusCode != '409') rethrow;
      }
    }
    await db.from(op.table).insert(op.payload);
  }

  Future<void> refreshCount() async {
    final q = ref.read(pendingQueueProvider);
    state = AsyncData(q == null ? 0 : await q.count());
  }

  Future<FlushResult?> flush() async {
    final q = ref.read(pendingQueueProvider);
    if (q == null) return null;
    final r = await q.flush(_send);
    state = AsyncData(r.remaining);
    return r;
  }
}

final pendingCountProvider =
    AsyncNotifierProvider.autoDispose<PendingCountNotifier, int>(PendingCountNotifier.new);
