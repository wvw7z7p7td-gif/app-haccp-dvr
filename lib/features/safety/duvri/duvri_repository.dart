import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../haccp/cleaning/cleaning_models.dart' show dbDate;
import 'duvri_models.dart';

class DuvriRepository {
  DuvriRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  static const _docsBucket = 'contractor-docs';
  static const _sigBucket = 'signatures';

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<DuvriData> load() async {
    final c = await _db
        .from('contractors')
        .select('*, contractor_documents(*)')
        .eq('company_id', companyId)
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('name');
    final d = await _db
        .from('duvri_documents')
        .select('*, contractors(name), duvri_interferences(*), duvri_signatures(party)')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return DuvriData(
      contractors: c.map(Contractor.fromMap).toList(),
      duvris: d.map(Duvri.fromMap).toList(),
    );
  }

  Future<String> saveContractor({
    String? id,
    required String name,
    String? vat,
    String? contact,
    String? phone,
    String? email,
    String? activity,
  }) async {
    final fields = {
      'name': name.trim(),
      'vat_number': _nn(vat),
      'contact_name': _nn(contact),
      'phone': _nn(phone),
      'email': _nn(email),
      'activity': _nn(activity),
    };
    if (id != null) {
      await _db.from('contractors').update(fields).eq('id', id);
      return id;
    }
    final row = await _db
        .from('contractors')
        .insert({'company_id': companyId, ...fields})
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Carica il file e registra il documento (id dal client: i tentativi non duplicano).
  Future<void> addDocument({
    required String id,
    required String contractorId,
    required ContractorDocType type,
    required Uint8List file,
    DateTime? issuedOn,
    DateTime? expiresOn,
  }) async {
    final path = '$companyId/contractors/$id.jpg';
    try {
      await _db.storage.from(_docsBucket).uploadBinary(path, file,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow;
    }
    try {
      await _db.from('contractor_documents').insert({
        'id': id,
        'company_id': companyId,
        'contractor_id': contractorId,
        'doc_type': type.dbValue,
        'issued_on': issuedOn == null ? null : dbDate(issuedOn),
        'expires_on': expiresOn == null ? null : dbDate(expiresOn),
        'file_path': path,
        'file_sha256': sha256.convert(file).toString(),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<String> createDuvri({
    required String contractorId,
    required String activity,
    String? areas,
    DateTime? startsOn,
    DateTime? endsOn,
    bool noInterference = false,
  }) async {
    final row = await _db
        .from('duvri_documents')
        .insert({
          'company_id': companyId,
          'contractor_id': contractorId,
          'activity_description': activity.trim(),
          'areas_involved': _nn(areas),
          'starts_on': startsOn == null ? null : dbDate(startsOn),
          'ends_on': endsOn == null ? null : dbDate(endsOn),
          'no_interference': noInterference,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> setNoInterference(String duvriId, bool value) =>
      _db.from('duvri_documents').update({'no_interference': value}).eq('id', duvriId);

  Future<void> addInterference({
    required String duvriId,
    required String description,
    required String measures,
    String? area,
    String? responsible,
    double costEur = 0,
  }) =>
      _db.from('duvri_interferences').insert({
        'company_id': companyId,
        'duvri_id': duvriId,
        'description': description.trim(),
        'measures': measures.trim(),
        'area': _nn(area),
        'responsible': _nn(responsible),
        'cost_eur': costEur,
      });

  Future<void> removeInterference(String id) => _db.from('duvri_interferences').delete().eq('id', id);

  Future<void> issue(String duvriId, {String? overrideReason}) =>
      _db.rpc('issue_duvri', params: {'p_duvri': duvriId, 'p_override_reason': _nn(overrideReason)});

  Future<void> sign({
    required String id,
    required String duvriId,
    required String party, // employer | contractor
    required String signerName,
    required Uint8List png,
  }) async {
    final path = '$companyId/duvri/$id.png';
    try {
      await _db.storage.from(_sigBucket).uploadBinary(path, png,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: false));
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow;
    }
    try {
      await _db.from('duvri_signatures').insert({
        'id': id,
        'company_id': companyId,
        'duvri_id': duvriId,
        'party': party,
        'signer_name': signerName.trim(),
        'signature_path': path,
        'signature_sha256': sha256.convert(png).toString(),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> close(String duvriId) =>
      _db.from('duvri_documents').update({'status': 'closed'}).eq('id', duvriId);
}
