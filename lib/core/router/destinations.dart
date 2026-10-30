import 'package:flutter/material.dart';

import '../models/app_role.dart';

class AppDestination {
  const AppDestination({
    required this.path,
    required this.branchIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.roles,
  });

  final String path;
  final int branchIndex; // posizione del branch in StatefulShellRoute
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Set<AppRole> roles;
}

const _all = {AppRole.admin, AppRole.employee, AppRole.consultant};

/// Ordine = ordine dei branch in app_router.dart.
const kDestinations = <AppDestination>[
  AppDestination(
    path: '/oggi', branchIndex: 0, label: 'Oggi',
    icon: Icons.today_outlined, selectedIcon: Icons.today, roles: _all,
  ),
  AppDestination(
    path: '/temperature', branchIndex: 1, label: 'Temperature',
    icon: Icons.thermostat_outlined, selectedIcon: Icons.thermostat, roles: _all,
  ),
  AppDestination(
    path: '/pulizie', branchIndex: 2, label: 'Pulizie',
    icon: Icons.cleaning_services_outlined, selectedIcon: Icons.cleaning_services, roles: _all,
  ),
  AppDestination(
    path: '/sicurezza', branchIndex: 3, label: 'Sicurezza',
    icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety, roles: _all,
  ),
  AppDestination(
    path: '/report', branchIndex: 4, label: 'Report',
    icon: Icons.description_outlined, selectedIcon: Icons.description,
    roles: {AppRole.admin, AppRole.consultant},
  ),
];

AppDestination? destinationForPath(String location) {
  for (final d in kDestinations) {
    if (location == d.path || location.startsWith('${d.path}/')) return d;
  }
  return null;
}
