enum AppRole {
  admin('admin', 'Titolare / Admin'),
  employee('employee', 'Operatore'),
  consultant('consultant', 'Consulente');

  const AppRole(this.dbValue, this.label);

  final String dbValue;
  final String label;

  /// Un valore sconosciuto degrada al ruolo di sola lettura.
  static AppRole fromDb(String value) =>
      AppRole.values.firstWhere((r) => r.dbValue == value, orElse: () => AppRole.consultant);

  bool get canWrite => this != AppRole.consultant;
  bool get isAdmin => this == AppRole.admin;
}
