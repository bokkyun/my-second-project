import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart' show appRouter, setupAppRouter;
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  await NotificationService.initialize();
  await Supabase.initialize(
    url: 'https://qrucuqdehrdqgsunfwfd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFydWN1cWRlaHJkcWdzdW5md2ZkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MTAxMzEsImV4cCI6MjA5MDE4NjEzMX0.tfu9Q3Ij9PD1bZx34ahmr-XraaQibPRXUSlsTkHG67k',
  );
  setupAppRouter();
  runApp(const TeamSyncApp());
}

class TeamSyncApp extends StatelessWidget {
  const TeamSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TeamSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1976D2),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
