import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty,
      'Passare SUPABASE_URL e SUPABASE_ANON_KEY con --dart-define');
  await initializeDateFormatting('it_IT');
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  runApp(const ProviderScope(child: App()));
}
