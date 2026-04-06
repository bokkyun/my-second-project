import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subway_prefs.dart';

class SubwayArrivalService {
  SubwayArrivalService._();

  static const _base =
      'https://swopenapi.seoul.go.kr/api/subway/sample/json/realtimeStationArrival/0/20/';

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
      out.add(await _arrivalLine(leg));
    }
    return out;
  }

  static Future<String> _arrivalLine(SubwayLeg leg) async {
    try {
      final uri = Uri.parse('$_base${Uri.encodeComponent(leg.station)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        return '• ${leg.station} ${leg.direction}: 정보 없음';
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['realtimeArrivalList'] as List?) ?? const [];
      if (list.isEmpty) {
        return '• ${leg.station} ${leg.direction}: 운행 정보 없음';
      }

      Map<String, dynamic> pick =
          (list.first as Map).cast<String, dynamic>();
      final directionNeedle = leg.direction.toLowerCase();
      for (final row in list.whereType<Map>()) {
        final m = row.cast<String, dynamic>();
        final updn = (m['updnLine'] as String? ?? '').toLowerCase();
        final trainLine = (m['trainLineNm'] as String? ?? '').toLowerCase();
        if (updn.contains(directionNeedle) ||
            trainLine.contains(directionNeedle)) {
          pick = m;
          break;
        }
      }

      final secondsRaw = (pick['barvlDt'] as String? ?? '').trim();
      final seconds = int.tryParse(secondsRaw);
      String eta;
      if (seconds != null && seconds >= 0) {
        final minutes = (seconds / 60).ceil();
        eta = minutes <= 0 ? '곧 도착' : '$minutes분 후';
      } else {
        eta = (pick['arvlMsg2'] as String? ?? '').trim();
        if (eta.isEmpty) eta = '정보 없음';
      }
      return '• ${leg.station} ${leg.direction}: $eta';
    } catch (_) {
      return '• ${leg.station} ${leg.direction}: 조회 실패';
    }
  }
}
