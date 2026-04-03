import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/storage/local_storage.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Indonesian locale data used by DateFormat throughout the app.
  // Must run before any widget that formats dates with 'id_ID'.
  await initializeDateFormatting('id_ID');

  // Lock to portrait orientation (mobile-first UX).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // SharedPreferences must be ready before any provider reads it.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // Inject the initialized SharedPreferences instance.
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CatatApp(),
    ),
  );
}

class CatatApp extends ConsumerWidget {
  const CatatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Catat App',
      theme: AppTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,

      // ── Localization ────────────────────────────────────────────────────────
      // Required for Material widgets (date pickers, button labels, etc.) to
      // render correctly in Indonesian. Also needed by table_calendar.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('id', 'ID'),
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
    );
  }
}
