import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/subway_display_row.dart';

/// 공공데이터포털 「서울교통공사 열차시간표」 API (B553766 / getTrainSch)
/// 실시간 도착 API(swopenapi)와 별도의 인증키(serviceKey)를 사용합니다.
class SubwayScheduleService {
  SubwayScheduleService._();

  static const _base =
      'https://apis.data.go.kr/B553766/schedule/getTrainSch';
  static const _webProxyPrefixes = <String>[
    'https://corsproxy.io/?',
    'https://api.allorigins.win/raw?url=',
  ];

  /// 6964456e7862636836347177675945 → ASCII (로컬 테스트용). 스토어 배포 시
  /// 공공데이터포털에서 발급한 serviceKey를 --dart-define=SUBWAY_SCHEDULE_SERVICE_KEY= 로 넣을 것.
  static String _hexDecodedDefaultKey() {
    const hex = '6964456e7862636836347177675945';
    final b = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      b.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return String.fromCharCodes(b);
  }

  static String get _serviceKey {
    const fromEnv = String.fromEnvironment('SUBWAY_SCHEDULE_SERVICE_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return _hexDecodedDefaultKey();
  }

  /// 공공데이터 명세 예시에 흔한 **한글** 값 (평일 / 토요일 / 일요일)
  static String wkndSeKoreanNow() {
    _ensureTz();
    final wd = tz.TZDateTime.now(_seoul).weekday;
    if (wd == DateTime.saturday) return '토요일';
    if (wd == DateTime.sunday) return '일요일';
    return '평일';
  }

  /// 일부 문서/샘플에서 쓰는 숫자 코드 (평일=8, 토요일=9, 일요일=0)
  static String wkndSeCodeNow() {
    _ensureTz();
    final wd = tz.TZDateTime.now(_seoul).weekday;
    if (wd == DateTime.saturday) return '9';
    if (wd == DateTime.sunday) return '0';
    return '8';
  }

  static bool _tzReady = false;

  static void _ensureTz() {
    if (_tzReady) return;
    tz_data.initializeTimeZones();
    _tzReady = true;
  }

  static tz.Location get _seoul => tz.getLocation('Asia/Seoul');

  /// 서울 기준 현재 시각 (시간표·다음 열차 계산용)
  static tz.TZDateTime nowSeoul() {
    _ensureTz();
    return tz.TZDateTime.now(_seoul);
  }

  /// [wkndSeKoreanNow] (호환용 이름)
  static String wkndSeNow() => wkndSeKoreanNow();

  /// 명세: 1=상행·내선, 2=하행·외선 (2호선도 동일 코드로 조회하는 경우가 많음)
  static const List<String> upbdnbQueryValues = ['1', '2'];

  /// 라인명 정규화 (설정값/표기 흔들림 -> API 기대값)
  static String normalizeLineName(String lineName) {
    final raw = lineName.trim();
    if (raw.isEmpty) return raw;
    if (raw == '중앙선') return '경의중앙선';
    if (raw == 'GTX') return 'GTX-A';
    return raw;
  }

  /// 역명 정규화 후보 생성.
  /// - 원문
  /// - '역' 접미사 제거/추가 (예: 흑석역 <-> 흑석)
  /// - 괄호 제거본 (예: 총신대입구(이수) -> 총신대입구)
  /// - 괄호 내부본 (예: 총신대입구(이수) -> 이수)
  static List<String> stationNameCandidates(String stationName) {
    final raw = stationName.trim();
    if (raw.isEmpty) return const [];
    final out = <String>[raw];
    if (raw.endsWith('역') && raw.length > 1) {
      final noSuffix = raw.substring(0, raw.length - 1).trim();
      if (noSuffix.isNotEmpty && !out.contains(noSuffix)) out.add(noSuffix);
    } else {
      final withSuffix = '$raw역';
      if (!out.contains(withSuffix)) out.add(withSuffix);
    }
    final reg = RegExp(r'^(.+?)\((.+)\)$');
    final m = reg.firstMatch(raw);
    if (m != null) {
      final outer = (m.group(1) ?? '').trim();
      final inner = (m.group(2) ?? '').trim();
      if (outer.isNotEmpty && !out.contains(outer)) out.add(outer);
      if (inner.isNotEmpty && !out.contains(inner)) out.add(inner);
    }
    return out;
  }

  /// 한 방향·한 페이지 조회 후 item 맵 목록
  static Future<List<Map<String, dynamic>>> fetchItemsPage({
    required String lineNm,
    required String stnNm,
    required String upbdnbSe,
    required String wkndSe,
    required int pageNo,
  }) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: <String, String>{
        'serviceKey': _serviceKey,
        'numOfRows': '1000',
        'pageNo': '$pageNo',
        'lineNm': lineNm.trim(),
        'stnNm': stnNm.trim(),
        'upbdnbSe': upbdnbSe,
        'wkndSe': wkndSe,
        'tmprTmtblYn': 'N',
        'type': 'json',
        '_type': 'json',
      },
    );
    http.Response? res;
    try {
      res = await _getWithWebFallback(uri);
      if (kDebugMode) {
        debugPrint('=== API 응답 전체 ===');
        debugPrint(
          '[getTrainSch] status=${res?.statusCode} '
          'line=$lineNm stn=$stnNm upbdnbSe=$upbdnbSe wkndSe=$wkndSe page=$pageNo',
        );
        if (res != null) {
          final body = res.body;
          if (body.length <= 1500) {
            debugPrint(body);
          } else {
            debugPrint('${body.substring(0, 1500)} ...');
          }
        } else {
          debugPrint('[getTrainSch] response is null');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('=== API 오류 ===');
        debugPrint(e.toString());
      }
      return const [];
    }
    if (res == null || res.statusCode != 200) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];

