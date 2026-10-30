// Modelli puri per il controllo infestanti.

enum PestKind {
  rodentBait('rodent_bait', 'Esca rodenticida'),
  rodentTrap('rodent_trap', 'Trappola per roditori'),
  insectLight('insect_light', 'Lampada UV insetti'),
  glueTrap('glue_trap', 'Trappola collante'),
  pheromone('pheromone', 'Feromoni'),
  other('other', 'Altro');

  const PestKind(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static PestKind fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => PestKind.other);
}

enum FindingStatus {
  ok('ok', 'Conforme'),
  activity('activity', 'Attivita\' / catture'),
  damaged('damaged', 'Danneggiata'),
  missing('missing', 'Mancante');

  const FindingStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static FindingStatus fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => FindingStatus.ok);
}

enum InspectionKind {
  internal('internal_check', 'Controllo interno'),
  external('external_service', 'Servizio esterno');

  const InspectionKind(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static InspectionKind fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => InspectionKind.internal);
}

/// Una postazione e' in ritardo se non e' mai stata controllata o se l'ultimo
/// controllo e' piu' vecchio della sua frequenza. Replica `v_pest_station_status`.
bool isStationOverdue({
  required bool active,
  required DateTime? lastInspectedAt,
  required int everyDays,
  required DateTime now,
}) {
  if (!active) return false;
  if (lastInspectedAt == null) return true;
  return lastInspectedAt.isBefore(now.subtract(Duration(days: everyDays)));
}

class PestStation {
  const PestStation({
    required this.id,
    required this.siteId,
    required this.code,
    required this.kind,
    required this.checkEveryDays,
    required this.active,
    required this.overdue,
    this.location,
    this.lastInspectedAt,
    this.lastStatus,
  });

  final String id;
  final String siteId;
  final String code;
  final PestKind kind;
  final String? location;
  final int checkEveryDays;
  final bool active;
  final bool overdue;
  final DateTime? lastInspectedAt;
  final FindingStatus? lastStatus;

  factory PestStation.fromMap(Map<String, dynamic> m) => PestStation(
        id: m['station_id'] as String,
        siteId: m['site_id'] as String,
        code: m['code'] as String,
        kind: PestKind.fromDb(m['kind'] as String?),
        location: m['location'] as String?,
        checkEveryDays: (m['check_every_days'] as num).toInt(),
        active: (m['active'] as bool?) ?? true,
        overdue: (m['overdue'] as bool?) ?? false,
        lastInspectedAt: m['last_inspected_at'] == null
            ? null
            : DateTime.parse(m['last_inspected_at'] as String).toLocal(),
        lastStatus: m['last_status'] == null ? null : FindingStatus.fromDb(m['last_status'] as String),
      );
}

class PestItem {
  const PestItem({
    required this.id,
    required this.stationId,
    required this.status,
    this.catchCount,
    this.notes,
    this.actions = const [],
  });
  final String id;
  final String stationId;
  final FindingStatus status;
  final int? catchCount;
  final String? notes;
  final List<String> actions;

  bool get needsAction => status != FindingStatus.ok && actions.isEmpty;

  factory PestItem.fromMap(Map<String, dynamic> m) => PestItem(
        id: m['id'] as String,
        stationId: m['station_id'] as String,
        status: FindingStatus.fromDb(m['status'] as String?),
        catchCount: (m['catch_count'] as num?)?.toInt(),
        notes: m['notes'] as String?,
        actions: [
          for (final a in (m['pest_corrective_actions'] as List?) ?? const [])
            (a as Map<String, dynamic>)['action'] as String
        ],
      );
}

class PestInspection {
  const PestInspection({
    required this.id,
    required this.kind,
    required this.inspectedAt,
    required this.items,
    this.providerName,
    this.operatorName,
    this.photoPath,
    this.notes,
  });
  final String id;
  final InspectionKind kind;
  final DateTime inspectedAt;
  final String? providerName;
  final String? operatorName;
  final String? photoPath;
  final String? notes;
  final List<PestItem> items;

  int get findings => items.where((i) => i.status != FindingStatus.ok).length;

  factory PestInspection.fromMap(Map<String, dynamic> m) {
    final emp = m['employees'] as Map<String, dynamic>?;
    return PestInspection(
      id: m['id'] as String,
      kind: InspectionKind.fromDb(m['kind'] as String?),
      inspectedAt: DateTime.parse(m['inspected_at'] as String).toLocal(),
      providerName: m['provider_name'] as String?,
      operatorName: emp == null ? null : '${emp['first_name']} ${emp['last_name']}',
      photoPath: m['report_photo_path'] as String?,
      notes: m['notes'] as String?,
      items: [
        for (final i in (m['pest_inspection_items'] as List?) ?? const [])
          PestItem.fromMap(i as Map<String, dynamic>)
      ],
    );
  }
}

class PestData {
  const PestData({required this.stations, required this.inspections});
  final List<PestStation> stations;
  final List<PestInspection> inspections;

  static const empty = PestData(stations: [], inspections: []);

  int get overdueCount => stations.where((s) => s.overdue).length;

  List<({PestInspection inspection, PestItem item, PestStation? station})> get openFindings => [
        for (final n in inspections)
          for (final i in n.items)
            if (i.needsAction)
              (inspection: n, item: i, station: stations.where((s) => s.id == i.stationId).firstOrNull),
      ];
}
