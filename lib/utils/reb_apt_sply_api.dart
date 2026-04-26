// 한국부동산원 청약홈 분양정보(공공데이터) — data.go.kr
//
// 키·경로는 빌드 시 --dart-define 으로 넣습니다(웹 my-first의 VITE_* 와 대응).
//   --dart-define=DATA_GO_KR_SERVICE_KEY=인증키
//   --dart-define=REB_APT_SPLY_PATH=/1613000/AptBasisOflsInfoService/getAptBasisOflsList
//   --dart-define=REB_APT_PAGE_SIZE=200
//   --dart-define=REB_APT_DATA_GO_ORIGIN=https://apis.data.go.kr
// Flutter Web에서 CORS로 막히면, 동일출처 API 프록시 origin 을 REB_APT_DATA_GO_ORIGIN에 두세요.
//
// @see https://www.data.go.kr

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/event.dart';

String? _parseYmdToIsoStart(dynamic v) {
  if (v == null) return null;
  final s = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (s.length >= 8) {
    return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}T00:00:00';
  }
  if (s.length == 6) {
    return '${s.substring(0, 4)}-${s.substring(4, 6)}-01T00:00:00';
  }
  return null;
}

String? _parseYmdToIsoEndOfDay(dynamic v) {
  final start = _parseYmdToIsoStart(v);
  if (start == null) return null;
  final d = DateTime.parse(start);
  final end = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  return end.toIso8601String();
}

class RebAptSplyConfig {
  RebAptSplyConfig._();

  static const String dataGoServiceKey = String.fromEnvironment('DATA_GO_KR_SERVICE_KEY');
  static const String splyPath = String.fromEnvironment(
    'REB_APT_SPLY_PATH',
    defaultValue: '/1613000/AptBasisOflsInfoService/getAptBasisOflsList',
  );
  static const String pageSize = String.fromEnvironment('REB_APT_PAGE_SIZE', defaultValue: '200');
  static const String dataGoOrigin = String.fromEnvironment(
    'REB_APT_DATA_GO_ORIGIN',
    defaultValue: 'https://apis.data.go.kr',
  );
}

RebAptSplyUrlParts buildRebAptSplyListUrl() {
  final key = RebAptSplyConfig.dataGoServiceKey.trim();
  final serviceKey = key.isNotEmpty ? 'serviceKey=${Uri.encodeQueryComponent(key)}' : '';
  const pageNo = 'pageNo=1';
  final num = 'numOfRows=${RebAptSplyConfig.pageSize}';
  const type = 'resultType=json';
  final path = RebAptSplyConfig.splyPath.replaceFirst(RegExp(r'^\s+'), '');
  final q = [serviceKey, pageNo, num, type].where((e) => e.isNotEmpty).join('&');
  return RebAptSplyUrlParts(path: path, query: q, keyPresent: key.isNotEmpty);
}

class RebAptSplyUrlParts {
  const RebAptSplyUrlParts({
    required this.path,
    required this.query,
    required this.keyPresent,
  });
  final String path;
  final String query;
  final bool keyPresent;
}

String toDataGoAbsoluteUrl(String path, [String? query]) {
  final p = path.startsWith('/') ? path : '/$path';
  var origin = RebAptSplyConfig.dataGoOrigin.replaceAll(RegExp(r'/$'), '');
  if (origin.isEmpty) origin = 'https://apis.data.go.kr';
  final q = (query == null || query.isEmpty) ? '' : (query.startsWith('?') ? query : '?$query');
  return '$origin$p$q';
}

/// data.go.kr 표준 response.header / body
({List<Map<String, dynamic>> items, String? error}) parseRebAptSplyResponse(dynamic json) {
  if (json is! Map) {
    return (items: <Map<String, dynamic>>[], error: '빈 응답입니다.');
  }
  final res = json['response'] as Map<String, dynamic>?;
  if (res == null) {
    return (items: <Map<String, dynamic>>[], error: '응답 형식이 예상과 다릅니다.');
  }
  final header = res['header'] as Map<String, dynamic>?;
  if (header != null) {
    final code = '${header['resultCode'] ?? header['resultcode'] ?? ''}';
    if (code.isNotEmpty && code != '00' && code != '0') {
      return (
        items: <Map<String, dynamic>>[],
        error: (header['resultMsg'] ?? header['resultMessage'] ?? 'API 오류 ($code)').toString(),
      );
    }
  }
  final body = res['body'];
  if (body is! Map<String, dynamic>) {
    return (items: <Map<String, dynamic>>[], error: null);
  }
  final items = body['items'];
  if (items == null) {
    return (items: <Map<String, dynamic>>[], error: null);
  }
  if (items is List) {
    return (
      items: items.whereType<Map<String, dynamic>>().toList(),
      error: null,
    );
  }
  if (items is Map<String, dynamic>) {
    final item = items['item'];
    if (item == null) {
      return (items: <Map<String, dynamic>>[], error: null);
    }
    if (item is List) {
      return (items: item.whereType<Map<String, dynamic>>().toList(), error: null);
    }
    if (item is Map<String, dynamic>) {
      return (items: <Map<String, dynamic>>[item], error: null);
    }
  }
  return (items: <Map<String, dynamic>>[], error: null);
}

