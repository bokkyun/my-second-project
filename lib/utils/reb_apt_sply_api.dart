// 한국부동산원 청약홈 분양정보(공공데이터)
// - datago: apis.data.go.kr
// - odcloud: api.odcloud.kr (v1/uddi:…, data 배열, serviceKey 쿼리) — 기본
//
// --dart-define=REB_APT_API_MODE=odcloud 또는 datago
// --dart-define=DATA_GO_KR_SERVICE_KEY=인증키
// --dart-define=REB_APT_ODCLOUD_PATH=/api/ApplyhomeInfoDetailSvc/v1/getAPTLttotPblancDetail
// --dart-define=REB_APT_ODCLOUD_ORIGIN=https://api.odcloud.kr

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
  static const String apiMode = String.fromEnvironment('REB_APT_API_MODE', defaultValue: 'odcloud');
  static const String splyPath = String.fromEnvironment(
    'REB_APT_SPLY_PATH',
    defaultValue: '/1613000/AptBasisOflsInfoService/getAptBasisOflsList',
  );
  static const String pageSize = String.fromEnvironment('REB_APT_PAGE_SIZE', defaultValue: '200');
  static const String dataGoOrigin = String.fromEnvironment(
    'REB_APT_DATA_GO_ORIGIN',
    defaultValue: 'https://apis.data.go.kr',
  );
  static const String odcloudPath = String.fromEnvironment(
    'REB_APT_ODCLOUD_PATH',
    defaultValue: '/api/ApplyhomeInfoDetailSvc/v1/getAPTLttotPblancDetail',
  );
  static const String odcloudOrigin = String.fromEnvironment(
    'REB_APT_ODCLOUD_ORIGIN',
    defaultValue: 'https://api.odcloud.kr',
  );
}

class RebAptSplyUrlParts {
  const RebAptSplyUrlParts({
    required this.path,
    required this.query,
    required this.keyPresent,
    required this.mode,
  });
  final String path;
  final String query;
  final bool keyPresent;
  final String mode;
}

RebAptSplyUrlParts buildRebAptSplyListUrl() {
  final m = RebAptSplyConfig.apiMode.toLowerCase();
  if (m == 'datago') {
    final key = RebAptSplyConfig.dataGoServiceKey.trim();
    final serviceKey = key.isNotEmpty ? 'serviceKey=${Uri.encodeQueryComponent(key)}' : '';
    const pageNo = 'pageNo=1';
    final num = 'numOfRows=${RebAptSplyConfig.pageSize}';
    const type = 'resultType=json';
    final path = RebAptSplyConfig.splyPath.replaceFirst(RegExp(r'^\s+'), '');
    final q = [serviceKey, pageNo, num, type].where((e) => e.isNotEmpty).join('&');
    return RebAptSplyUrlParts(path: path, query: q, keyPresent: key.isNotEmpty, mode: 'datago');
  }

  final key = RebAptSplyConfig.dataGoServiceKey.trim();
  final serviceKey = key.isNotEmpty ? 'serviceKey=${Uri.encodeQueryComponent(key)}' : '';
  const page = 'page=1';
  final perPage = 'perPage=${RebAptSplyConfig.pageSize}';
  final path = RebAptSplyConfig.odcloudPath.replaceFirst(RegExp(r'^\s+'), '');
  final q = [page, perPage, serviceKey].where((e) => e.isNotEmpty).join('&');
  return RebAptSplyUrlParts(path: path, query: q, keyPresent: key.isNotEmpty, mode: 'odcloud');
}

String toRebAptAbsoluteUrl(String path, String? query, String mode) {
  final p = path.startsWith('/') ? path : '/$path';
  final q = (query == null || query.isEmpty) ? '' : (query.startsWith('?') ? query : '?$query');

  if (mode == 'odcloud') {
    var origin = RebAptSplyConfig.odcloudOrigin.replaceAll(RegExp(r'/$'), '');
    if (origin.isEmpty) origin = 'https://api.odcloud.kr';
    return '$origin$p$q';
  }

  var origin = RebAptSplyConfig.dataGoOrigin.replaceAll(RegExp(r'/$'), '');
  if (origin.isEmpty) origin = 'https://apis.data.go.kr';
  return '$origin$p$q';
}

