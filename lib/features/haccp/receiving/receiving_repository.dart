import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cleaning/cleaning_models.dart' show dbDate;
import 'receiving_models.dart';

/// Riga da registrare (id stabile generato dal client).
class NewReceiptLine {
  NewReceiptLine({
    required this.id,
    required this.productName,
    required this.outcome,
    required this.expiryKind,
    this.productId,
    this.lotCode,
    this.expiry,
    this.quantity,
    this.unit,
    this.tempC,
    this.minC,
    this.maxC,
    this.packagingOk = true,
    this.labelOk = true,
    this.notes,
  });
  final String id;
  final String? productId;
  final String productName;
  final String? lotCode;
  final DateTime? expiry;
  final ExpiryKind expiryKind;
  final double? quantity;
  final String? unit;
  final double? tempC;
  final double? minC;
  final double? maxC;
  final bool packagingOk;
  final bool labelOk;
  final ReceiptOutcome outcome;
  final String? notes;
}

class ReceivingRepository {
  ReceivingRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  static const _bucket = 'receipts';

  Future<ReceivingData> load() async {
    final since = DateTime.now().subtract(const Duration(days: 90)).toUtc().toIso8601String();
    final rows = await _db
        .from('goods_receipts')
        .select('*, suppliers(name), employees(first_name, last_name), goods_receipt_lines(*)')
        .eq('company_id', companyId)
        .gte('received_at', since)
        .order('received_at', ascending: false)
        .limit(300);
    final sup = await _db
        .from('suppliers')
        .select()
        .eq('company_id', companyId)
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('name');
    final st = await _db.from('v_supplier_stats').select().eq('company_id', companyId);
    return ReceivingData(
      receipts: rows.map(GoodsReceipt.fromMap).toList(),
      suppliers: sup.map(Supplier.fromMap).toList(),
      stats: {for (final r in st) r['supplier_id'] as String: SupplierStats.fromMap(r)},
    );
  }

  Future<List<CatalogProduct>> products() async {
    final rows = await _db
        .from('products')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows.map(CatalogProduct.fromMap).toList();
  }

  Future<Supplier> createSupplier(String name, {String? vat}) async {
    final row = await _db
        .from('suppliers')
        .insert({
          'company_id': companyId,
          'name': name.trim(),
          if (vat != null && vat.trim().isNotEmpty) 'vat_number': vat.trim(),
        })
        .select()
        .single();
    return Supplier.fromMap(row);
  }

  /// Se il prodotto non e' in anagrafica lo crea (con i limiti usati) cosi' la
  /// volta dopo la temperatura limite e' gia' proposta.
  Future<String> createProduct({
    required String name,
    String? supplierId,
    double? minC,
    double? maxC,
  }) async {
    final row = await _db
        .from('products')
        .insert({
          'company_id': companyId,
          'name': name.trim(),
          'supplier_id': supplierId,
          'delivery_min_c': minC,
          'delivery_max_c': maxC,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> saveReceipt({
    required String receiptId,
    required String siteId,
    required String supplierId,
    required DateTime docDate,
    required DateTime receivedAt,
    required List<NewReceiptLine> lines,
    String? docNumber,
    String? employeeId,
    bool vehicleOk = true,
    String? notes,
    Uint8List? photo,
  }) async {
    String? photoPath;
    String? photoHash;
    if (photo != null) {
      photoPath = '$companyId/receipts/$receiptId.jpg';
      try {
        await _db.storage.from(_bucket).uploadBinary(
              photoPath,
              photo,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
      } on StorageException catch (e) {
        if (e.statusCode != '409') rethrow; // gia' caricata da un tentativo precedente
      }
      photoHash = sha256.convert(photo).toString();
    }

    try {
      await _db.from('goods_receipts').insert({
        'id': receiptId,
        'company_id': companyId,
        'site_id': siteId,
        'supplier_id': supplierId,
        'doc_number': _nn(docNumber),
        'doc_date': dbDate(docDate),
        'received_at': receivedAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
        'vehicle_ok': vehicleOk,
        'doc_photo_path': photoPath,
        'doc_photo_hash': photoHash,
        'notes': _nn(notes),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // intestazione gia' registrata
    }

    await _db.from('goods_receipt_lines').upsert([
      for (var i = 0; i < lines.length; i++)
        {
          'id': lines[i].id,
          'company_id': companyId,
          'receipt_id': receiptId,
          'sort_order': i,
          'product_id': lines[i].productId,
          'product_name': lines[i].productName.trim(),
          'lot_code': _nn(lines[i].lotCode),
          'expiry_date': lines[i].expiry == null ? null : dbDate(lines[i].expiry!),
          'expiry_kind': lines[i].expiryKind.dbValue,
          'quantity': lines[i].quantity,
          'unit': _nn(lines[i].unit),
          'temp_c': lines[i].tempC,
          'min_limit_c': lines[i].minC,
          'max_limit_c': lines[i].maxC,
          'packaging_ok': lines[i].packagingOk,
          'label_ok': lines[i].labelOk,
          'outcome': lines[i].outcome.dbValue,
          'notes': _nn(lines[i].notes),
        }
    ], onConflict: 'id', ignoreDuplicates: true);
  }

  Future<List<LotHit>> searchLot(String query) async {
    final q = query.trim().replaceAll('%', '').replaceAll(',', ' ');
    if (q.length < 2) return const [];
    final rows = await _db
        .from('goods_receipt_lines')
        .select('*, goods_receipts!inner(doc_number, received_at, suppliers(name))')
        .eq('company_id', companyId)
        .or('lot_code.ilike.%$q%,product_name.ilike.%$q%')
        .order('expiry_date', ascending: true, nullsFirst: false)
        .limit(100);
    return rows.map(LotHit.fromMap).toList();
  }

  Future<void> saveRecall({
    required String id,
    required ReceiptLine line,
    required RecallAction action,
    required String reason,
    required DateTime performedAt,
    double? quantity,
    String? employeeId,
  }) async {
    try {
      await _db.from('product_recalls').insert({
        'id': id,
        'company_id': companyId,
        'line_id': line.id,
        'lot_code': line.lotCode ?? '—',
        'product_name': line.productName,
        'action': action.dbValue,
        'quantity': quantity,
        'unit': line.unit,
        'reason': reason.trim(),
        'performed_at': performedAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<List<String>> recallsFor(String lineId) async {
    final rows = await _db
        .from('product_recalls')
        .select('action, reason, performed_at')
        .eq('line_id', lineId)
        .order('performed_at', ascending: false);
    return [
      for (final r in rows)
        '${RecallAction.values.firstWhere((a) => a.dbValue == r['action']).label}: ${r['reason']}'
    ];
  }

  Future<String?> photoUrl(String path) async =>
      _db.storage.from(_bucket).createSignedUrl(path, 300);

  static String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
