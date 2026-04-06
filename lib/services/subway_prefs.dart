import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SubwayLeg {
  const SubwayLeg({
    required this.station,
    required this.direction,
    this.line = '',
  });

  final String station;
  final String direction;
  final String line;

  Map<String, dynamic> toJson() => {
        'station': station,
        'direction': direction,
        'line': line,
      };

  factory SubwayLeg.fromJson(Map<String, dynamic> json) {
    return SubwayLeg(
      station: (json['station'] as String? ?? '').trim(),
      direction: (json['direction'] as String? ?? '').trim(),
      line: (json['line'] as String? ?? '').trim(),
    );
  }

  bool get isValid => station.isNotEmpty;
}

class SubwayCommuteConfig {
  const SubwayCommuteConfig({
    required this.goToWork,
    required this.comeHome,
  });

  final List<SubwayLeg> goToWork;
  final List<SubwayLeg> comeHome;

  static const empty = SubwayCommuteConfig(goToWork: [], comeHome: []);

  bool get hasAny => goToWork.isNotEmpty || comeHome.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'goToWork': goToWork.map((e) => e.toJson()).toList(),
        'comeHome': comeHome.map((e) => e.toJson()).toList(),
      };

  factory SubwayCommuteConfig.fromJson(Map<String, dynamic> json) {
    List<SubwayLeg> parse(Object? raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => SubwayLeg.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.isValid)
          .toList();
    }

    return SubwayCommuteConfig(
      goToWork: parse(json['goToWork']),
      comeHome: parse(json['comeHome']),
    );
  }
}

class SubwayPrefs {
  SubwayPrefs._();

  static const _key = 'subway_commute_config_v1';

  static Future<SubwayCommuteConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return SubwayCommuteConfig.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SubwayCommuteConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return SubwayCommuteConfig.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return SubwayCommuteConfig.empty;
  }

  static Future<void> save(SubwayCommuteConfig config) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(config.toJson()));
  }
}
