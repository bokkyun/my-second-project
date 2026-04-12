import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bootstrap/url_strategy_stub.dart'
    if (dart.library.html) 'bootstrap/url_strategy_web.dart' as url_strategy;
import 'router.dart' show appRouter, setupAppRouter;
import 'services/notification_service.dart';
import 'services/push_messaging_service.dart';
import 'services/widget_sync_service.dart';

/// Supabase 프로젝트 참조 (대시보드 URL에 사용)
/// [Authentication → Providers](https://supabase.com/dashboard/project/qrucuqdehrdqgsunfwfd/auth/providers)
/// 에서 Email / Google 등 공급자를 켜고 Client ID·Secret을 넣습니다.
const String kSupabaseProjectRef = 'qrucuqdehrdqgsunfwfd';

/// 빌드 시 `--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...` 로 덮어쓸 수 있습니다.
const String _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://$kSupabaseProjectRef.supabase.co',
);
const String _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFydWN1cWRlaHJkcWdzdW5md2ZkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MTAxMzEsImV4cCI6MjA5MDE4NjEzMX0.tfu9Q3Ij9PD1bZx34ahmr-XraaQibPRXUSlsTkHG67k',
);

/// **실험 (2026-04-06):** 시스템 홈/내비와 겹침 완화 — 전체 UI를 약 1cm(48 logical px) 위로 올리고 아래는 [surface] 색 빈 줄.
/// **원상복구:** `_TeamSyncAppState.build` 안 `MaterialApp.router`의 `builder`를 제거하고, 이 상수도 삭제하면 됩니다.
const double _kExperimentalBottomLiftForSystemNav = 48;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.configureAppUrlStrategy();
  await initializeDateFormatting('ko_KR');
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('NotificationService 초기화 오류(무시): $e');
  }
  // 커스텀 HttpClient(IOClient)는 일부 기기에서 DNS/연결과 맞지 않을 수 있어 SDK 기본 클라이언트 사용
  var supabaseInitialized = false;
  try {
    await Supabase.initialize(
      url: _kSupabaseUrl,
      anonKey: _kSupabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // OAuth(Google 등) 복귀 URL의 세션(code/fragment)을 웹에서 인식
        detectSessionInUri: true,
        autoRefreshToken: true,
      ),
    ).timeout(const Duration(seconds: 10));
    supabaseInitialized = true;
  } catch (e) {
    debugPrint('Supabase 초기화 타임아웃 또는 오류 - 오프라인 모드로 진행: $e');
  }
  // Google OAuth(PKCE) 복귀 시 `?code=`가 있어도 세션이 비어 있으면 한 번 더 복구 (해시 URL 환경 대비)
  if (kIsWeb && supabaseInitialized) {
    try {
      final u = Uri.base;
      if (u.queryParameters.containsKey('code') &&
          Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.getSessionFromUrl(u);
      }
    } catch (e) {
      debugPrint('OAuth 세션 복구 재시도: $e');
    }
  }
  setupAppRouter();
  NotificationService.attachRouter(appRouter);
  await PushMessagingService.init(appRouter);
  try {
    await NotificationService.scheduleDailySummaryFromPrefs([]);
  } catch (e) {
    debugPrint('scheduleDailySummaryFromPrefs 오류(무시): $e');
  }
  try {
    await NotificationService.handleNotificationAppLaunch();
  } catch (e) {
    debugPrint('handleNotificationAppLaunch 오류(무시): $e');
  }
  try {
    await WidgetSyncService.syncSubwayOnly();
  } catch (e) {
    debugPrint('Widget 지하철 동기화 오류(무시): $e');
  }
  runApp(const TeamSyncApp());
}

class TeamSyncApp extends StatefulWidget {
  const TeamSyncApp({super.key});

  @override
  State<TeamSyncApp> createState() => _TeamSyncAppState();
}

class _TeamSyncAppState extends State<TeamSyncApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.rescheduleDailySummaryAfterAppResume();
      WidgetSyncService.syncSubwayOnly();
    }
  }

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
      builder: (context, child) {
        final c = child;
        if (c == null) return const SizedBox.shrink();
        final stripColor = Theme.of(context).colorScheme.surface;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: c),
            ColoredBox(
              color: stripColor,
              child: SizedBox(height: _kExperimentalBottomLiftForSystemNav),
            ),
          ],
        );
      },
    );
  }
}
