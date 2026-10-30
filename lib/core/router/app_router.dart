import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/haccp/cleaning/cleaning_page.dart';
import '../../features/haccp/menu/menu_page.dart';
import '../../features/haccp/pest/pest_page.dart';
import '../../features/haccp/receiving/receiving_page.dart';
import '../../features/haccp/temperatures/temperature_page.dart';
import '../../features/home/today_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/safety/safety_page.dart';
import '../../features/settings/settings_page.dart';
import '../auth/providers.dart';
import '../layout/adaptive_shell.dart';
import 'destinations.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.listen(activeMembershipProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/oggi',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/oggi';

      // Guardia di ruolo (la sicurezza vera resta nelle policy RLS del DB).
      final membership = ref.read(activeMembershipProvider);
      final dest = destinationForPath(state.matchedLocation);
      if (membership != null && dest != null && !dest.roles.contains(membership.role)) {
        return '/oggi';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/infestanti', builder: (_, __) => const PestPage()),
      GoRoute(path: '/menu', builder: (_, __) => const MenuPage()),
      GoRoute(path: '/impostazioni', builder: (_, __) => const SettingsPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/oggi', builder: (_, __) => const TodayPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/temperature', builder: (_, __) => const TemperaturePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/pulizie', builder: (_, __) => const CleaningPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/merci', builder: (_, __) => const ReceivingPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/sicurezza', builder: (_, __) => const SafetyPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/report', builder: (_, __) => const ReportsPage()),
          ]),
        ],
      ),
    ],
  );
});
