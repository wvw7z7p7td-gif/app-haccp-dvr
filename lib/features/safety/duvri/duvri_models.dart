// Modelli puri per appaltatori e DUVRI (D.Lgs. 81/08 art. 26).

enum ContractorDocType {
  chamber('chamber_of_commerce', 'Visura camerale', true),
  durc('durc', 'DURC', true),
  insurance('insurance', 'Polizza assicurativa', true),
  fitness('technical_fitness', 'Idoneita\' tecnico-professionale', true),
  dvr('dvr', 'DVR / autocertificazione', false),
  other('other', 'Altro', false);

  const ContractorDocType(this.dbValue, this.label, this.required);
  final String dbValue;
  final String label;
  final bool required;
  static ContractorDocType fromDb(String? v) =>
      values.firstWhere((t) => t.dbValue == v, orElse: () => ContractorDocType.other);
}

enum DocValidity { valid, expiring, expired, missing }

class ContractorDoc {
  const ContractorDoc({
    required this.id,
    required this.type,
    this.issuedOn,
    this.expiresOn,
    this.filePath,
  });
  final String id;
  final ContractorDocType type;
  final DateTime? issuedOn;
  final DateTime? expiresOn;
  final String? filePath;

  /// Un documento senza file allegato non fa fede (come nel database).
  DocValidity validity(DateTime today, {int expiringDays = 30}) {
    if (filePath == null) return DocValidity.missing;
    final t = DateTime(today.year, today.month, today.day);
    if (expiresOn == null) return DocValidity.valid;
    if (expiresOn!.isBefore(t)) return DocValidity.expired;
    if (expiresOn!.isBefore(t.add(Duration(days: expiringDays)))) return DocValidity.expiring;
    return DocValidity.valid;
  }

  factory ContractorDoc.fromMap(Map<String, dynamic> m) => ContractorDoc(
        id: m['id'] as String,
        type: ContractorDocType.fromDb(m['doc_type'] as String?),
        issuedOn: m['issued_on'] == null ? null : DateTime.parse(m['issued_on'] as String),
        expiresOn: m['expires_on'] == null ? null : DateTime.parse(m['expires_on'] as String),
        filePath: m['file_path'] as String?,
      );
}

class Contractor {
  const Contractor({
    required this.id,
    required this.name,
    this.vat,
    this.contact,
    this.phone,
    this.email,
    this.activity,
    this.docs = const [],
  });
  final String id;
  final String name;
  final String? vat;
  final String? contact;
  final String? phone;
  final String? email;
  final String? activity;
  final List<ContractorDoc> docs;

  /// Tipi obbligatori senza nessun documento valido (non scaduto, con file).
  List<ContractorDocType> missingRequired(DateTime today) => [
        for (final t in ContractorDocType.values)
          if (t.required &&
              !docs.any((d) {
                if (d.type != t) return false;
                final v = d.validity(today);
                return v == DocValidity.valid || v == DocValidity.expiring;
              }))
            t
      ];

  bool isCompliant(DateTime today) => missingRequired(today).isEmpty;

  /// Prima scadenza tra i documenti validi (per l'avviso "in scadenza").
  DateTime? nextExpiry(DateTime today) {
    DateTime? best;
    for (final d in docs) {
      final v = d.validity(today);
      if ((v == DocValidity.valid || v == DocValidity.expiring) && d.expiresOn != null) {
        if (best == null || d.expiresOn!.isBefore(best)) best = d.expiresOn;
      }
    }
    return best;
  }

  factory Contractor.fromMap(Map<String, dynamic> m) => Contractor(
        id: m['id'] as String,
        name: m['name'] as String,
        vat: m['vat_number'] as String?,
        contact: m['contact_name'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        activity: m['activity'] as String?,
        docs: [
          for (final d in (m['contractor_documents'] as List?) ?? const [])
            if ((d as Map<String, dynamic>)['deleted_at'] == null) ContractorDoc.fromMap(d)
        ],
      );
}

class Interference {
  const Interference({
    required this.id,
    required this.description,
    required this.measures,
    this.area,
    this.responsible,
    this.costEur = 0,
  });
  final String id;
  final String description;
  final String measures;
  final String? area;
  final String? responsible;
  final double costEur;

