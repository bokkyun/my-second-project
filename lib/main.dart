import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart' show appRouter, setupAppRouter;
import 'services/notification_service.dart';
import 'services/push_messaging_service.dart';

/// 빌드 시 `--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...` 로 덮어쓸 수 있습니다.
const String _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qrucuqdehrdqgsunfwfd.supabase.co',
);
const String _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFydWN1cWRlaHJkcWdzdW5md2ZkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MTAxMzEsImV4cCI6MjA5MDE4NjEzMX0.tfu9Q3Ij9PD1bZx34ahmr-XraaQibPRXUSlsTkHG67k',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  await NotificationService.initialize();
  // 커스텀 HttpClient(IOClient)는 일부 기기에서 DNS/연결과 맞지 않을 수 있어 SDK 기본 클라이언트 사용
  await Supabase.initialize(
    url: _kSupabaseUrl,
    anonKey: _kSupabaseAnonKey,
  );
  setupAppRouter();
  NotificationService.attachRouter(appRouter);
  await PushMessagingService.init(appRouter);
  await NotificationService.scheduleDailySummaryFromPrefs([]);
  await NotificationService.handleNotificationAppLaunch();
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
