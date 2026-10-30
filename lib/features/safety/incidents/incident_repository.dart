import 'package:supabase_flutter/supabase_flutter.dart';

import 'incident_models.dart';

class IncidentRepository {
  IncidentRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<IncidentData> load() async {
    final since = DateTime.now().subtract(const Duration(days: 730)).toUtc().toIso8601String();
    final rows = await _db
        .from('incidents')
        .select('*, employees!incidents_employee_id_fkey(first_name, last_name), incident_actions(*)')
        .eq('company_id', companyId)
        .gte('occurred_at', since)
        .order('occurred_at', ascending: false)
        .limit(300);
    return IncidentData(incidents: rows.map(Incident.fromMap).toList());
  }

  Future<void> report({
    required String id,
    required IncidentKind kind,
    required DateTime occurredAt,
    required String description,
    required Severity severity,
    int daysLost = 0,
    String? employeeId,
    String? reportedBy,
    String? area,
    String? bodyPart,
    String? siteId,
  }) async {
    try {
      await _db.from('incidents').insert({
        'id': id,
        'company_id': companyId,
        'site_id': siteId,
        'kind': kind.dbValue,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'description': description.trim(),
        'severity': severity.dbValue,
        'days_lost': daysLost,
        'employee_id': employeeId,
        'reported_by': reportedBy,
        'area': _nn(area),
        'body_part': _nn(bodyPart),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> addAction({
    required String id,
    required String incidentId,
    required IncidentStep step,
    required String description,
    required DateTime performedAt,
    String? reference,
    String? employeeId,
  }) async {
    try {
      await _db.from('incident_actions').insert({
        'id': id,
        'company_id': companyId,
        'incident_id': incidentId,
        'step': step.dbValue,
        'description': description.trim(),
        'reference': _nn(reference),
        'performed_at': performedAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }
}
