// Modelli puri per persone, formazione e DPI.

enum Validity { valid, expiring, expired, missing }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

Validity validityFor(DateTime? expiresOn, DateTime today, {int expiringDays = 30}) {
  if (expiresOn == null) return Validity.valid;
  final t = _day(today);
  if (_day(expiresOn).isBefore(t)) return Validity.expired;
  if (_day(expiresOn).isBefore(t.add(Duration(days: expiringDays)))) return Validity.expiring;
  return Validity.valid;
}

class TrainingType {
  const TrainingType({required this.id, required this.code, required this.name, this.validityMonths, this.custom = false});
  final String id;
  final String code;
  final String name;
  final int? validityMonths;
  final bool custom;

  factory TrainingType.fromMap(Map<String, dynamic> m) => TrainingType(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        validityMonths: (m['validity_months'] as num?)?.toInt(),
        custom: m['company_id'] != null,
      );
}

class PpeType {
  const PpeType({required this.id, required this.name, this.category, this.standard, this.replaceAfterMonths});
  final String id;
  final String name;
  final int? category;
  final String? standard;
  final int? replaceAfterMonths;

  factory PpeType.fromMap(Map<String, dynamic> m) => PpeType(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] as num?)?.toInt(),
        standard: m['standard_en'] as String?,
        replaceAfterMonths: (m['replace_after_months'] as num?)?.toInt(),
      );
}

class JobRole {
  const JobRole({required this.id, required this.name, this.trainingIds = const {}, this.ppeIds = const {}});
  final String id;
  final String name;
  final Set<String> trainingIds;
  final Set<String> ppeIds;

  factory JobRole.fromMap(Map<String, dynamic> m) => JobRole(
        id: m['id'] as String,
        name: m['name'] as String,
        trainingIds: {
          for (final r in (m['job_role_training_requirements'] as List?) ?? const [])
            (r as Map<String, dynamic>)['training_type_id'] as String
        },
        ppeIds: {
          for (final r in (m['job_role_ppe'] as List?) ?? const []) (r as Map<String, dynamic>)['ppe_type_id'] as String
        },
      );
}

class TrainingRecord {
  const TrainingRecord({
    required this.id,
    required this.employeeId,
    required this.typeId,
    required this.issuedOn,
    this.expiresOn,
    this.provider,
    this.hours,
    this.certificatePath,
  });
  final String id;
  final String employeeId;
  final String typeId;
  final DateTime issuedOn;
  final DateTime? expiresOn;
  final String? provider;
  final double? hours;
  final String? certificatePath;

  factory TrainingRecord.fromMap(Map<String, dynamic> m) => TrainingRecord(
        id: m['id'] as String,
        employeeId: m['employee_id'] as String,
        typeId: m['training_type_id'] as String,
        issuedOn: DateTime.parse(m['issued_on'] as String),
        expiresOn: m['expires_on'] == null ? null : DateTime.parse(m['expires_on'] as String),
        provider: m['provider'] as String?,
        hours: (m['hours'] as num?)?.toDouble(),
        certificatePath: m['certificate_path'] as String?,
      );
}

class PpeAssignment {
  const PpeAssignment({
    required this.id,
    required this.employeeId,
    required this.typeId,
    required this.deliveredOn,
    this.expiresOn,
    this.size,
    this.serial,
    this.returnedOn,
  });
  final String id;
  final String employeeId;
  final String typeId;
  final DateTime deliveredOn;
  final DateTime? expiresOn;
  final String? size;
  final String? serial;
  final DateTime? returnedOn;

  factory PpeAssignment.fromMap(Map<String, dynamic> m) => PpeAssignment(
        id: m['id'] as String,
        employeeId: m['employee_id'] as String,
        typeId: m['ppe_type_id'] as String,
        deliveredOn: DateTime.parse(m['delivered_on'] as String),
        expiresOn: m['expires_on'] == null ? null : DateTime.parse(m['expires_on'] as String),
        size: m['size'] as String?,
        serial: m['serial_number'] as String?,
        returnedOn: m['returned_on'] == null ? null : DateTime.parse(m['returned_on'] as String),
      );
}

class Employee {
  const Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isSupervisor,
    required this.active,
    this.jobRoleId,
    this.hireDate,
  });
  final String id;
  final String firstName;
  final String lastName;
  final bool isSupervisor;
  final bool active;
  final String? jobRoleId;
  final DateTime? hireDate;

  String get fullName => '$firstName $lastName';

  factory Employee.fromMap(Map<String, dynamic> m) => Employee(
        id: m['id'] as String,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String,
        isSupervisor: (m['is_supervisor'] as bool?) ?? false,
        active: (m['active'] as bool?) ?? true,
        jobRoleId: m['job_role_id'] as String?,
        hireDate: m['hire_date'] == null ? null : DateTime.parse(m['hire_date'] as String),
      );
}

