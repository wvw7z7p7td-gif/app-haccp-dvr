import '../cleaning/cleaning_models.dart' show dbDate, dateOnly;

enum ReceiptOutcome {
  accepted('accepted', 'Accettato'),
  reservation('accepted_with_reservation', 'Accettato con riserva'),
  rejected('rejected', 'Respinto');

  const ReceiptOutcome(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ReceiptOutcome fromDb(String? v) =>
      values.firstWhere((o) => o.dbValue == v, orElse: () => ReceiptOutcome.accepted);
}

enum ExpiryKind {
  useBy('use_by', 'Scadenza'),
  bestBefore('best_before', 'TMC');

  const ExpiryKind(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static ExpiryKind fromDb(String? v) =>
      values.firstWhere((o) => o.dbValue == v, orElse: () => ExpiryKind.useBy);
}

enum RecallAction {
  withdrawn('withdrawn', 'Ritirato dalla vendita/uso'),
  discarded('discarded', 'Smaltito'),
  returnedToSupplier('returned_to_supplier', 'Reso al fornitore'),
  authorityNotified('authority_notified', 'Autorita\' avvisata');

  const RecallAction(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

/// Esito del controllo di una riga alla consegna. Replica le regole del trigger
/// `goods_receipt_lines_prepare` (il database resta comunque l'ultima barriera).
class LineCheck {
  const LineCheck({required this.tempOut, required this.expired, required this.allowed});
  final bool tempOut;
  final bool expired;
  final List<ReceiptOutcome> allowed;

  bool get hasProblem => tempOut || expired;

  /// Esito proposto in automatico.
  ReceiptOutcome get suggested => allowed.first;
}

LineCheck evaluateLine({
  double? tempC,
  double? minC,
  double? maxC,
  DateTime? expiry,
  ExpiryKind kind = ExpiryKind.useBy,
  required DateTime receivedOn,
}) {
  final tempOut = tempC != null &&
      ((minC != null && tempC < minC) || (maxC != null && tempC > maxC));
  final expired = expiry != null && dateOnly(expiry).isBefore(dateOnly(receivedOn));
  final List<ReceiptOutcome> allowed;
  if (expired && kind == ExpiryKind.useBy) {
    allowed = [ReceiptOutcome.rejected];
  } else if (expired || tempOut) {
    allowed = [ReceiptOutcome.rejected, ReceiptOutcome.reservation];
  } else {
    allowed = [ReceiptOutcome.accepted, ReceiptOutcome.reservation, ReceiptOutcome.rejected];
  }
  return LineCheck(tempOut: tempOut, expired: expired, allowed: allowed);
}

class Supplier {
  const Supplier({required this.id, required this.name, this.vat, this.phone});
  final String id;
  final String name;
  final String? vat;
  final String? phone;

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'] as String,
        name: m['name'] as String,
        vat: m['vat_number'] as String?,
        phone: m['phone'] as String?,
      );
}

class SupplierStats {
  const SupplierStats({
    required this.supplierId,
    required this.receipts,
    required this.lines,
    required this.rejected,
    required this.reservations,
  });
  final String supplierId;
  final int receipts;
  final int lines;
  final int rejected;
  final int reservations;

  /// Quota di righe non conformi (respinte o con riserva) negli ultimi 12 mesi.
  double get nonConformityRate => lines == 0 ? 0 : (rejected + reservations) / lines;

  factory SupplierStats.fromMap(Map<String, dynamic> m) => SupplierStats(
        supplierId: m['supplier_id'] as String,
        receipts: (m['receipts_12m'] as num?)?.toInt() ?? 0,
        lines: (m['lines_12m'] as num?)?.toInt() ?? 0,
        rejected: (m['rejected_12m'] as num?)?.toInt() ?? 0,
        reservations: (m['reservation_12m'] as num?)?.toInt() ?? 0,
      );
}

class CatalogProduct {
  const CatalogProduct({required this.id, required this.name, this.supplierId, this.minC, this.maxC});
  final String id;
  final String name;
  final String? supplierId;
  final double? minC;
  final double? maxC;

  factory CatalogProduct.fromMap(Map<String, dynamic> m) => CatalogProduct(
        id: m['id'] as String,
        name: m['name'] as String,
        supplierId: m['supplier_id'] as String?,
        minC: (m['delivery_min_c'] as num?)?.toDouble(),
        maxC: (m['delivery_max_c'] as num?)?.toDouble(),
      );
}

class ReceiptLine {
  const ReceiptLine({
    required this.id,
    required this.productName,
    required this.outcome,
    required this.expiryKind,
    this.lotCode,
    this.expiry,
    this.quantity,
    this.unit,
    this.tempC,
    this.minC,
    this.maxC,
    this.tempOut = false,
    this.expired = false,
    this.packagingOk = true,
    this.labelOk = true,
    this.notes,
  });

