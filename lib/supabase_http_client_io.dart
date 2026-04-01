import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 모바일/데스크톱: TCP 연결 대기 시간 제한 (끝없이 몇 분 대기하는 현상 완화)
http.Client? createSupabaseHttpClient() {
  final inner = HttpClient();
  inner.connectionTimeout = const Duration(seconds: 20);
  return IOClient(inner);
}
