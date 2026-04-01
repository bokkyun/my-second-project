import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 인증 상태가 바뀔 때마다 GoRouter의 redirect를 다시 평가하도록 합니다.
/// (로그인 직후 세션이 반영되기 전에 /calendar로 가면 다시 /login으로 튕기는 문제 방지)
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
