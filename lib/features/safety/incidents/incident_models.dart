// Modelli puri per infortuni e near-miss.

enum IncidentKind {
  injury('injury', 'Infortunio'),
  nearMiss('near_miss', 'Quasi incidente');

  const IncidentKind(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static IncidentKind fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => IncidentKind.nearMiss);
}

enum Severity {
  none('none', 'Nessun danno'),
  firstAid('first_aid', 'Primo soccorso'),
  medical('medical', 'Cure mediche'),
  lostTime('lost_time', 'Giorni di assenza'),
  serious('serious', 'Grave');

  const Severity(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static Severity fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => Severity.none);
}

enum IncidentStep {
  investigation('investigation', 'Indagine sulle cause'),
  corrective('corrective', 'Azione correttiva'),
  inailReport('inail_report', 'Denuncia INAIL'),
  closure('closure', 'Chiusura');

  const IncidentStep(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static IncidentStep fromDb(String? v) =>
      values.firstWhere((k) => k.dbValue == v, orElse: () => IncidentStep.investigation);
}

/// Replica la regola del database: denuncia INAIL se oltre 3 giorni di assenza o infortunio grave.
bool inailReportRequired(IncidentKind kind, Severity severity, int daysLost) =>
    kind == IncidentKind.injury && (daysLost > 3 || severity == Severity.serious);

class IncidentAction {
  const IncidentAction({
    required this.id,
    required this.step,
    required this.description,
    required this.performedAt,
    this.reference,
  });
  final String id;
  final IncidentStep step;
  final String description;
  final DateTime performedAt;
  final String? reference;

  factory IncidentAction.fromMap(Map<String, dynamic> m) => IncidentAction(
        id: m['id'] as String,
        step: IncidentStep.fromDb(m['step'] as String?),
        description: m['description'] as String,
        performedAt: DateTime.parse(m['performed_at'] as String).toLocal(),
        reference: m['reference'] as String?,
      );
}

class Incident {
  const Incident({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.description,
    required this.severity,
    required this.daysLost,
    required this.inailRequired,
    required this.actions,
    this.employeeName,
    this.area,
    this.bodyPart,
  });
  final String id;
  final IncidentKind kind;
  final DateTime occurredAt;
  final String description;
  final Severity severity;
  final int daysLost;
  final bool inailRequired;
  final String? employeeName;
  final String? area;
  final String? bodyPart;
  final List<IncidentAction> actions;

  bool has(IncidentStep s) => actions.any((a) => a.step == s);
  bool get closed => has(IncidentStep.closure);

  /// Passi ancora necessari prima della chiusura.
  List<IncidentStep> pendingSteps() {
    if (closed) return const [];
    return [
      if (!has(IncidentStep.investigation) && !has(IncidentStep.corrective)) IncidentStep.investigation,
      if (inailRequired && !has(IncidentStep.inailReport)) IncidentStep.inailReport,
    ];
  }

  bool get canClose =>
      !closed &&
      (has(IncidentStep.investigation) || has(IncidentStep.corrective)) &&
      (!inailRequired || has(IncidentStep.inailReport));

  /// Passi che l'utente puo' ancora registrare (la denuncia solo se prevista).
  List<IncidentStep> get availableSteps => closed
      ? const []
      : [
          IncidentStep.investigation,
          IncidentStep.corrective,
          if (inailRequired && !has(IncidentStep.inailReport)) IncidentStep.inailReport,
          if (canClose) IncidentStep.closure,
        ];

  factory Incident.fromMap(Map<String, dynamic> m) {
    final e = m['employees'] as Map<String, dynamic>?;
    return Incident(
      id: m['id'] as String,
      kind: IncidentKind.fromDb(m['kind'] as String?),
      occurredAt: DateTime.parse(m['occurred_at'] as String).toLocal(),
      description: m['description'] as String,
      severity: Severity.fromDb(m['severity'] as String?),
      daysLost: (m['days_lost'] as num?)?.toInt() ?? 0,
      inailRequired: (m['inail_report_required'] as bool?) ?? false,
      employeeName: e == null ? null : '${e['first_name']} ${e['last_name']}',
      area: m['area'] as String?,
      bodyPart: m['body_part'] as String?,
      actions: [
        for (final a in (m['incident_actions'] as List?) ?? const []) IncidentAction.fromMap(a as Map<String, dynamic>)
      ]..sort((a, b) => a.performedAt.compareTo(b.performedAt)),
    );
  }
}

class IncidentStats {
  const IncidentStats({required this.injuries, required this.nearMisses, required this.daysLost, required this.open});
  final int injuries;
  final int nearMisses;
  final int daysLost;
  final int open;
}

class IncidentData {
  const IncidentData({required this.incidents});
  final List<Incident> incidents;
  static const empty = IncidentData(incidents: []);

  /// Ultimi 12 mesi.
  IncidentStats stats(DateTime today) {
    final since = DateTime(today.year - 1, today.month, today.day);
    final recent = incidents.where((i) => i.occurredAt.isAfter(since)).toList();
    return IncidentStats(
      injuries: recent.where((i) => i.kind == IncidentKind.injury).length,
      nearMisses: recent.where((i) => i.kind == IncidentKind.nearMiss).length,
      daysLost: recent.fold(0, (a, i) => a + i.daysLost),
      open: incidents.where((i) => !i.closed).length,
    );
  }

  int get inailPending => incidents.where((i) => i.inailRequired && !i.has(IncidentStep.inailReport)).length;
}