/// data.go + odcloud 공통
({List<Map<String, dynamic>> items, String? error}) parseRebAptSplyResponse(dynamic json) {
  if (json is! Map) {
    return (items: <Map<String, dynamic>>[], error: '빈 응답입니다.');
  }
  final m = Map<String, dynamic>.from(json);
  if (m['data'] is List) {
    final code = m['code'];
    if (code is num && code < 0) {
      return (items: <Map<String, dynamic>>[], error: m['msg']?.toString() ?? 'API 오류');
    }
    final list = m['data'] as List;
    return (
      items: list.map((e) {
        if (e is Map<String, dynamic>) return e;
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{};
      }).toList(),
      error: null,
    );
  }
  if (m['code'] is num && (m['code'] as num) < 0) {
    return (items: <Map<String, dynamic>>[], error: m['msg']?.toString() ?? 'API 오류');
  }

  final res = m['response'] as Map<String, dynamic>?;
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
    return (items: items.map((e) => Map<String, dynamic>.from(e as Map)).toList(), error: null);
  }
  if (items is Map<String, dynamic>) {
    final item = items['item'];
    if (item == null) {
      return (items: <Map<String, dynamic>>[], error: null);
    }
    if (item is List) {
      return (items: item.map((e) => Map<String, dynamic>.from(e as Map)).toList(), error: null);
    }
    if (item is Map<String, dynamic>) {
      return (items: <Map<String, dynamic>>[item], error: null);
    }
  }
  return (items: <Map<String, dynamic>>[], error: null);
}

String _t(Map<String, dynamic> item, String k) {
  final v = item[k];
  if (v == null || v == '') return '';
  return v.toString().trim();
}

String _firstT(Map<String, dynamic> item, List<String> keys) {
  for (final k in keys) {
    final v = _t(item, k);
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// 오늘 YYYYMMDD (로컬) — RCEPT_ENDDE 와 문자열 비교
String ymd8Today() {
  final d = DateTime.now();
  return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

String getOdcloudReceiptEndYmd8(Map<String, dynamic> item) {
  final v = item['RCEPT_ENDDE'] ??
      item['SPLY_RCEPT_ENDDE'] ??
      item['SPLY_RCEPT_CLSDE'] ??
      item['rceptEndde'] ??
      item['접수마감일'] ??
      item['접수종료일'];
  if (v == null) return '';
  final s = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
  return s.length >= 8 ? s.substring(0, 8) : '';
}

List<Map<String, dynamic>> filterOdcloudItemsUpcoming(List<Map<String, dynamic>> items) {
  final today = ymd8Today();
  return items.where((row) {
    final end = getOdcloudReceiptEndYmd8(row);
    if (end.isEmpty) return false;
    return end.compareTo(today) >= 0;
  }).toList();
}

CalendarEvent? mapOdcloudItemToCalendarEvent(Map<String, dynamic> item, int index) {
  var tb = _firstT(item, [
    '주택명',
    '아파트명',
    'HOUSE_NM',
    'HSMP_NM',
    'PBLANC_NM',
    'SPLY_HSMP_NM',
    'HSSPLY_HSMP_NM',
    '사업명',
    'BIZ_NM',
    'SPLY_BIZ_NM',
    'BLDG_NM',
  ]);
  if (tb.isEmpty) tb = '아파트 분양';

  final p1 = _firstT(item, ['공고번호', 'PBLANC_NO']);
  final p2 = _firstT(item, ['주택관리번호', 'HOUSE_MGMT_NO', 'HSMP_MGMT_NO']);
  final pbl =
      p1.isNotEmpty || p2.isNotEmpty ? ' (${[p1, p2].where((e) => e.isNotEmpty).join(' / ')})' : '';

  var startYmd = _firstT(item, [
    'RCEPT_BGNDE',
    'SPLY_RCEPT_BGNDE',
    'SPLY_RCEPT_STTDE',
    'rceptBgnde',
    '접수시작일',
    '청약접수시작일',
    '입주자모집공고일',
    '공고일',
    '모집공고일',
    '접수기간',
  ]);

  var endYmd = _firstT(item, [
    'RCEPT_ENDDE',
    'SPLY_RCEPT_ENDDE',
    'SPLY_RCEPT_CLSDE',
    'rceptEndde',
    '접수마감일',
    '접수종료일',
    '청약접수마감일',
  ]);
  if (endYmd.isEmpty) endYmd = startYmd;

  var starts = _parseYmdToIsoStart(startYmd);
  if (starts == null) {
    for (final v in item.values) {
      if (v == null) continue;
      final s = v.toString();
      if (RegExp(r'(\d{4}[-/.\s]?\d{2}[-/.\s]?\d{2}|\d{8})').hasMatch(s)) {
        starts = _parseYmdToIsoStart(s);
        if (starts != null) break;
      }
    }
  }
  if (starts == null) {
    final d = DateTime.now();
    starts =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';
  }
  final ends = _parseYmdToIsoEndOfDay(endYmd) ?? _parseYmdToIsoEndOfDay(startYmd) ?? starts;

  final idKey =
      '${_firstT(item, ['주택관리번호', 'HOUSE_MGMT_NO', 'HSMP_MGMT_NO'])}_${_firstT(item, ['공고번호', 'PBLANC_NO'])}_$index';
  final id = 'reb-od-${idKey.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣\\-_]'), '_')}';

  return CalendarEvent(
    id: id,
    title: '🏢 $tb$pbl',
    description: 'api.odcloud.kr(공공데이터)에서 제공됩니다. 수정/삭제할 수 없습니다.',
    startsAt: DateTime.parse(starts).toLocal(),
    endsAt: DateTime.parse(ends).toLocal(),
    isAllDay: true,
    color: '#0d47a1',
    creatorId: CalendarEvent.kExternalCreatorId,
    creatorNickname: '청약홈(ODcloud)',
    groupIds: const [],
    eventKind: 'default',
    externalSource: 'reb-odcloud',
    externalRaw: Map<String, dynamic>.from(item),
  );
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
  final id = 'reb-apt-${idRaw.toString().replaceAll(RegExp(r'[^a-zA-Z0-9\\-_]'), '_')}';
  return CalendarEvent(
    id: id,
    title: '🏢 ${titleBase.toString().trim()}$pbl',
    description: 'apis.data.go.kr(공공데이터)에서 제공됩니다. 수정/삭제할 수 없습니다.',
    startsAt: DateTime.parse(starts).toLocal(),
    endsAt: DateTime.parse(ends).toLocal(),
    isAllDay: true,
    color: '#0d47a1',
    creatorId: CalendarEvent.kExternalCreatorId,
    creatorNickname: '청약홈(부동산원)',
    groupIds: const [],
    eventKind: 'default',
    externalSource: 'reb-apt',
    externalRaw: Map<String, dynamic>.from(item),
  );
}

