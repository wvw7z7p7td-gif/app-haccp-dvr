import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pest_models.dart';

class NewPestItem {
  const NewPestItem({
    required this.id,
    required this.stationId,
    required this.status,
    this.catchCount,
    this.notes,
  });
  final String id;
  final String stationId;
  final FindingStatus status;
  final int? catchCount;
  final String? notes;
}

class PestRepository {
  PestRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  static const _bucket = 'pest-reports';

  Future<PestData> load() async {
    final st = await _db
        .from('v_pest_station_status')
        .select()
        .eq('company_id', companyId)
        .order('code');
    final since = DateTime.now().subtract(const Duration(days: 180)).toUtc().toIso8601String();
    final rows = await _db
        .from('pest_inspections')
        .select('*, employees(first_name, last_name), '
            'pest_inspection_items(*, pest_corrective_actions(action))')
        .eq('company_id', companyId)
        .gte('inspected_at', since)
        .order('inspected_at', ascending: false)
        .limit(200);
    return PestData(
      stations: st.map(PestStation.fromMap).toList(),
      inspections: rows.map(PestInspection.fromMap).toList(),
    );
  }

  Future<void> saveStation({
    String? id,
    required String siteId,
    required String code,
    required PestKind kind,
    required int everyDays,
    String? location,
    bool active = true,
  }) async {
    final fields = {
      'code': code.trim(),
      'kind': kind.dbValue,
      'location': (location == null || location.trim().isEmpty) ? null : location.trim(),
      'check_every_days': everyDays,
      'active': active,
    };
    if (id == null) {
      await _db.from('pest_stations').insert({'company_id': companyId, 'site_id': siteId, ...fields});
    } else {
      await _db.from('pest_stations').update(fields).eq('id', id);
    }
  }

  Future<void> saveInspection({
    required String id,
    required String siteId,
    required InspectionKind kind,
    required DateTime inspectedAt,
    required List<NewPestItem> items,
    String? providerName,
    String? employeeId,
    String? notes,
    Uint8List? photo,
  }) async {
    String? path;
    String? hash;
    if (photo != null) {
      path = '$companyId/pest/$id.jpg';
      try {
        await _db.storage.from(_bucket).uploadBinary(path, photo,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      } on StorageException catch (e) {
        if (e.statusCode != '409') rethrow;
      }
      hash = sha256.convert(photo).toString();
    }
    try {
      await _db.from('pest_inspections').insert({
        'id': id,
        'company_id': companyId,
        'site_id': siteId,
        'kind': kind.dbValue,
        'inspected_at': inspectedAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
        'provider_name': (providerName == null || providerName.trim().isEmpty) ? null : providerName.trim(),
        'report_photo_path': path,
        'report_photo_hash': hash,
        'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
    await _db.from('pest_inspection_items').upsert([
      for (final i in items)
        {
          'id': i.id,
          'company_id': companyId,
          'inspection_id': id,
          'station_id': i.stationId,
          'status': i.status.dbValue,
          'catch_count': i.catchCount,
          'notes': (i.notes == null || i.notes!.trim().isEmpty) ? null : i.notes!.trim(),
        }
    ], onConflict: 'id', ignoreDuplicates: true);
  }

  Future<void> saveAction({
    required String id,
    required String itemId,
    required String action,
    required DateTime performedAt,
    String? employeeId,
  }) async {
    try {
      await _db.from('pest_corrective_actions').insert({
        'id': id,
        'company_id': companyId,
        'item_id': itemId,
        'action': action.trim(),
        'performed_at': performedAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<String?> photoUrl(String path) => _db.storage.from(_bucket).createSignedUrl(path, 300);
}
