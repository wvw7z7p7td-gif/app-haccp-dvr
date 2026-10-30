import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cleaning_models.dart';

class CleaningRepository {
  CleaningRepository(this._db, this.companyId);

  final SupabaseClient _db;
  final String companyId;

  static const _bucket = 'signatures';

  Future<CleaningData> load() async {
    final planRows = await _db
        .from('cleaning_plans')
        .select('*, cleaning_products(name), cleaning_plan_items(id, description, sort_order, deleted_at)')
        .eq('company_id', companyId)
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('name');
    final plans = planRows.map(CleaningPlan.fromMap).toList();

    final since = dbDate(DateTime.now().subtract(const Duration(days: 30)));
    final logRows = await _db
        .from('cleaning_logs')
        .select('*, cleaning_plans(name, requires_approval), employees(first_name, last_name), cleaning_log_approvals(id)')
        .eq('company_id', companyId)
        .gte('due_date', since)
        .order('due_date', ascending: false)
        .order('performed_at', ascending: false)
        .limit(500);
    final logs = logRows.map(CleaningLog.fromMap).toList();

    return CleaningData(plans: plans, logs: logs);
  }

  Future<String> _uploadSignature(String path, Uint8List png) async {
    try {
      await _db.storage.from(_bucket).uploadBinary(
            path,
            png,
            fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
          );
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow; // gia' caricata in un tentativo precedente
    }
    return sha256.convert(png).toString();
  }

  /// Registra l'esecuzione. Gli id arrivano dal client: i nuovi tentativi sono idempotenti.
  Future<void> saveLog({
    required String logId,
    required CleaningPlan plan,
    required DateTime dueDate,
    required CleaningStatus status,
    required DateTime performedAt,
    required Map<String, String> itemIds, // id voce piano -> id riga log
    String? employeeId,
    String? notes,
    Uint8List? signaturePng,
  }) async {
    String? sigPath;
    String? sigHash;
    if (signaturePng != null) {
      sigPath = '$companyId/cleaning/$logId.png';
      sigHash = await _uploadSignature(sigPath, signaturePng);
    }

    var logExists = false;
    try {
      await _db.from('cleaning_logs').insert({
        'id': logId,
        'company_id': companyId,
        'site_id': plan.siteId,
        'plan_id': plan.id,
        'due_date': dbDate(dueDate),
        'status': status.dbValue,
        'employee_id': employeeId,
        'performed_at': performedAt.toUtc().toIso8601String(),
        'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        'signature_path': sigPath,
        'signature_hash': sigHash,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      logExists = true;
    }

    if (status == CleaningStatus.done && plan.items.isNotEmpty && !logExists) {
      await _db.from('cleaning_log_items').insert([
        for (final item in plan.items)
          {
            'id': itemIds[item.id],
            'company_id': companyId,
            'log_id': logId,
            'plan_item_id': item.id,
            'done': true,
          }
      ]);
    }
  }

  Future<void> approve({
    required String approvalId,
    required String logId,
    required String employeeId,
    required Uint8List signaturePng,
  }) async {
    final path = '$companyId/cleaning-approvals/$approvalId.png';
    final hash = await _uploadSignature(path, signaturePng);
    try {
      await _db.from('cleaning_log_approvals').insert({
        'id': approvalId,
        'company_id': companyId,
        'log_id': logId,
        'employee_id': employeeId,
        'signature_path': path,
        'signature_hash': hash,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // gia' controfirmata
      rethrow;
    }
  }

  Future<CleaningLogDetail> logDetail(String logId) async {
    final itemRows = await _db
        .from('cleaning_log_items')
        .select('done, cleaning_plan_items(description, sort_order)')
        .eq('log_id', logId);
    final items = itemRows
        .map((r) {
          final pi = r['cleaning_plan_items'];
          return (
            order: pi is Map ? (pi['sort_order'] as num?)?.toInt() ?? 0 : 0,
            item: LogItemDetail(
              text: pi is Map ? (pi['description'] as String? ?? '') : '',
              done: (r['done'] as bool?) ?? true,
            ),
          );
        })
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final logRow =
        await _db.from('cleaning_logs').select('signature_path').eq('id', logId).single();
    final sigPath = logRow['signature_path'] as String?;

    final appr = await _db
        .from('cleaning_log_approvals')
        .select('approved_at, signature_path, employees(first_name, last_name)')
        .eq('log_id', logId)
        .maybeSingle();

    Future<String?> signed(String? path) async =>
        path == null ? null : await _db.storage.from(_bucket).createSignedUrl(path, 300);

    final emp = appr?['employees'];
    return CleaningLogDetail(
      items: items.map((e) => e.item).toList(),
      signatureUrl: await signed(sigPath),
      approverName: emp is Map ? '${emp['first_name']} ${emp['last_name']}' : null,
      approvedAt: appr == null ? null : DateTime.parse(appr['approved_at'] as String).toLocal(),
      approvalSignatureUrl: await signed(appr?['signature_path'] as String?),
    );
  }

  Future<String?> _productId(String? name) async {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return null;
    final existing = await _db
        .from('cleaning_products')
        .select('id')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .ilike('name', n)
        .limit(1)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final created = await _db
        .from('cleaning_products')
        .insert({'company_id': companyId, 'name': n})
        .select('id')
        .single();
    return created['id'] as String;
  }

  Future<void> savePlan({
    String? id,
    required String siteId,
    required String name,
    required CleaningFrequency frequency,
    required List<int> weekdays,
    int? dayOfMonth,
    String? shift,
    String? productName,
    String? method,
    String? dilution,
    int? contactTimeMin,
    required bool requiresApproval,
    required List<PlanItemDraft> items,
    required List<String> removedItemIds,
  }) async {
    String? nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final productId = await _productId(productName);
    final data = {
      'name': name.trim(),
      'frequency': frequency.dbValue,
      'weekdays': frequency == CleaningFrequency.weekly ? weekdays : null,
      'day_of_month': frequency == CleaningFrequency.monthly ? dayOfMonth : null,
      'shift': nn(shift),
      'product_id': productId,
      'method': nn(method),
      'dilution': nn(dilution),
      'contact_time_min': contactTimeMin,
      'requires_approval': requiresApproval,
    };

    String planId;
    if (id == null) {
      final row = await _db
          .from('cleaning_plans')
          .insert({...data, 'company_id': companyId, 'site_id': siteId})
          .select('id')
          .single();
      planId = row['id'] as String;
    } else {
      await _db.from('cleaning_plans').update(data).eq('id', id);
      planId = id;
    }

    if (removedItemIds.isNotEmpty) {
      await _db
          .from('cleaning_plan_items')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .inFilter('id', removedItemIds);
    }
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.id == null) {
        await _db.from('cleaning_plan_items').insert({
          'company_id': companyId,
          'plan_id': planId,
          'description': it.description.trim(),
          'sort_order': i,
        });
      } else {
        await _db
            .from('cleaning_plan_items')
            .update({'description': it.description.trim(), 'sort_order': i}).eq('id', it.id!);
      }
    }
  }

  Future<void> deactivatePlan(String id) =>
      _db.from('cleaning_plans').update({'active': false}).eq('id', id);
}