CalendarEvent? mapRebAptItemToCalendarEvent(Map<String, dynamic> item, int index, String mode) {
  if (mode == 'odcloud') {
    return mapOdcloudItemToCalendarEvent(item, index);
  }
  return mapSplyItemToCalendarEvent(item, index);
}

/// 네이티브/웹: odcloud·data.go origin 직접 호출
Future<({List<CalendarEvent> events, String? error})> fetchRebAptSplyList() async {
  final built = buildRebAptSplyListUrl();
  if (!built.keyPresent) {
    return (events: <CalendarEvent>[], error: 'DATA_GO_KR_SERVICE_KEY(인증키)를 --dart-define으로 설정하세요.');
  }
  if (built.path.isEmpty) {
    return (events: <CalendarEvent>[], error: 'API 경로를 확인하세요.(REB_APT_ODCLOUD_PATH / REB_APT_SPLY_PATH)');
  }
  final url = toRebAptAbsoluteUrl(built.path, built.query, built.mode);
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    final bodyJson = res.body.isNotEmpty ? jsonDecode(utf8.decode(res.bodyBytes)) : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? em;
      if (bodyJson is Map) {
        em = bodyJson['msg']?.toString() ?? bodyJson['message']?.toString();
      }
      return (events: <CalendarEvent>[], error: em ?? 'HTTP ${res.statusCode}');
    }
    if (bodyJson is! Map) {
      return (events: <CalendarEvent>[], error: 'JSON 형식이 아닙니다.');
    }
    final parsed = parseRebAptSplyResponse(bodyJson);
    if (parsed.error != null) {
      return (events: <CalendarEvent>[], error: parsed.error);
    }
    var rows = parsed.items;
    if (built.mode == 'odcloud') {
      rows = filterOdcloudItemsUpcoming(rows);
    }
    final out = <CalendarEvent>[];
    for (var i = 0; i < rows.length; i++) {
      final ev = mapRebAptItemToCalendarEvent(rows[i], i, built.mode);
      if (ev != null) out.add(ev);
    }
    return (events: out, error: null);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('cors') || msg.contains('xmlhttp') || msg.contains('clientexception')) {
      return (
        events: <CalendarEvent>[],
        error: 'CORS/네트워크: Web 빌드는 브라우저 정책에 막힐 수 있어 Android/iOS로 시험하거나 프록시를 쓰세요.',
      );
    }
    return (events: <CalendarEvent>[], error: e.toString());
  }
}
