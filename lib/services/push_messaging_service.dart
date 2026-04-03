import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

/// Firebase + FCM (google-services.json / Firebase 설정 후 동작)
class PushMessagingService {
  PushMessagingService._();

  static GoRouter? _router;
  static bool _inited = false;

  static Future<void> init(GoRouter router) async {
    if (_inited) return;
    _router = router;

    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      debugPrint('Firebase 초기화 생략(설정 파일 없음): $e\n$st');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM 알림 권한 거부');
    }

    await _syncTokenToProfile(await messaging.getToken());

    FirebaseMessaging.instance.onTokenRefresh.listen(_syncTokenToProfile);

    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      final n = m.notification;
      final eventId = m.data['event_id'] as String?;
      if (n != null && eventId != null) {
        NotificationService.showGroupEventLocalNotification(
          title: n.title ?? '그룹 일정',
          body: n.body ?? '',
          eventId: eventId,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final eventId = m.data['event_id'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        _router?.go('/calendar?eventId=$eventId');
      }
    });

    final initial = await messaging.getInitialMessage();
    final initialId = initial?.data['event_id'] as String?;
    if (initialId != null && initialId.isNotEmpty) {
      Future<void>.delayed(Duration.zero, () {
        _router?.go('/calendar?eventId=$initialId');
      });
    }

    _inited = true;
  }

  static Future<void> _syncTokenToProfile(String? token) async {
    if (token == null || token.isEmpty) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', uid);
    } catch (e) {
      debugPrint('fcm_token 저장 실패: $e');
    }
  }

  /// 로그아웃 시 토큰 제거(다른 기기·재로그인 시 혼선 방지)
  static Future<void> clearTokenForLogout() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null})
          .eq('id', uid);
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
