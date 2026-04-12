import 'package:flutter_web_plugins/url_strategy.dart';

/// 웹에서 `#/경로` 대신 `/경로`를 쓰면 OAuth(PKCE) 복귀 URL의 `?code=`가 안정적으로 처리됩니다.
void configureAppUrlStrategy() {
  usePathUrlStrategy();
}