class DeadlineItem {
  const DeadlineItem({required this.kind, required this.label, required this.dueOn, this.employeeId});
  final String kind;
  final String label;
  final DateTime dueOn;
  final String? employeeId;

  int daysLeft(DateTime today) => _day(dueOn).difference(_day(today)).inDays;

  String get kindLabel => switch (kind) {
        'training' => 'Formazione',
        'ppe' => 'DPI',
        'dvr_review' => 'Revisione DVR',
        'contractor_doc' => 'Documento appaltatore',
        'safety_officer' => 'Incarico sicurezza',
        'dvr_action' => 'Azione DVR',
        _ => kind,
      };

  factory DeadlineItem.fromMap(Map<String, dynamic> m) => DeadlineItem(
        kind: m['kind'] as String,
        label: m['label'] as String,
        dueOn: DateTime.parse(m['due_on'] as String),
        employeeId: m['employee_id'] as String?,
      );
}

class PeopleData {
  const PeopleData({
    required this.employees,
    required this.roles,
    required this.trainingTypes,
    required this.trainingRecords,
    required this.ppeTypes,
    required this.ppeAssignments,
    required this.deadlines,
  });
  final List<Employee> employees;
  final List<JobRole> roles;
  final List<TrainingType> trainingTypes;
  final List<TrainingRecord> trainingRecords;
  final List<PpeType> ppeTypes;
  final List<PpeAssignment> ppeAssignments;
  final List<DeadlineItem> deadlines;

  static const empty = PeopleData(
      employees: [], roles: [], trainingTypes: [], trainingRecords: [], ppeTypes: [], ppeAssignments: [], deadlines: []);

  Employee? employee(String id) {
    for (final e in employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  JobRole? roleOf(Employee e) {
    for (final r in roles) {
      if (r.id == e.jobRoleId) return r;
    }
    return null;
  }

  TrainingType? trainingType(String id) {
    for (final t in trainingTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  PpeType? ppeType(String id) {
    for (final t in ppeTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Stato della formazione `typeId` di una persona (considera l'attestato piu' recente).
  Validity trainingStatus(String employeeId, String typeId, DateTime today) {
    final recs = trainingRecords.where((r) => r.employeeId == employeeId && r.typeId == typeId).toList();
    if (recs.isEmpty) return Validity.missing;
    recs.sort((a, b) => b.issuedOn.compareTo(a.issuedOn));
    return validityFor(recs.first.expiresOn, today);
  }

  /// Stato del DPI `typeId` di una persona (solo consegne non restituite).
  Validity ppeStatus(String employeeId, String typeId, DateTime today) {
    final list = ppeAssignments
        .where((a) => a.employeeId == employeeId && a.typeId == typeId && a.returnedOn == null)
        .toList();
    if (list.isEmpty) return Validity.missing;
    // vale la consegna con scadenza piu' lontana (nessuna scadenza = senza limite)
    DateTime? best;
    var unlimited = false;
    for (final a in list) {
      if (a.expiresOn == null) {
        unlimited = true;
      } else if (best == null || a.expiresOn!.isAfter(best)) {
        best = a.expiresOn;
      }
    }
    return unlimited ? Validity.valid : validityFor(best, today);
  }

  /// Problemi della persona: formazione e DPI richiesti dalla mansione, non validi.
  ({int training, int ppe, int expiring}) issuesFor(Employee e, DateTime today) {
    final role = roleOf(e);
    if (role == null) return (training: 0, ppe: 0, expiring: 0);
    var t = 0, p = 0, x = 0;
    for (final id in role.trainingIds) {
      final s = trainingStatus(e.id, id, today);
      if (s == Validity.missing || s == Validity.expired) t++;
      if (s == Validity.expiring) x++;
    }
    for (final id in role.ppeIds) {
      final s = ppeStatus(e.id, id, today);
      if (s == Validity.missing || s == Validity.expired) p++;
      if (s == Validity.expiring) x++;
    }
    return (training: t, ppe: p, expiring: x);
  }

  int totalIssues(DateTime today) {
    var n = 0;
    for (final e in employees.where((e) => e.active)) {
      final i = issuesFor(e, today);
      n += i.training + i.ppe;
    }
    return n;
  }

  List<DeadlineItem> deadlinesWithin(DateTime today, int days) =>
      deadlines.where((d) => d.daysLeft(today) <= days).toList()..sort((a, b) => a.dueOn.compareTo(b.dueOn));
}
