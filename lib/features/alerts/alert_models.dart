import '../haccp/pest/pest_models.dart';
import '../haccp/temperatures/temperature_models.dart';
import '../safety/incidents/incident_models.dart';
import '../safety/people/people_models.dart';

enum AlertSeverity { critical, warning, info }

class AppAlert {
  const AppAlert({
    required this.severity,
    required this.title,
    required this.detail,
    required this.route,
  });
  final AlertSeverity severity;
  final String title;
  final String detail;
  final String route;
}

/// Orizzonte (giorni) entro cui una scadenza diventa un avviso.
const alertHorizonDays = 30;

String _when(int daysLeft) {
  if (daysLeft < 0) return 'scaduto da ${-daysLeft} gg';
  if (daysLeft == 0) return 'scade oggi';
  return 'scade tra $daysLeft gg';
}

String _routeForDeadline(String kind) => switch (kind) {
      'dvr_review' || 'dvr_action' || 'safety_officer' => '/dvr',
      'contractor_doc' => '/duvri',
      _ => '/persone',
    };

/// Funzione pura: unisce tutte le fonti in un'unica lista ordinata per gravita'.
List<AppAlert> buildAlerts({
  required DateTime today,
  TempOverview? temps,
  PestData? pest,
  PeopleData? people,
  IncidentData? incidents,
}) {
  final out = <AppAlert>[];

  if (temps != null && temps.totalOpenDeviations > 0) {
    final n = temps.totalOpenDeviations;
    out.add(AppAlert(
      severity: AlertSeverity.critical,
      title: 'Temperature fuori limite',
      detail: '$n scostament${n == 1 ? 'o' : 'i'} senza azione correttiva',
      route: '/temperature',
    ));
  }

  if (incidents != null && incidents.inailPending > 0) {
    final n = incidents.inailPending;
    out.add(AppAlert(
      severity: AlertSeverity.critical,
      title: 'Denuncia INAIL da registrare',
      detail: '$n event${n == 1 ? 'o' : 'i'} con obbligo di denuncia',
      route: '/eventi',
    ));
  }

  if (pest != null) {
    final f = pest.openFindings.length;
    if (f > 0) {
      out.add(AppAlert(
        severity: AlertSeverity.critical,
        title: 'Infestanti: azioni aperte',
        detail: '$f segnalazion${f == 1 ? 'e' : 'i'} da gestire',
        route: '/infestanti',
      ));
    }
    if (pest.overdueCount > 0) {
      out.add(AppAlert(
        severity: AlertSeverity.warning,
        title: 'Ispezioni infestanti in ritardo',
        detail: '${pest.overdueCount} postazion${pest.overdueCount == 1 ? 'e' : 'i'} da controllare',
        route: '/infestanti',
      ));
    }
  }

  if (people != null) {
    for (final d in people.deadlinesWithin(today, alertHorizonDays)) {
      final left = d.daysLeft(today);
      out.add(AppAlert(
        severity: left < 0
            ? AlertSeverity.critical
            : (left <= 7 ? AlertSeverity.warning : AlertSeverity.info),
        title: '${d.kindLabel}: ${d.label}',
        detail: _when(left),
        route: _routeForDeadline(d.kind),
      ));
    }
  }

  if (incidents != null) {
    final open = incidents.stats(today).open;
    if (open > 0) {
      out.add(AppAlert(
        severity: AlertSeverity.info,
        title: 'Eventi da chiudere',
        detail: '$open event${open == 1 ? 'o' : 'i'} aperti',
        route: '/eventi',
      ));
    }
  }

  // Ordinamento stabile per gravita' (l'ordine di inserimento resta dentro lo stesso livello).
  final indexed = out.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.severity.index.compareTo(b.value.severity.index);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}
