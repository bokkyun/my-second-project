import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subway_prefs.dart';

class SubwayArrivalService {
  SubwayArrivalService._();

  // dart-define로 키를 덮어쓸 수 있고, 없으면 현재 제공된 키를 기본값으로 사용합니다.
  static const _apiKey = String.fromEnvironment(
    'SEOUL_SUBWAY_API_KEY',
    defaultValue: '506378455262636839386d76677a73',
  );
  static const _base =
      'https://swopenapi.seoul.go.kr/api/subway/$_apiKey/json/realtimeStationArrival/0/20/';

  static Future<String> buildSummary(SubwayCommuteConfig config) async {
    if (!config.hasAny) {
      return '지하철 설정 버튼에서 출퇴근 역을 저장해 주세요.';
    }

    final lines = <String>[];
    if (config.goToWork.isNotEmpty) {
      lines.add('출근');
      lines.addAll(await _forLegs(config.goToWork));
    }
    if (config.comeHome.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('퇴근');
      lines.addAll(await _forLegs(config.comeHome));
    }
    return lines.join('\n').trim();
  }

  static Future<List<String>> _forLegs(List<SubwayLeg> legs) async {
    final out = <String>[];
    for (final leg in legs) {
      out.addAll(await _arrivalLines(leg));
    }
    return out;
  }

  static Future<List<String>> _arrivalLines(SubwayLeg leg) async {
    try {
      final uri = Uri.parse('$_base${Uri.encodeComponent(leg.station)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        return ['• ${leg.station}: 정보 없음'];
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'];
      final code = (body['code'] as String? ?? '').trim();
      if (status is num && status >= 400 || code.startsWith('ERROR-')) {
        if (code == 'ERROR-338') {
          return ['• ${leg.station}: 실시간 API 권한 없음'];
        }
        return ['• ${leg.station}: API 오류($code)'];
      }
      final list = (body['realtimeArrivalList'] as List?) ?? const [];
      if (list.isEmpty) {
        return ['• ${leg.station}: 운행 정보 없음'];
      }

      final wantedSubwayId = _subwayIdFromLine(leg.line);
      final byDirection = <String, Map<String, dynamic>>{};
      for (final row in list.whereType<Map>()) {
        final m = row.cast<String, dynamic>();
        final subwayId = (m['subwayId'] as String? ?? '').trim();
        if (wantedSubwayId != null && subwayId != wantedSubwayId) continue;

        final direction = _extractDirection(
          (m['trainLineNm'] as String? ?? '').trim(),
          (m['updnLine'] as String? ?? '').trim(),
        );
        if (direction.isEmpty) continue;

        final current = byDirection[direction];
        if (current == null) {
          byDirection[direction] = m;
          continue;
        }
        final oldSec = int.tryParse((current['barvlDt'] as String? ?? '').trim());
        final newSec = int.tryParse((m['barvlDt'] as String? ?? '').trim());
        if (newSec != null && (oldSec == null || newSec < oldSec)) {
          byDirection[direction] = m;
        }
      }

      if (byDirection.isEmpty) {
        return ['• ${leg.station}: 운행 정보 없음'];
      }

      final dirs = byDirection.keys.toList()..sort();
      final lines = <String>[];
      for (final dir in dirs) {
        final pick = byDirection[dir]!;
        lines.add('• ${leg.station} $dir: ${_etaText(pick)}');
      }
      return lines;
    } catch (_) {
      return ['• ${leg.station}: 조회 실패'];
    }
  }

  static String _etaText(Map<String, dynamic> row) {
    final secondsRaw = (row['barvlDt'] as String? ?? '').trim();
    final seconds = int.tryParse(secondsRaw);
    if (seconds != null && seconds >= 0) {
      final minutes = (seconds / 60).ceil();
      return minutes <= 0 ? '곧 도착' : '$minutes분 후 도착';
    }
    final msg = (row['arvlMsg2'] as String? ?? '').trim();
    return msg.isEmpty ? '정보 없음' : msg;
  }

  static String _extractDirection(String trainLine, String updnLine) {
    final reg = RegExp(r'([가-힣A-Za-z0-9]+행)');
    final match = reg.firstMatch(trainLine);
    if (match != null) return match.group(1) ?? '';
    return updnLine;
  }

  static String? _subwayIdFromLine(String lineName) {
    if (lineName.isEmpty) return null;
    if (lineName.contains('1호선')) return '1001';
    if (lineName.contains('2호선')) return '1002';
    if (lineName.contains('3호선')) return '1003';
    if (lineName.contains('4호선')) return '1004';
    if (lineName.contains('5호선')) return '1005';
    if (lineName.contains('6호선')) return '1006';
    if (lineName.contains('7호선')) return '1007';
    if (lineName.contains('8호선')) return '1008';
    if (lineName.contains('9호선')) return '1009';
    if (lineName.contains('중앙선')) return '1061';
    if (lineName.contains('경의중앙선')) return '1063';
    if (lineName.contains('공항철도')) return '1065';
    if (lineName.contains('신분당선')) return '1077';
    if (lineName.contains('수인분당선')) return '1075';
    if (lineName.contains('경춘선')) return '1067';
    if (lineName.contains('경강선')) return '1081';
    if (lineName.contains('서해선')) return '1093';
    if (lineName.contains('우이신설선')) return '1092';
    return null;
  }
}
