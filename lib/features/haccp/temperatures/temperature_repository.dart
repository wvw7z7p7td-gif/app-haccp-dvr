import 'package:supabase_flutter/supabase_flutter.dart';

import 'temperature_models.dart';

class TemperatureRepository {
  TemperatureRepository(this._db, this.companyId);

  final SupabaseClient _db;
  final String companyId;

  Future<TempOverview> overview() async {
    final pointRows = await _db
        .from('temp_control_points')
        .select()
        .eq('company_id', companyId)
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('name');
    final points = pointRows.map(ControlPoint.fromMap).toList();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final todayRows = await _db
        .from('temp_readings')
        .select()
        .eq('company_id', companyId)
        .gte('measured_at', startOfDay)
        .order('measured_at', ascending: false);

    final count = <String, int>{};
    final last = <String, TempReading>{};
    for (final row in todayRows) {
      final r = TempReading.fromMap(row);
      count[r.controlPointId] = (count[r.controlPointId] ?? 0) + 1;
      last.putIfAbsent(r.controlPointId, () => r); // le righe sono dalla piu' recente
    }

    final openRows = await _db
        .from('v_open_temp_deviations')
        .select('id, control_point_id')
        .eq('company_id', companyId);
    final open = <String, int>{};
    for (final row in openRows) {
      final id = row['control_point_id'] as String;
      open[id] = (open[id] ?? 0) + 1;
    }

    return TempOverview(points: points, todayCount: count, lastToday: last, openDeviations: open);
  }

  Future<TempHistory> history(String pointId, {int limit = 60}) async {
    final rows = await _db
        .from('temp_readings')
        .select()
        .eq('control_point_id', pointId)
        .order('measured_at', ascending: false)
        .limit(limit);
    final readings = rows.map(TempReading.fromMap).toList();

    final bad = readings.where((r) => r.outOfRange).map((r) => r.id).toList();
    var acted = <String>{};
    if (bad.isNotEmpty) {
      final a = await _db
          .from('temp_corrective_actions')
          .select('reading_id')
          .inFilter('reading_id', bad);
      acted = a.map((e) => e['reading_id'] as String).toSet();
    }
    return TempHistory(readings: readings, withAction: acted);
  }

  /// L'id e' generato dal client: un nuovo tentativo con lo stesso id e' idempotente.
  Future<TempReading> insertReading({
    required String id,
    required ControlPoint point,
    required double value,
    required DateTime measuredAt,
    String? employeeId,
    String? notes,
  }) async {
    try {
      final row = await _db.from('temp_readings').insert({
        'id': id,
        'company_id': companyId,
        'site_id': point.siteId,
        'control_point_id': point.id,
        'value_c': value,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
        'source': 'manual',
        'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      }).select().single();
      return TempReading.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final row = await _db.from('temp_readings').select().eq('id', id).single();
        return TempReading.fromMap(row);
      }
      rethrow;
    }
  }

  Future<void> insertCorrectiveAction({
    required String id,
    required String readingId,
    String? cause,
    required String actionTaken,
    required ProductFate fate,
    String? employeeId,
    String? notes,
  }) async {
    try {
      await _db.from('temp_corrective_actions').insert({
        'id': id,
        'company_id': companyId,
        'reading_id': readingId,
        'cause': cause,
        'action_taken': actionTaken.trim(),
        'product_fate': fate.dbValue,
        'employee_id': employeeId,
        'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // gia' registrata
    }
  }

  /// I limiti modificati valgono per le rilevazioni future: ogni rilevazione
  /// conserva i limiti in vigore al momento della registrazione.
  Future<void> saveControlPoint({
    String? id,
    required String siteId,
    required String name,
    required ControlPointKind kind,
    double? minC,
    double? maxC,
    required int readingsPerDay,
  }) async {
    final data = {
      'name': name.trim(),
      'kind': kind.dbValue,
      'min_temp_c': minC,
      'max_temp_c': maxC,
      'readings_per_day': readingsPerDay,
    };
    if (id == null) {
      await _db.from('temp_control_points').insert({
        ...data,
        'company_id': companyId,
        'site_id': siteId,
      });
    } else {
      await _db.from('temp_control_points').update(data).eq('id', id);
    }
  }

  Future<void> deactivateControlPoint(String id) =>
      _db.from('temp_control_points').update({'active': false}).eq('id', id);
}