CalendarEvent? mapSplyItemToCalendarEvent(Map<String, dynamic> item, int index) {
  final titleBase = item['aptNm'] ??
      item['hmsApt'] ??
      item['houseNm'] ??
      item['pblancNm'] ??
      item['bildNm'] ??
      item['aptDong'] ??
      '아파트 분양';
  final pbl = (item['pblancNo'] != null || item['rceptMth'] != null)
      ? ' (${[item['pblancNo'], item['rceptMth']].where((e) => e != null).join(' / ')})'
      : '';
  final startYmd = item['rceptBgnde'] ??
      item['receptStrtDttm'] ??
      item['rcptStrtDttm'] ??
      item['pblancDttm'] ??
      item['pblancDay'] ??
      item['pblancDt'] ??
      item['rceptMth'];
  final endYmd = item['rceptEndde'] ?? item['receptDttm'] ?? item['rceptEndde'] ?? startYmd;
  final starts = _parseYmdToIsoStart(startYmd);
  if (starts == null) return null;
  final ends = _parseYmdToIsoEndOfDay(endYmd) ?? _parseYmdToIsoEndOfDay(startYmd) ?? starts;
  final idRaw = item['pblancNo'] ?? item['aptSeq'] ?? item['rceptMth'] ?? index;
  final id = 'reb-apt-${idRaw.toString().replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_')}';
  return CalendarEvent(
    id: id,
    title: '🏢 ${titleBase.toString().trim()}$pbl',
    description: '한국부동산원 청약홈 공공데이터(apis.data.go.kr)에서 제공됩니다. 수정/삭제할 수 없습니다.',
    startsAt: DateTime.parse(starts).toLocal(),
    endsAt: DateTime.parse(ends).toLocal(),
    isAllDay: true,
    color: '#0d47a1',
    creatorId: CalendarEvent.kExternalCreatorId,
    creatorNickname: '청약홈(부동산원)',
    groupIds: const [],
    eventKind: 'default',
    externalSource: 'reb-apt',
  );
}

/// 네이티브·앱: 직접 data.go 호출. (웹은 CORS로 실패할 수 있음)
Future<({List<CalendarEvent> events, String? error})> fetchRebAptSplyList() async {
  final built = buildRebAptSplyListUrl();
  if (!built.keyPresent) {
    return (events: <CalendarEvent>[], error: 'DATA_GO_KR_SERVICE_KEY가 없습니다. --dart-define으로 설정하세요.');
  }
  if (built.path.isEmpty) {
    return (events: <CalendarEvent>[], error: 'REB_APT_SPLY_PATH를 확인하세요.');
  }
  final url = toDataGoAbsoluteUrl(built.path, built.query);
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return (events: <CalendarEvent>[], error: 'HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    final parsed = parseRebAptSplyResponse(json);
    if (parsed.error != null) {
      return (events: <CalendarEvent>[], error: parsed.error);
    }
    final out = <CalendarEvent>[];
    for (var i = 0; i < parsed.items.length; i++) {
      final ev = mapSplyItemToCalendarEvent(parsed.items[i], i);
      if (ev != null) out.add(ev);
    }
    return (events: out, error: null);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('cors') || msg.contains('xmlhttp') || msg.contains('clientexception')) {
      return (
        events: <CalendarEvent>[],
        error: 'CORS/네트워크: Flutter Web은 data.go.kr 직접 호출이 막힐 수 있습니다. '
            'REB_APT_DATA_GO_ORIGIN에 동일출처 프록시를 쓰거나, Android/iOS 앱에서 사용하세요.',
      );
    }
    return (events: <CalendarEvent>[], error: e.toString());
  }
}