  final String id;
  final String productName;
  final String? lotCode;
  final DateTime? expiry;
  final ExpiryKind expiryKind;
  final double? quantity;
  final String? unit;
  final double? tempC;
  final double? minC;
  final double? maxC;
  final bool tempOut;
  final bool expired;
  final bool packagingOk;
  final bool labelOk;
  final ReceiptOutcome outcome;
  final String? notes;

  bool get nonConforming => outcome != ReceiptOutcome.accepted;

  factory ReceiptLine.fromMap(Map<String, dynamic> m) => ReceiptLine(
        id: m['id'] as String,
        productName: m['product_name'] as String,
        lotCode: m['lot_code'] as String?,
        expiry: m['expiry_date'] == null ? null : DateTime.parse(m['expiry_date'] as String),
        expiryKind: ExpiryKind.fromDb(m['expiry_kind'] as String?),
        quantity: (m['quantity'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        tempC: (m['temp_c'] as num?)?.toDouble(),
        minC: (m['min_limit_c'] as num?)?.toDouble(),
        maxC: (m['max_limit_c'] as num?)?.toDouble(),
        tempOut: (m['temp_out_of_range'] as bool?) ?? false,
        expired: (m['expired'] as bool?) ?? false,
        packagingOk: (m['packaging_ok'] as bool?) ?? true,
        labelOk: (m['label_ok'] as bool?) ?? true,
        outcome: ReceiptOutcome.fromDb(m['outcome'] as String?),
        notes: m['notes'] as String?,
      );
}

class GoodsReceipt {
  const GoodsReceipt({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.docDate,
    required this.receivedAt,
    required this.lines,
    this.docNumber,
    this.operatorName,
    this.vehicleOk = true,
    this.photoPath,
    this.notes,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String? docNumber;
  final DateTime docDate;
  final DateTime receivedAt;
  final String? operatorName;
  final bool vehicleOk;
  final String? photoPath;
  final String? notes;
  final List<ReceiptLine> lines;

  int get rejectedCount => lines.where((l) => l.outcome == ReceiptOutcome.rejected).length;
  int get reservationCount => lines.where((l) => l.outcome == ReceiptOutcome.reservation).length;
  bool get hasIssues => rejectedCount > 0 || reservationCount > 0 || !vehicleOk;

  factory GoodsReceipt.fromMap(Map<String, dynamic> m) {
    final emp = m['employees'] as Map<String, dynamic>?;
    final lines = ((m['goods_receipt_lines'] as List?) ?? const [])
        .map((e) => ReceiptLine.fromMap(e as Map<String, dynamic>))
        .toList();
    return GoodsReceipt(
      id: m['id'] as String,
      supplierId: m['supplier_id'] as String,
      supplierName: (m['suppliers'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
      docNumber: m['doc_number'] as String?,
      docDate: DateTime.parse(m['doc_date'] as String),
      receivedAt: DateTime.parse(m['received_at'] as String).toLocal(),
      operatorName: emp == null ? null : '${emp['first_name']} ${emp['last_name']}',
      vehicleOk: (m['vehicle_ok'] as bool?) ?? true,
      photoPath: m['doc_photo_path'] as String?,
      notes: m['notes'] as String?,
      lines: lines,
    );
  }
}

/// Risultato della ricerca per lotto (rintracciabilita' a monte e a valle).
class LotHit {
  const LotHit({
    required this.line,
    required this.supplierName,
    required this.receivedAt,
    this.docNumber,
  });
  final ReceiptLine line;
  final String supplierName;
  final DateTime receivedAt;
  final String? docNumber;

  factory LotHit.fromMap(Map<String, dynamic> m) {
    final r = m['goods_receipts'] as Map<String, dynamic>;
    return LotHit(
      line: ReceiptLine.fromMap(m),
      supplierName: (r['suppliers'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
      receivedAt: DateTime.parse(r['received_at'] as String).toLocal(),
      docNumber: r['doc_number'] as String?,
    );
  }
}

class ReceivingData {
  const ReceivingData({required this.receipts, required this.suppliers, required this.stats});
  final List<GoodsReceipt> receipts;
  final List<Supplier> suppliers;
  final Map<String, SupplierStats> stats;

  static const empty = ReceivingData(receipts: [], suppliers: [], stats: {});

  List<GoodsReceipt> receivedOn(DateTime day) {
    final d = dateOnly(day);
    return receipts.where((r) => dateOnly(r.receivedAt) == d).toList();
  }

  /// Righe in scadenza entro [days] giorni (stock presunto, non e' una giacenza reale).
  int get issuesLast30Days {
    final since = DateTime.now().subtract(const Duration(days: 30));
    return receipts.where((r) => r.receivedAt.isAfter(since) && r.hasIssues).length;
  }
}

String lotDay(DateTime d) => dbDate(d);
