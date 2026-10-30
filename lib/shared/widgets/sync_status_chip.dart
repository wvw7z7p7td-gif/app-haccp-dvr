import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncState { synced, syncing, pending, offline }

class SyncStatus {
  const SyncStatus(this.state, {this.pendingCount = 0});
  final SyncState state;
  final int pendingCount;
}

/// Placeholder: nel passo "offline-first" sara' alimentato dal layer di sync
/// (SQLite locale + PowerSync) con il numero di registrazioni in coda.
final syncStatusProvider =
    StateProvider<SyncStatus>((ref) => const SyncStatus(SyncState.synced));

class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    final (icon, label) = switch (s.state) {
      SyncState.synced => (Icons.cloud_done_outlined, 'Sincronizzato'),
      SyncState.syncing => (Icons.sync, 'Sincronizzo…'),
      SyncState.pending => (Icons.cloud_upload_outlined, '${s.pendingCount} in coda'),
      SyncState.offline => (Icons.cloud_off_outlined, 'Offline'),
    };
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
