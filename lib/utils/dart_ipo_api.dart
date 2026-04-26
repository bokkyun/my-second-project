// 금융감독원 Open DART — 공시 목록(list.json), 공모·지분증권(C·C001)
// --dart-define=DART_CRTFC_KEY=인증키
// @see https://opendart.fss.or.kr/

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/event.dart';

class DartIpoConfig {
  DartIpoConfig._();

  static const String crtfcKey = String.fromEnvironment('DART_CRTFC_KEY');
  static const String pblntfTy = String.fromEnvironment('DART_PBLNTF_TY', defaultValue: 'C');
  static const String pblntfDetailTy = String.fromEnvironment('DART_PBLNTF_DETAIL_TY', defaultValue: 'C001');
  static const String pageCount = String.fromEnvironment('DART_PAGE_COUNT', defaultValue: '100');
}

String _ymd8(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}

({String bgnDe, String endDe}) rangeYmd8(DateTime start, DateTime end) {
  final a = _ymd8(start);
  final b = _ymd8(end);
  if (a.compareTo(b) <= 0) {
    return (bgnDe: a, endDe: b);
  }
  return (bgnDe: b, endDe: a);
}

DateTime? _parseRceptStart(String? ymd) {
  if (ymd == null || ymd.length < 8) return null;
  final s = ymd.replaceAll(RegExp(r'[^0-9]'), '');
  if (s.length < 8) return null;
  return DateTime(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(4, 6)),
    int.parse(s.substring(6, 8)),
  );
}

DateTime? _rceptEndOfDay(String? ymd) {
  final d = _parseRceptStart(ymd);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

CalendarEvent? mapDartListItemToEvent(Map<String, dynamic> row, int index) {
  final rcept = row['rcept_dt']?.toString().trim() ?? '';
  if (rcept.isEmpty) return null;
  final start = _parseRceptStart(rcept);
  final end = _rceptEndOfDay(rcept) ?? start;
  if (start == null || end == null) return null;
  final corp = (row['corp_name'] ?? row['flr_nm'] ?? '기업').toString().trim();
  final title = '📈 ${corp.isEmpty ? '기업' : corp}';
  final rno = (row['rcept_no'] ?? 'i$index').toString();
  final id = 'dart-ipo-${rno.replaceAll(RegExp(r'[^a-zA-Z0-9\\-_]'), '_')}';
  return CalendarEvent(
    id: id,
    title: title,
    description: 'opendart.fss.or.kr 공시 목록(공개 데이터). 수정/삭제할 수 없습니다.',
    startsAt: start,
    endsAt: end,
    isAllDay: true,
    color: '#1b5e20',
    creatorId: CalendarEvent.kExternalCreatorId,
    creatorNickname: '금감원·DART',
    groupIds: const [],
    eventKind: 'default',
    externalSource: 'ipo',
    externalRaw: Map<String, dynamic>.from(row),
  );
}

/// list.json — 페이지 루프(최대 [maxPages])
Future<({List<CalendarEvent> events, String? error})> fetchDartIpoList(
  DateTime viewStart,
  DateTime viewEnd, {
  int maxPages = 25,
}) async {
  final key = DartIpoConfig.crtfcKey.trim();
  if (key.isEmpty) {
    return (events: <CalendarEvent>[], error: 'DART_CRTFC_KEY(인증키)를 --dart-define으로 설정하세요.');
  }
  final range = rangeYmd8(viewStart, viewEnd);
  const base = 'https://opendart.fss.or.kr/api/list.json';
  final all = <Map<String, dynamic>>[];
  var page = 1;
  var totalPage = 1;
  do {
    final q = <String, String>{
      'crtfc_key': key,
      'pblntf_ty': DartIpoConfig.pblntfTy,
      'pblntf_detail_ty': DartIpoConfig.pblntfDetailTy,
      'bgn_de': range.bgnDe,
      'end_de': range.endDe,
      'page_no': '$page',
      'page_count': DartIpoConfig.pageCount,
    };
    final uri = Uri.parse(base).replace(queryParameters: q);
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 45));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return (events: <CalendarEvent>[], error: 'HTTP ${res.statusCode}');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) {
        return (events: <CalendarEvent>[], error: '응답 형식이 아닙니다.');
      }
      if (body['status']?.toString() != '000') {
        return (
          events: <CalendarEvent>[],
          error: body['message']?.toString() ?? 'DART API 오류',
        );
      }
      final list = (body['list'] as List<dynamic>?) ?? [];
      for (final e in list) {
        if (e is Map<String, dynamic>) all.add(e);
        if (e is Map) all.add(Map<String, dynamic>.from(e));
      }
      totalPage = int.tryParse(body['total_page']?.toString() ?? '1') ?? 1;
      page += 1;
    } catch (e) {
      return (events: <CalendarEvent>[], error: e.toString());
    }
  } while (page <= totalPage && page <= maxPages);

  final seen = <String>{};
  final out = <CalendarEvent>[];
  for (var i = 0; i < all.length; i++) {
    final ev = mapDartListItemToEvent(all[i], i);
    if (ev == null) continue;
    if (seen.contains(ev.id)) continue;
    seen.add(ev.id);
    out.add(ev);
  }
  return (events: out, error: null);
}