    final response = decoded['response'];
    if (response is! Map<String, dynamic>) {
      if (kDebugMode) {
        debugPrint('[getTrainSch] response 루트 형식 오류');
      }
      return const [];
    }

    final header = response['header'];
    if (header is Map) {
      final code = header['resultCode']?.toString().trim() ?? '';
      final msg = header['resultMsg']?.toString();
      if (kDebugMode) {
        debugPrint(
          '[getTrainSch] resultCode=$code resultMsg=$msg '
          'line=$lineNm stn=$stnNm upbdnbSe=$upbdnbSe wkndSe=$wkndSe page=$pageNo',
        );
      }
      // 일부 응답은 숫자 0 / 문자열 "0" 도 성공으로 옴
      if (code.isNotEmpty && code != '00' && code != '0') {
        return const [];
      }
    }

    final body = response['body'];
    if (body is! Map<String, dynamic>) return const [];

    return _unwrapItems(body['items']);
  }

  static Future<http.Response?> _getWithWebFallback(Uri uri) async {
    try {
      return await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!kIsWeb) return null;
    }
    if (!kIsWeb) return null;

    for (final prefix in _webProxyPrefixes) {
      try {
        final proxied = Uri.parse('$prefix${Uri.encodeComponent(uri.toString())}');
        final res = await http.get(proxied).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[getTrainSch] 웹 프록시 사용: $prefix');
          }
          return res;
        }
      } catch (_) {}
    }
    return null;
  }

  static List<Map<String, dynamic>> _unwrapItems(dynamic items) {
    if (items == null) return const [];
    // items 가 빈 문자열 등으로 오는 경우
    if (items is String) return const [];
    if (items is! Map) return const [];
    final raw = items['item'];
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (raw is Map) {
      return [raw.cast<String, dynamic>()];
    }
    return const [];
  }

  /// 모든 페이지·방향을 합쳐 역의 시간표 행 수집.
  /// 먼저 **한글 wkndSe**로 시도하고, 결과가 없으면 **숫자 코드(8/9/0)** 로 한 번 더 시도.
  static Future<List<Map<String, dynamic>>> fetchAllForStation({
    required String lineNm,
    required String stnNm,
    String? wkndSe,
  }) async {
    final normalizedLine = normalizeLineName(lineNm);
    final stationCands = stationNameCandidates(stnNm);
    if (stationCands.isEmpty) return const [];

    final primary = wkndSe ?? wkndSeKoreanNow();
    final wkndCands = <String>[primary];
    if (wkndSe == null) {
      final fallback = wkndSeCodeNow();
      if (fallback != primary) wkndCands.add(fallback);
    }

    // 가능한 조합을 모두 순차 시도하고, 첫 성공 결과를 반환
    for (final stn in stationCands) {
      for (final wk in wkndCands) {
        final out = await _fetchAllForStationWithWknd(
          lineNm: normalizedLine,
          stnNm: stn,
          wknd: wk,
        );
        if (out.isNotEmpty) {
          if (kDebugMode && (stn != stnNm || normalizedLine != lineNm || wk != primary)) {
            debugPrint(
              '[getTrainSch] 정규화 성공 line: $lineNm->$normalizedLine, '
              'stn: $stnNm->$stn, wkndSe: $primary->$wk',
            );
          }
          return out;
        }
      }
    }
    return const [];
  }

  static Future<List<Map<String, dynamic>>> _fetchAllForStationWithWknd({
    required String lineNm,
    required String stnNm,
    required String wknd,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final d in upbdnbQueryValues) {
      var page = 1;
      while (true) {
        final batch = await fetchItemsPage(
          lineNm: lineNm,
          stnNm: stnNm,
          upbdnbSe: d,
          wkndSe: wknd,
          pageNo: page,
        );
        if (batch.isEmpty) break;
        for (final m in batch) {
          out.add({...m, '_queryUpbdnbSe': d});
        }
        if (batch.length < 1000) break;
        page++;
      }
    }
    return out;
  }

  /// 맵에서 종착역/방향 표시용 문자열 추출
  static String terminalFromItem(Map<String, dynamic> m) {
    for (final k in [
      'trainDstnNm',
      'dstnNm',
      'subwayDstnNm',
      'trainDestNm',
      'trainLineNm',
    ]) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final reg = RegExp(r'([가-힣A-Za-z0-9]+행)');
      final hit = reg.firstMatch(s);
      if (hit != null) return hit.group(1) ?? s;
      if (s.length <= 20) return s;
      return '${s.substring(0, 17)}…';
    }
    final no = m['trainNo'] ?? m['trainCycl'] ?? '';
    if (no.toString().trim().isNotEmpty) return '열차 ${no.toString().trim()}';
    return '—';
  }

  static String updnFromItem(Map<String, dynamic> m) {
    for (final k in ['upbdnbSe', 'updnLine', 'updLine', 'subwayDir']) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    final q = m['_queryUpbdnbSe'];
    if (q != null) return q.toString().trim();
    return '';
  }

  /// 항목에서 해당 역 시각 파싱 (오늘 날짜 기준). 응답이 "0802" 형태 4자리면 dptTm/arvlTm 순으로 시도.
  static tz.TZDateTime? arrivalAtStation(Map<String, dynamic> m) {
    _ensureTz();
    final base = tz.TZDateTime.now(_seoul);
    for (final k in [
      'dptTm',
      'arvlTm',
      'dpt_tm',
      'arvl_tm',
      'arrivalTm',
      'departureTm',
      'arvlTime',
      'arrivalTime',
      'leftTime',
    ]) {
      final parsed = _parseTimeToSeoul(m[k], base);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static tz.TZDateTime? _parseTimeToSeoul(dynamic v, tz.TZDateTime baseDay) {
    if (v == null) return null;
    // JSON에서 정수(802, 0802, 123456)로 오는 경우
    if (v is int) {
      final str = v.toString();
      if (str.length == 6) {
        return _parseTimeToSeoul(str, baseDay);
      }
      if (str.length <= 4) {
        return _parseTimeToSeoul(str.padLeft(4, '0'), baseDay);
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final p1 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
    if (p1 != null) {
      final h = int.parse(p1.group(1)!);
      final min = int.parse(p1.group(2)!);
      final sec = int.tryParse(p1.group(3) ?? '0') ?? 0;
      return tz.TZDateTime(
        _seoul,
        baseDay.year,
        baseDay.month,
        baseDay.day,
        h,
        min,
        sec,
      );
    }

    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6) {
      final h = int.parse(digits.substring(0, 2));
      final min = int.parse(digits.substring(2, 4));
      final sec = int.parse(digits.substring(4, 6));
      return tz.TZDateTime(
        _seoul,
        baseDay.year,
        baseDay.month,
        baseDay.day,
        h,
        min,
        sec,
      );
    }
    if (digits.length == 4) {
      final h = int.parse(digits.substring(0, 2));
      final min = int.parse(digits.substring(2, 4));
      return tz.TZDateTime(
        _seoul,
        baseDay.year,
        baseDay.month,
        baseDay.day,
        h,
        min,
        0,
      );
    }
    return null;
  }

  /// 스케줄 기준 표시 문자열 (다음 열차 시각 + 남은 시간)
  static String formatEta(tz.TZDateTime train, tz.TZDateTime now) {
    final hh = train.hour.toString().padLeft(2, '0');
    final mm = train.minute.toString().padLeft(2, '0');
    final clock = '$hh:$mm';
    final diff = train.difference(now);
    if (diff.inSeconds < 90) return '곧 도착 ($clock)';
    final mins = diff.inMinutes.clamp(1, 999);
    return '약 $mins분 후 ($clock)';
  }

  static SubwayTrackKind kindFromUpdn(String updn, [String lineName = '']) {
    final u = updn.trim();
    final l = lineName.trim();
    if (l.contains('2호선')) {
      if (u == '1' || u.contains('내선')) return SubwayTrackKind.up;
      if (u == '2' || u.contains('외선')) return SubwayTrackKind.down;
    }
    if (u == '1' || u.contains('상행') || u.contains('내선')) {
      return SubwayTrackKind.up;
    }
    if (u == '2' || u.contains('하행') || u.contains('외선')) {
      return SubwayTrackKind.down;
    }
    return SubwayTrackKind.other;
  }

  /// API 코드·한글 방향을 짧은 궤도 라벨로 (캘린더 패널용).
  /// 2호선: 1→내선, 2→외선 / 그 외: 1→상행, 2→하행
  static String shortTrackLabelForQuery(String updn, [String lineName = '']) {
    final u = updn.trim();
    final l = lineName.trim();
    if (l.contains('2호선')) {
      switch (u) {
        case '1':
          return '내선';
        case '2':
          return '외선';
      }
    }
    switch (u) {
      case '1':
        return '상행';
      case '2':
        return '하행';
      case '3':
        return '내선';
      case '4':
        return '외선';
    }
    if (u.contains('상행')) return '상행';
    if (u.contains('하행')) return '하행';
    if (u.contains('내선')) return '내선';
    if (u.contains('외선')) return '외선';
    if (u.isNotEmpty) {
      return u.length > 2 ? u.substring(0, 2) : u;
    }
    return '';
  }
}
