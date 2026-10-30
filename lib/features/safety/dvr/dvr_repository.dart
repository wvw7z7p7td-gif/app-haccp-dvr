import 'package:supabase_flutter/supabase_flutter.dart';

import '../../haccp/cleaning/cleaning_models.dart' show dbDate;
import 'dvr_models.dart';

class DvrRepository {
  DvrRepository(this._db, this.companyId);
  final SupabaseClient _db;
  final String companyId;

  Future<DvrData> load() async {
    final haz = await _db.from('hazard_catalog').select().order('sort_order');
    final risks = await _db
        .from('dvr_risks')
        .select('*, hazard_catalog(name), areas(name), job_roles(name), dvr_actions(*)')
        .eq('company_id', companyId)
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('risk_score', ascending: false)
        .order('title');
    final officers = await _db
        .from('safety_officers')
        .select('*, employees(first_name, last_name)')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('role');
    final versions = await _db
        .from('dvr_documents')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    final areas = await _db
        .from('areas')
        .select('id, name')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    final roles = await _db
        .from('job_roles')
        .select('id, name')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    NamedRef ref(Map<String, dynamic> r) => NamedRef(r['id'] as String, r['name'] as String);
    return DvrData(
      hazards: haz.map(Hazard.fromMap).toList(),
      risks: risks.map(DvrRisk.fromMap).toList(),
      officers: officers.map(SafetyOfficer.fromMap).toList(),
      versions: versions.map(DvrVersion.fromMap).toList(),
      areas: areas.map(ref).toList(),
      roles: roles.map(ref).toList(),
    );
  }

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<String> createArea(String siteId, String name) async {
    final row = await _db
        .from('areas')
        .insert({'company_id': companyId, 'site_id': siteId, 'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<String> createRole(String name) async {
    final row = await _db
        .from('job_roles')
        .insert({'company_id': companyId, 'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> saveRisk({
    String? id,
    required String hazardId,
    required String title,
    required int probability,
    required int severity,
    String? siteId,
    String? areaId,
    String? jobRoleId,
    String? description,
    String? measures,
    int? residualProbability,
    int? residualSeverity,
  }) async {
    final fields = {
      'hazard_id': hazardId,
      'title': title.trim(),
      'description': _nn(description),
      'probability': probability,
      'severity': severity,
      'site_id': siteId,
      'area_id': areaId,
      'job_role_id': jobRoleId,
      'measures': _nn(measures),
      'residual_probability': residualProbability,
      'residual_severity': residualSeverity,
      'assessed_on': dbDate(DateTime.now()),
    };
    if (id == null) {
      await _db.from('dvr_risks').insert({'company_id': companyId, ...fields});
    } else {
      await _db.from('dvr_risks').update(fields).eq('id', id);
    }
  }

  Future<void> archiveRisk(String id) => _db.from('dvr_risks').update({'active': false}).eq('id', id);

  Future<void> saveAction({
    String? id,
    required String riskId,
    required String description,
    String? responsible,
    DateTime? dueOn,
    ActionStatus status = ActionStatus.open,
  }) async {
    final fields = {
      'risk_id': riskId,
      'description': description.trim(),
      'responsible': _nn(responsible),
      'due_on': dueOn == null ? null : dbDate(dueOn),
      'status': status.dbValue,
      'done_on': status == ActionStatus.done ? dbDate(DateTime.now()) : null,
    };
    if (id == null) {
      await _db.from('dvr_actions').insert({'company_id': companyId, ...fields});
    } else {
      await _db.from('dvr_actions').update(fields).eq('id', id);
    }
  }

  Future<void> saveOfficer({
    required SafetyRole role,
    required String name,
    DateTime? appointedOn,
    DateTime? endsOn,
  }) =>
      _db.from('safety_officers').insert({
        'company_id': companyId,
        'role': role.dbValue,
        'external_name': name.trim(),
        'appointed_on': appointedOn == null ? null : dbDate(appointedOn),
        'ends_on': endsOn == null ? null : dbDate(endsOn),
      });

  Future<void> endOfficer(String id) =>
      _db.from('safety_officers').update({'ends_on': dbDate(DateTime.now())}).eq('id', id);

  Future<void> createDraft(String version, String? siteId) => _db
      .from('dvr_documents')
      .insert({'company_id': companyId, 'site_id': siteId, 'version': version.trim()});

  Future<void> issue(String dvrId, DateTime nextReview, String? reason) =>
      _db.rpc('issue_dvr', params: {
        'p_dvr': dvrId,
        'p_next_review': dbDate(nextReview),
        'p_reason': _nn(reason),
      });
}
