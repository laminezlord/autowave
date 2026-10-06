import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'data/backend.dart';
import 'data/demo/demo_backend.dart';
import 'data/supabase/supabase_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fixed locale for money and dates, so unusual device locales can't break formatting.
  await initializeDateFormatting('en_NG');
  Intl.defaultLocale = 'en_NG';
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (Env.demo) {
    backend = DemoBackend();
  } else {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
    backend = SupabaseBackend();
  }
  runApp(const AutoWaveApp());
}
