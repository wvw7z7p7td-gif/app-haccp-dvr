// Modelli puri (senza dipendenze da Flutter) per pulizie e sanificazione.

String dbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

const weekdayLabels = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const shiftOptions = ['Apertura', 'Durante il servizio', 'Chiusura'];

int shiftRank(String? shift) {
  final i = shiftOptions.indexOf(shift ?? '');
  return i < 0 ? shiftOptions.length : i;
}

enum CleaningFrequency {
  daily('daily', 'Giornaliera'),
  weekly('weekly', 'Settimanale'),
  monthly('monthly', 'Mensile'),
  onEvent('on_event', 'A evento');

  const CleaningFrequency(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static CleaningFrequency fromDb(String v) =>
      values.firstWhere((f) => f.dbValue == v, orElse: () => daily);
}

enum CleaningStatus {
  done('done', 'Eseguita'),
  skipped('skipped', 'Non eseguita'),
  notApplicable('not_applicable', 'Non applicabile');

  const CleaningStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static CleaningStatus fromDb(String v) =>
      values.firstWhere((s) => s.dbValue == v, orElse: () => done);
}

class PlanItem {
  const PlanItem({required this.id, required this.description, required this.sortOrder});
  final String id;
  final String description;
  final int sortOrder;

  factory PlanItem.fromMap(Map<String, dynamic> m) => PlanItem(
        id: m['id'] as String,
        description: m['description'] as String,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class CleaningPlan {
  const CleaningPlan({
    required this.id,
    required this.siteId,
    required this.name,
    required this.frequency,
    required this.weekdays,
    required this.requiresApproval,
    required this.items,
    this.description,
    this.dayOfMonth,
    this.shift,
    this.productName,
    this.method,
    this.dilution,
    this.contactTimeMin,
  });

  final String id;
  final String siteId;
  final String name;
  final String? description;
  final CleaningFrequency frequency;
  final List<int> weekdays; // ISO: 1 = lunedi' .. 7 = domenica
  final int? dayOfMonth;
  final String? shift;
  final String? productName;
  final String? method;
  final String? dilution;
  final int? contactTimeMin;
  final bool requiresApproval;
  final List<PlanItem> items;

  factory CleaningPlan.fromMap(Map<String, dynamic> m) {
    final product = m['cleaning_products'];
    final rawItems = (m['cleaning_plan_items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((i) => i['deleted_at'] == null)
        .map(PlanItem.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return CleaningPlan(
      id: m['id'] as String,
      siteId: m['site_id'] as String,
      name: m['name'] as String,
      description: m['description'] as String?,
      frequency: CleaningFrequency.fromDb(m['frequency'] as String),
      weekdays: (m['weekdays'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
      dayOfMonth: (m['day_of_month'] as num?)?.toInt(),
      shift: m['shift'] as String?,
      productName: product is Map ? product['name'] as String? : null,
      method: m['method'] as String?,
      dilution: m['dilution'] as String?,
      contactTimeMin: (m['contact_time_min'] as num?)?.toInt(),
      requiresApproval: (m['requires_approval'] as bool?) ?? false,
      items: rawItems,
    );
  }

  /// Il piano e' previsto nel giorno indicato? I piani "a evento" non lo sono mai.
  /// Un piano mensile fissato al 31 cade l'ultimo giorno dei mesi piu' corti.
  bool isDueOn(DateTime d) {
    switch (frequency) {
      case CleaningFrequency.daily:
        return true;
      case CleaningFrequency.weekly:
        return weekdays.contains(d.weekday);
      case CleaningFrequency.monthly:
        final last = DateTime(d.year, d.month + 1, 0).day;
        final target = (dayOfMonth ?? 1).clamp(1, last);
        return d.day == target;
      case CleaningFrequency.onEvent:
        return false;
    }
  }

  String get scheduleLabel {
    switch (frequency) {
      case CleaningFrequency.daily:
        return 'Ogni giorno';
      case CleaningFrequency.weekly:
        final days = ([...weekdays]..sort()).map((d) => weekdayLabels[d - 1]).join(', ');
        return days.isEmpty ? 'Settimanale' : days;
      case CleaningFrequency.monthly:
        return 'Il giorno ${dayOfMonth ?? 1} del mese';
      case CleaningFrequency.onEvent:
        return 'A evento';
    }
  }
}

class CleaningLog {
  const CleaningLog({
    required this.id,
    required this.planId,
    required this.planName,
    required this.dueDate,
    required this.status,
    required this.performedAt,
    required this.requiresApproval,
    required this.approved,
    this.employeeId,
    this.employeeName,
    this.notes,
    this.signaturePath,
  });

  final String id;
  final String planId;
  final String planName;
  final DateTime dueDate;
  final CleaningStatus status;
  final DateTime performedAt;
  final bool requiresApproval;
  final bool approved;
  final String? employeeId;
  final String? employeeName;
  final String? notes;
  final String? signaturePath;

  factory CleaningLog.fromMap(Map<String, dynamic> m) {
    final plan = m['cleaning_plans'];
    final emp = m['employees'];
    final appr = m['cleaning_log_approvals'];
    return CleaningLog(
      id: m['id'] as String,
      planId: m['plan_id'] as String,
      planName: plan is Map ? (plan['name'] as String? ?? 'Piano') : 'Piano',
      dueDate: DateTime.parse(m['due_date'] as String),
      status: CleaningStatus.fromDb(m['status'] as String),
      performedAt: DateTime.parse(m['performed_at'] as String).toLocal(),
      requiresApproval: plan is Map && (plan['requires_approval'] as bool? ?? false),
      approved: appr is Map || (appr is List && appr.isNotEmpty),
      employeeId: m['employee_id'] as String?,
      employeeName: emp is Map ? '${emp['first_name']} ${emp['last_name']}' : null,
      notes: m['notes'] as String?,
      signaturePath: m['signature_path'] as String?,
    );
  }
}

class CleaningData {
  const CleaningData({required this.plans, required this.logs});
  static const empty = CleaningData(plans: [], logs: []);

  final List<CleaningPlan> plans;
  final List<CleaningLog> logs; // piu' recenti per prime

  List<CleaningPlan> dueOn(DateTime d) =>
      plans.where((p) => p.isDueOn(d)).toList()
        ..sort((a, b) => shiftRank(a.shift).compareTo(shiftRank(b.shift)));

  List<CleaningPlan> get eventPlans =>
      plans.where((p) => p.frequency == CleaningFrequency.onEvent).toList();

  List<CleaningLog> logsOn(String planId, DateTime d) =>
      logs.where((l) => l.planId == planId && isSameDay(l.dueDate, d)).toList();

  CleaningLog? latestOn(String planId, DateTime d) => logsOn(planId, d).firstOrNull;

  /// Eseguite, ma ancora senza controfirma del responsabile.
  List<CleaningLog> get pendingApprovals => logs
      .where((l) => l.requiresApproval && !l.approved && l.status == CleaningStatus.done)
      .toList();

  int doneOn(DateTime d) =>
      dueOn(d).where((p) => latestOn(p.id, d)?.status == CleaningStatus.done).length;

  int skippedOn(DateTime d) => dueOn(d)
      .where((p) => latestOn(p.id, d)?.status == CleaningStatus.skipped)
      .length;
}

class LogItemDetail {
  const LogItemDetail({required this.text, required this.done});
  final String text;
  final bool done;
}

class CleaningLogDetail {
  const CleaningLogDetail({
    required this.items,
    this.signatureUrl,
    this.approverName,
    this.approvedAt,
    this.approvalSignatureUrl,
  });
  final List<LogItemDetail> items;
  final String? signatureUrl;
  final String? approverName;
  final DateTime? approvedAt;
  final String? approvalSignatureUrl;
}

class PlanItemDraft {
  PlanItemDraft({this.id, required this.description});
  final String? id; // null = nuova voce
  String description;
}

class CleaningTemplate {
  const CleaningTemplate({
    required this.name,
    required this.frequency,
    required this.items,
    this.shift,
    this.weekdays = const [],
    this.dayOfMonth,
  });
  final String name;
  final CleaningFrequency frequency;
  final String? shift;
  final List<int> weekdays;
  final int? dayOfMonth;
  final List<String> items;
}

/// Modelli indicativi: vanno adattati al piano di autocontrollo dell'attivita'.
const cleaningTemplates = <CleaningTemplate>[
  CleaningTemplate(
    name: 'Pulizia e sanificazione piani di lavoro',
    frequency: CleaningFrequency.daily,
    shift: 'Chiusura',
    items: [
      'Rimuovere i residui di lavorazione',
      'Detergere le superfici',
      'Risciacquare con acqua potabile',
      'Applicare il sanificante rispettando il tempo di contatto',
      'Risciacquare e asciugare',
    ],
  ),
  CleaningTemplate(
    name: 'Pulizia attrezzature (affettatrice, planetaria, ecc.)',
    frequency: CleaningFrequency.daily,
    shift: 'Chiusura',
    items: [
      'Scollegare l\'attrezzatura dall\'alimentazione',
      'Smontare le parti a contatto con gli alimenti',
      'Detergere e sanificare le parti smontate',
      'Pulire il corpo macchina',
      'Rimontare e asciugare',
    ],
  ),
  CleaningTemplate(
    name: 'Pulizia pavimenti e scarichi',
    frequency: CleaningFrequency.daily,
    shift: 'Chiusura',
    items: [
      'Spazzare e raccogliere i rifiuti',
      'Lavare il pavimento con detergente',
      'Pulire e sanificare i pozzetti di scarico',
    ],
  ),
  CleaningTemplate(
    name: 'Sanificazione celle e frigoriferi',
    frequency: CleaningFrequency.weekly,
    weekdays: [1],
    shift: 'Apertura',
    items: [
      'Svuotare o spostare i prodotti mantenendo la catena del freddo',
      'Detergere ripiani, pareti e guarnizioni',
      'Sanificare e risciacquare',
      'Riposizionare i prodotti',
    ],
  ),
  CleaningTemplate(
    name: 'Pulizia cappa e filtri',
    frequency: CleaningFrequency.monthly,
    dayOfMonth: 1,
    items: [
      'Smontare e lavare i filtri',
      'Pulire la cappa all\'interno e all\'esterno',
      'Rimontare i filtri',
    ],
  ),
];
