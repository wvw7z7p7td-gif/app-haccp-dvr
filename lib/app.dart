import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HACCP & Sicurezza',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: brightness,
      ),
      // Target di tocco ampi: si usa anche con i guanti.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