  factory Interference.fromMap(Map<String, dynamic> m) => Interference(
        id: m['id'] as String,
        description: m['description'] as String,
        measures: m['measures'] as String,
        area: m['area'] as String?,
        responsible: m['responsible'] as String?,
        costEur: (m['cost_eur'] as num?)?.toDouble() ?? 0,
      );
}

enum DuvriStage { draft, issued, signed, closed }

class Duvri {
  const Duvri({
    required this.id,
    required this.contractorId,
    required this.contractorName,
    required this.activity,
    required this.status,
    required this.noInterference,
    required this.interferences,
    required this.signedParties,
    this.areas,
    this.startsOn,
    this.endsOn,
    this.issuedAt,
    this.snapshotSha,
    this.override,
  });
  final String id;
  final String contractorId;
  final String contractorName;
  final String activity;
  final String? areas;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String status; // draft | signed | closed
  final bool noInterference;
  final DateTime? issuedAt;
  final String? snapshotSha;
  final String? override;
  final List<Interference> interferences;
  final Set<String> signedParties; // employer | contractor

  DuvriStage get stage => switch (status) {
        'closed' => DuvriStage.closed,
        'signed' => DuvriStage.signed,
        _ => issuedAt == null ? DuvriStage.draft : DuvriStage.issued,
      };

  String get stageLabel => switch (stage) {
        DuvriStage.draft => 'Bozza',
        DuvriStage.issued => signedParties.isEmpty ? 'Emesso, da firmare' : 'Firmato da una parte',
        DuvriStage.signed => 'Firmato',
        DuvriStage.closed => 'Chiuso',
      };

  double get totalCost => interferences.fold(0.0, (a, i) => a + i.costEur);

  /// Pronto per l'emissione: interferenze elencate oppure assenza dichiarata (mai entrambe).
  bool get readyToIssue =>
      stage == DuvriStage.draft &&
      ((interferences.isNotEmpty && !noInterference) || (interferences.isEmpty && noInterference));

  /// Lavori in corso (firmato e nel periodo) o scaduto da chiudere.
  bool needsClosing(DateTime today) =>
      stage == DuvriStage.signed && endsOn != null && endsOn!.isBefore(DateTime(today.year, today.month, today.day));

  factory Duvri.fromMap(Map<String, dynamic> m) => Duvri(
        id: m['id'] as String,
        contractorId: m['contractor_id'] as String,
        contractorName: (m['contractors'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
        activity: m['activity_description'] as String,
        areas: m['areas_involved'] as String?,
        startsOn: m['starts_on'] == null ? null : DateTime.parse(m['starts_on'] as String),
        endsOn: m['ends_on'] == null ? null : DateTime.parse(m['ends_on'] as String),
        status: m['status'] as String,
        noInterference: (m['no_interference'] as bool?) ?? false,
        issuedAt: m['issued_at'] == null ? null : DateTime.parse(m['issued_at'] as String).toLocal(),
        snapshotSha: m['snapshot_sha256'] as String?,
        override: m['compliance_override'] as String?,
        interferences: [
          for (final i in (m['duvri_interferences'] as List?) ?? const [])
            Interference.fromMap(i as Map<String, dynamic>)
        ],
        signedParties: {
          for (final s in (m['duvri_signatures'] as List?) ?? const []) (s as Map<String, dynamic>)['party'] as String
        },
      );
}

class DuvriData {
  const DuvriData({required this.contractors, required this.duvris});
  final List<Contractor> contractors;
  final List<Duvri> duvris;
  static const empty = DuvriData(contractors: [], duvris: []);

  Contractor? contractor(String id) {
    for (final c in contractors) {
      if (c.id == id) return c;
    }
    return null;
  }

  int nonCompliantContractors(DateTime today) =>
      contractors.where((c) => !c.isCompliant(today)).length;

  int docsExpiringSoon(DateTime today) {
    final limit = today.add(const Duration(days: 30));
    var n = 0;
    for (final c in contractors) {
      for (final d in c.docs) {
        if (d.validity(today) == DocValidity.expiring && d.expiresOn!.isBefore(limit)) n++;
      }
    }
    return n;
  }
}
