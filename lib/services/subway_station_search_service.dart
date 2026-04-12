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

/// 역 이름 검색(서울 열린데이터 역 검색 API). 도착 시간은 [SubwayScheduleService] 시간표 API 사용.
class SubwayStationSearchService {
  SubwayStationSearchService._();

  static const _apiKey = String.fromEnvironment(
    'SEOUL_SUBWAY_API_KEY',
    defaultValue: '73594a7a6362636838317744686270',
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
}
