// Modelli puri per il DVR digitale (matrice rischio P x D, scala 1-4).

enum RiskLevel {
  low('low', 'Basso'),
  medium('medium', 'Medio'),
  high('high', 'Alto'),
  veryHigh('very_high', 'Molto alto');

  const RiskLevel(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

/// Replica `risk_level()` del database: <=2 basso, <=4 medio, <=8 alto, altrimenti molto alto.
RiskLevel riskLevelFor(int score) {
  if (score <= 2) return RiskLevel.low;
  if (score <= 4) return RiskLevel.medium;
  if (score <= 8) return RiskLevel.high;
  return RiskLevel.veryHigh;
}

const probabilityLabels = {1: 'Improbabile', 2: 'Poco probabile', 3: 'Probabile', 4: 'Molto probabile'};
const severityLabels = {1: 'Lieve', 2: 'Modesta', 3: 'Grave', 4: 'Gravissima'};

class Hazard {
  const Hazard({required this.id, required this.code, required this.category, required this.name, this.example});
  final String id;
  final String code;
  final String category;
  final String name;
  final String? example;

  factory Hazard.fromMap(Map<String, dynamic> m) => Hazard(
        id: m['id'] as String,
        code: m['code'] as String,
        category: m['category'] as String,
        name: m['name'] as String,
        example: m['example'] as String?,
      );
}

enum ActionStatus {
  open('open', 'Da fare'),
  inProgress('in_progress', 'In corso'),
  done('done', 'Completata');

  const ActionStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static ActionStatus fromDb(String? v) =>
      values.firstWhere((s) => s.dbValue == v, orElse: () => ActionStatus.open);
}

class DvrAction {
  const DvrAction({
    required this.id,
    required this.riskId,
    required this.description,
    required this.status,
    this.responsible,
    this.dueOn,
    this.doneOn,
  });
  final String id;
  final String riskId;
  final String description;
  final ActionStatus status;
  final String? responsible;
  final DateTime? dueOn;
  final DateTime? doneOn;

  bool isOverdue(DateTime today) =>
      status != ActionStatus.done &&
      dueOn != null &&
      dueOn!.isBefore(DateTime(today.year, today.month, today.day));

  factory DvrAction.fromMap(Map<String, dynamic> m) => DvrAction(
        id: m['id'] as String,
        riskId: m['risk_id'] as String,
        description: m['description'] as String,
        status: ActionStatus.fromDb(m['status'] as String?),
        responsible: m['responsible'] as String?,
        dueOn: m['due_on'] == null ? null : DateTime.parse(m['due_on'] as String),
        doneOn: m['done_on'] == null ? null : DateTime.parse(m['done_on'] as String),
      );
}

class DvrRisk {
  const DvrRisk({
    required this.id,
    required this.title,
    required this.hazardId,
    required this.hazardName,
    required this.probability,
    required this.severity,
    this.siteId,
    this.areaId,
    this.areaName,
    this.jobRoleId,
    this.jobRoleName,
    this.description,
    this.measures,
    this.residualProbability,
    this.residualSeverity,
    this.actions = const [],
  });

  final String id;
  final String title;
  final String? description;
  final String hazardId;
  final String hazardName;
  final String? siteId;
  final String? areaId;
  final String? areaName;
  final String? jobRoleId;
  final String? jobRoleName;
  final int probability;
  final int severity;
  final String? measures;
  final int? residualProbability;
  final int? residualSeverity;
  final List<DvrAction> actions;

  int get score => probability * severity;
  RiskLevel get level => riskLevelFor(score);
  int? get residualScore =>
      residualProbability == null || residualSeverity == null ? null : residualProbability! * residualSeverity!;
  RiskLevel? get residualLevel => residualScore == null ? null : riskLevelFor(residualScore!);

  int get openActions => actions.where((a) => a.status != ActionStatus.done).length;

  /// Rischio che richiede attenzione: alto/molto alto senza misure descritte o senza azioni aperte.
  bool get needsAttention =>
      level.index >= RiskLevel.high.index &&
      (measures == null || measures!.trim().isEmpty) &&
      openActions == 0;

  factory DvrRisk.fromMap(Map<String, dynamic> m) => DvrRisk(
        id: m['id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        hazardId: m['hazard_id'] as String,
        hazardName: (m['hazard_catalog'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
        siteId: m['site_id'] as String?,
        areaId: m['area_id'] as String?,
        areaName: (m['areas'] as Map<String, dynamic>?)?['name'] as String?,
        jobRoleId: m['job_role_id'] as String?,
        jobRoleName: (m['job_roles'] as Map<String, dynamic>?)?['name'] as String?,
        probability: (m['probability'] as num).toInt(),
        severity: (m['severity'] as num).toInt(),
        measures: m['measures'] as String?,
        residualProbability: (m['residual_probability'] as num?)?.toInt(),
        residualSeverity: (m['residual_severity'] as num?)?.toInt(),
        actions: [
          for (final a in (m['dvr_actions'] as List?) ?? const [])
            if ((a as Map<String, dynamic>)['deleted_at'] == null) DvrAction.fromMap(a)
        ],
      );
}

enum SafetyRole {
  employer('employer', 'Datore di lavoro'),
  rspp('rspp', 'RSPP'),
  rls('rls', 'RLS'),
  companyDoctor('company_doctor', 'Medico competente'),
  fireOfficer('fire_officer', 'Addetto antincendio'),
  firstAid('first_aid_officer', 'Addetto primo soccorso');

  const SafetyRole(this.dbValue, this.label);
  final String dbValue;
  final String label;
  static SafetyRole fromDb(String? v) =>
      values.firstWhere((s) => s.dbValue == v, orElse: () => SafetyRole.employer);
}

class SafetyOfficer {
  const SafetyOfficer({
    required this.id,
    required this.role,
    required this.name,
    this.appointedOn,
    this.endsOn,
  });
  final String id;
  final SafetyRole role;
  final String name;
  final DateTime? appointedOn;
  final DateTime? endsOn;

  bool isActive(DateTime today) =>
      endsOn == null || !endsOn!.isBefore(DateTime(today.year, today.month, today.day));

  factory SafetyOfficer.fromMap(Map<String, dynamic> m) {
    final e = m['employees'] as Map<String, dynamic>?;
    return SafetyOfficer(
      id: m['id'] as String,
      role: SafetyRole.fromDb(m['role'] as String?),
      name: (m['external_name'] as String?) ?? (e == null ? '—' : '${e['first_name']} ${e['last_name']}'),
      appointedOn: m['appointed_on'] == null ? null : DateTime.parse(m['appointed_on'] as String),
      endsOn: m['ends_on'] == null ? null : DateTime.parse(m['ends_on'] as String),
    );
  }
}

class DvrVersion {
  const DvrVersion({
    required this.id,
    required this.version,
    required this.status,
    this.siteId,
    this.issuedOn,
    this.nextReviewOn,
    this.sha256,
    this.riskCount,
  });
  final String id;
  final String version;
  final String status; // draft | active | superseded | expired
  final String? siteId;
  final DateTime? issuedOn;
  final DateTime? nextReviewOn;
  final String? sha256;
  final int? riskCount;

  bool get isDraft => status == 'draft';
  bool get isActive => status == 'active';

  String get statusLabel => switch (status) {
        'draft' => 'Bozza',
        'active' => 'In vigore',
        'superseded' => 'Sostituita',
        'expired' => 'Scaduta',
        _ => status,
      };

  bool reviewDue(DateTime today, {int withinDays = 30}) =>
      isActive &&
      nextReviewOn != null &&
      nextReviewOn!.isBefore(today.add(Duration(days: withinDays)));

  factory DvrVersion.fromMap(Map<String, dynamic> m) {
    final snap = m['snapshot'] as Map<String, dynamic>?;
    return DvrVersion(
      id: m['id'] as String,
      version: m['version'] as String,
      status: m['status'] as String,
      siteId: m['site_id'] as String?,
      issuedOn: m['issued_on'] == null ? null : DateTime.parse(m['issued_on'] as String),
      nextReviewOn: m['next_review_on'] == null ? null : DateTime.parse(m['next_review_on'] as String),
      sha256: m['snapshot_sha256'] as String?,
      riskCount: snap == null ? null : (snap['risks'] as List?)?.length,
    );
  }
}

class NamedRef {
  const NamedRef(this.id, this.name);
  final String id;
  final String name;
}

class DvrData {
  const DvrData({
    required this.hazards,
    required this.risks,
    required this.officers,
    required this.versions,
    required this.areas,
    required this.roles,
  });
  final List<Hazard> hazards;
  final List<DvrRisk> risks;
  final List<SafetyOfficer> officers;
  final List<DvrVersion> versions;
  final List<NamedRef> areas;
  final List<NamedRef> roles;

  static const empty =
      DvrData(hazards: [], risks: [], officers: [], versions: [], areas: [], roles: []);

  Map<RiskLevel, int> get countByLevel => {
        for (final l in RiskLevel.values) l: risks.where((r) => r.level == l).length,
      };

  List<DvrAction> get allActions => [for (final r in risks) ...r.actions];

  int overdueActions(DateTime today) => allActions.where((a) => a.isOverdue(today)).length;

  DvrVersion? get current {
    for (final v in versions) {
      if (v.isActive) return v;
    }
    return null;
  }

  /// Figure obbligatorie senza nessuna nomina attiva.
  List<SafetyRole> missingOfficers(DateTime today) => [
        for (final r in const [SafetyRole.employer, SafetyRole.rspp])
          if (!officers.any((o) => o.role == r && o.isActive(today))) r
      ];
}
