import 'package:flutter/material.dart';

String formatTemp(num v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} °C';

/// Accetta virgola o punto decimale. Null se non e' un numero valido.
double? parseTemp(String raw) {
  final s = raw.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

enum ControlPointKind {
  fridge('fridge', 'Frigorifero / cella', Icons.kitchen),
  freezer('freezer', 'Congelatore', Icons.ac_unit),
  display('display', 'Vetrina espositiva', Icons.storefront),
  blastChiller('blast_chiller', 'Abbattitore', Icons.severe_cold),
  hotHolding('hot_holding', 'Mantenimento a caldo', Icons.local_fire_department),
  other('other', 'Altro', Icons.device_thermostat);

  const ControlPointKind(this.dbValue, this.label, this.icon);
  final String dbValue;
  final String label;
  final IconData icon;

  /// Intestazione di sezione nell'elenco.
  String get sectionLabel => switch (this) {
        fridge || freezer || blastChiller => 'Unita\' di raffreddamento',
        display => 'Vetrine espositive',
        hotHolding => 'Mantenimento a caldo',
        other => 'Altri punti di controllo',
      };

  static ControlPointKind fromDb(String v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => other);
}

enum ProductFate {
  notApplicable('not_applicable', 'Nessun prodotto coinvolto'),
  kept('kept', 'Prodotto mantenuto (dopo verifica)'),
  reworked('reworked', 'Prodotto rilavorato'),
  quarantined('quarantined', 'Prodotto in quarantena'),
  discarded('discarded', 'Prodotto eliminato');

  const ProductFate(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

class ControlPoint {
  const ControlPoint({
    required this.id,
    required this.siteId,
    required this.name,
    required this.kind,
    required this.minC,
    required this.maxC,
    required this.readingsPerDay,
  });

  final String id;
  final String siteId;
  final String name;
  final ControlPointKind kind;
  final double? minC;
  final double? maxC;
  final int readingsPerDay;

  factory ControlPoint.fromMap(Map<String, dynamic> m) => ControlPoint(
        id: m['id'] as String,
        siteId: m['site_id'] as String,
        name: m['name'] as String,
        kind: ControlPointKind.fromDb(m['kind'] as String),
        minC: _num(m['min_temp_c']),
        maxC: _num(m['max_temp_c']),
        readingsPerDay: (m['readings_per_day'] as num?)?.toInt() ?? 1,
      );

  bool isOutOfRange(double v) =>
      (minC != null && v < minC!) || (maxC != null && v > maxC!);

  String get rangeLabel {
    if (minC != null && maxC != null) return '${formatTemp(minC!)} … ${formatTemp(maxC!)}';
    if (maxC != null) return '≤ ${formatTemp(maxC!)}';
    if (minC != null) return '≥ ${formatTemp(minC!)}';
    return 'nessun limite';
  }

  @override
  bool operator ==(Object other) => other is ControlPoint && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class TempReading {
  const TempReading({
    required this.id,
    required this.controlPointId,
    required this.valueC,
    required this.measuredAt,
    required this.outOfRange,
    this.employeeId,
    this.notes,
  });

  final String id;
  final String controlPointId;
  final double valueC;
  final DateTime measuredAt;
  final bool outOfRange;
  final String? employeeId;
  final String? notes;

  factory TempReading.fromMap(Map<String, dynamic> m) => TempReading(
        id: m['id'] as String,
        controlPointId: m['control_point_id'] as String,
        valueC: _num(m['value_c'])!,
        measuredAt: DateTime.parse(m['measured_at'] as String).toLocal(),
        outOfRange: (m['out_of_range'] as bool?) ?? false,
        employeeId: m['employee_id'] as String?,
        notes: m['notes'] as String?,
      );
}

/// Dati per l'elenco e per la pagina "Oggi".
class TempOverview {
  const TempOverview({
    required this.points,
    required this.todayCount,
    required this.lastToday,
    required this.openDeviations,
  });

  static const empty = TempOverview(points: [], todayCount: {}, lastToday: {}, openDeviations: {});

  final List<ControlPoint> points;
  final Map<String, int> todayCount;           // id punto -> rilevazioni di oggi
  final Map<String, TempReading> lastToday;    // id punto -> ultima di oggi
  final Map<String, int> openDeviations;       // id punto -> scostamenti senza azione

  int get totalOpenDeviations => openDeviations.values.fold(0, (a, b) => a + b);
  int get expectedToday => points.fold(0, (a, p) => a + p.readingsPerDay);
  int get doneToday => points.fold(
      0, (a, p) => a + (todayCount[p.id] ?? 0).clamp(0, p.readingsPerDay));
}

class TempHistory {
  const TempHistory({required this.readings, required this.withAction});
  final List<TempReading> readings;   // dalla piu' recente
  final Set<String> withAction;       // id rilevazioni con azione correttiva
}
