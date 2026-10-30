import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../haccp/cleaning/cleaning_models.dart' show dbDate;
import 'people_models.dart';

class PeopleRepository {
  PeopleRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<PeopleData> load() async {
    final emp = await _db
        .from('employees')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('last_name');
    final roles = await _db
        .from('job_roles')
        .select('*, job_role_training_requirements(training_type_id), job_role_ppe(ppe_type_id)')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    final tt = await _db
        .from('training_types')
        .select()
        .or('company_id.is.null,company_id.eq.$companyId')
        .isFilter('deleted_at', null)
        .order('name');
    final tr = await _db
        .from('training_records')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('issued_on', ascending: false);
    final pt = await _db
        .from('ppe_types')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    final pa = await _db
        .from('ppe_assignments')
        .select()
        .eq('company_id', companyId)
        .order('delivered_on', ascending: false);
    final dl = await _db.from('v_deadlines').select().eq('company_id', companyId).order('due_on');
    return PeopleData(
      employees: emp.map(Employee.fromMap).toList(),
      roles: roles.map(JobRole.fromMap).toList(),
      trainingTypes: tt.map(TrainingType.fromMap).toList(),
      trainingRecords: tr.map(TrainingRecord.fromMap).toList(),
      ppeTypes: pt.map(PpeType.fromMap).toList(),
      ppeAssignments: pa.map(PpeAssignment.fromMap).toList(),
      deadlines: dl.map(DeadlineItem.fromMap).toList(),
    );
  }

  Future<String> saveEmployee({
    String? id,
    required String firstName,
    required String lastName,
    String? jobRoleId,
    bool isSupervisor = false,
    bool active = true,
    DateTime? hireDate,
  }) async {
    final fields = {
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'job_role_id': jobRoleId,
      'is_supervisor': isSupervisor,
      'active': active,
      'hire_date': hireDate == null ? null : dbDate(hireDate),
    };
    if (id != null) {
      await _db.from('employees').update(fields).eq('id', id);
      return id;
    }
    final row = await _db
        .from('employees')
        .insert({'company_id': companyId, ...fields})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> setPin(String employeeId, String pin) =>
      _db.rpc('set_employee_pin', params: {'p_employee': employeeId, 'p_pin': pin});

  Future<String> createRole(String name) async {
    final row = await _db
        .from('job_roles')
        .insert({'company_id': companyId, 'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Sostituisce i requisiti della mansione (formazione e DPI).
  Future<void> saveRoleRequirements(String roleId, Set<String> trainingIds, Set<String> ppeIds) async {
    await _db.from('job_role_training_requirements').delete().eq('job_role_id', roleId);
    await _db.from('job_role_ppe').delete().eq('job_role_id', roleId);
    if (trainingIds.isNotEmpty) {
      await _db.from('job_role_training_requirements').insert([
        for (final t in trainingIds) {'job_role_id': roleId, 'training_type_id': t, 'company_id': companyId}
      ]);
    }
    if (ppeIds.isNotEmpty) {
      await _db.from('job_role_ppe').insert([
        for (final p in ppeIds) {'job_role_id': roleId, 'ppe_type_id': p, 'company_id': companyId}
      ]);
    }
  }

  Future<void> saveTrainingType({required String code, required String name, int? validityMonths}) =>
      _db.from('training_types').insert({
        'company_id': companyId,
        'code': code.trim().toUpperCase(),
        'name': name.trim(),
        'validity_months': validityMonths,
      });

  Future<void> savePpeType({
    required String name,
    int? category,
    String? standard,
    int? replaceAfterMonths,
  }) =>
      _db.from('ppe_types').insert({
        'company_id': companyId,
        'name': name.trim(),
        'category': category,
        'standard_en': _nn(standard),
        'replace_after_months': replaceAfterMonths,
      });

  Future<void> addTraining({
    required String id,
    required String employeeId,
    required String typeId,
    required DateTime issuedOn,
    DateTime? expiresOn,
    String? provider,
    double? hours,
    Uint8List? certificate,
  }) async {
    String? path;
    if (certificate != null) {
      path = '$companyId/training/$id.jpg';
      try {
        await _db.storage.from('hr-docs').uploadBinary(path, certificate,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      } on StorageException catch (e) {
        if (e.statusCode != '409') rethrow;
      }
    }
    try {
      await _db.from('training_records').insert({
        'id': id,
        'company_id': companyId,
        'employee_id': employeeId,
        'training_type_id': typeId,
        'issued_on': dbDate(issuedOn),
        'expires_on': expiresOn == null ? null : dbDate(expiresOn),
        'provider': _nn(provider),
        'hours': hours,
        'certificate_path': path,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> deliverPpe({
    required String id,
    required String employeeId,
    required String typeId,
    required DateTime deliveredOn,
    required Uint8List signaturePng,
    String? size,
    String? serial,
    String? deliveredBy,
  }) async {
    final path = '$companyId/ppe/$id.png';
    try {
      await _db.storage.from('signatures').uploadBinary(path, signaturePng,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: false));
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow;
    }
    try {
      await _db.from('ppe_assignments').insert({
        'id': id,
        'company_id': companyId,
        'employee_id': employeeId,
        'ppe_type_id': typeId,
        'delivered_on': dbDate(deliveredOn),
        'size': _nn(size),
        'serial_number': _nn(serial),
        'delivered_by': deliveredBy,
        'signature_path': path,
        'signature_hash': sha256.convert(signaturePng).toString(),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> returnPpe(String assignmentId) =>
      _db.from('ppe_assignments').update({'returned_on': dbDate(DateTime.now())}).eq('id', assignmentId);
}
