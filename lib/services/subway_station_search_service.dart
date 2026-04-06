import 'dart:convert';

import 'package:http/http.dart' as http;

class SubwayStationCandidate {
  const SubwayStationCandidate({
    required this.stationName,
    required this.lineName,
  });

  final String stationName;
  final String lineName;

  String get display => '$stationName ($lineName)';
}

class SubwayStationSearchService {
  SubwayStationSearchService._();

  static const _apiKey = String.fromEnvironment(
    'SEOUL_SUBWAY_API_KEY',
    defaultValue: '506378455262636839386d76677a73',
  );

  static Future<List<SubwayStationCandidate>> searchStations(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    final uri = Uri.parse(
      'http://openapi.seoul.go.kr:8088/$_apiKey/json/SearchInfoBySubwayNameService/1/50/${Uri.encodeComponent(keyword)}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return const [];

    final body = jsonDecode(res.body);
    if (body is! Map) return const [];
    final raw = body['SearchInfoBySubwayNameService'];
    if (raw is! Map) return const [];
    final rows = raw['row'];
    if (rows is! List) return const [];

    final out = <SubwayStationCandidate>[];
    final dedupe = <String>{};
    for (final row in rows.whereType<Map>()) {
      final m = row.cast<String, dynamic>();
      final station = (m['STATION_NM'] as String? ?? '').trim();
      final line = (m['LINE_NUM'] as String? ?? '').trim();
      if (station.isEmpty || line.isEmpty) continue;
      final key = '$station::$line';
      if (dedupe.add(key)) {
        out.add(SubwayStationCandidate(stationName: station, lineName: line));
      }
    }
    return out;
  }

  static Future<List<String>> fetchDirections({
    required String stationName,
    String? lineName,
  }) async {
    final station = stationName.trim();
    if (station.isEmpty) return const [];

    final uri = Uri.parse(
      'https://swopenapi.seoul.go.kr/api/subway/$_apiKey/json/realtimeStationArrival/0/50/${Uri.encodeComponent(station)}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return const [];

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return const [];
    final status = body['status'];
    final code = (body['code'] as String? ?? '').trim();
    if (status is num && status >= 400 || code.startsWith('ERROR-')) {
      return const [];
    }
    final list = (body['realtimeArrivalList'] as List?) ?? const [];
    if (list.isEmpty) return const [];

    final wantedSubwayId = _subwayIdFromLine(lineName ?? '');
    final seen = <String>{};
    final out = <String>[];
    for (final row in list.whereType<Map>()) {
      final m = row.cast<String, dynamic>();
      final subwayId = (m['subwayId'] as String? ?? '').trim();
      if (wantedSubwayId != null && subwayId != wantedSubwayId) continue;

      final trainLine = (m['trainLineNm'] as String? ?? '').trim();
      final fromTrainLine = _extractDirection(trainLine);
      final value = fromTrainLine ?? ((m['updnLine'] as String? ?? '').trim());
      if (value.isEmpty) continue;
      if (seen.add(value)) out.add(value);
    }

    if (out.isEmpty) return const [];

    out.sort((a, b) {
      final aHang = a.endsWith('행');
      final bHang = b.endsWith('행');
      if (aHang != bHang) return aHang ? -1 : 1;
      return a.compareTo(b);
    });
    return out;
  }

  static String? _extractDirection(String trainLine) {
    if (trainLine.isEmpty) return null;
    final reg = RegExp(r'([가-힣A-Za-z0-9]+행)');
    final match = reg.firstMatch(trainLine);
    if (match == null) return null;
    return match.group(1);
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
