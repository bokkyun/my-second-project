import 'dart:async';

import 'package:timezone/timezone.dart' as tz;

import '../models/subway_display_row.dart';
import 'subway_prefs.dart';
import 'subway_schedule_service.dart';

/// 출퇴근 경로별 지하철 **시간표** 기준 다음 도착 안내 (공공데이터 getTrainSch)
class SubwayArrivalService {
  SubwayArrivalService._();

  /// 홈 위젯 등 텍스트 전용(간단 문자열)
  static Future<String> buildSummary(SubwayCommuteConfig config) async {
    final rows = await buildDisplayRows(config);
    if (rows.isEmpty) {
      return '지하철 설정에서 역을 저장해 주세요.';
    }
    final buf = StringBuffer();
    for (final r in rows) {
      if (r.isSection) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln(r.sectionLabel);
        continue;
      }
      buf.writeln(
        '${r.station} ${r.terminal} ${r.eta}',
      );
    }
    return buf.toString().trim();
  }

  /// UI용(색·줄바꿈)
  static Future<List<SubwayDisplayRow>> buildDisplayRows(
    SubwayCommuteConfig config,
  ) async {
    if (!config.hasAny) return const [];

    final out = <SubwayDisplayRow>[];
    if (config.goToWork.isNotEmpty) {
      out.add(SubwayDisplayRow.section('출근'));
      for (final leg in config.goToWork) {
        out.addAll(await _rowsForLeg(leg));
      }
    }
    if (config.comeHome.isNotEmpty) {
      out.add(SubwayDisplayRow.section('퇴근'));
      for (final leg in config.comeHome) {
        out.addAll(await _rowsForLeg(leg));
      }
    }
    return out;
  }

  static Future<List<SubwayDisplayRow>> _rowsForLeg(SubwayLeg leg) async {
    try {
      if (leg.line.trim().isEmpty) {
        return [
          SubwayDisplayRow.line(
            station: leg.station,
            trackShort: '',
            terminal: '',
            eta: '노선을 선택해 주세요',
            trackKind: SubwayTrackKind.other,
          ),
        ];
      }

      final items = await SubwayScheduleService.fetchAllForStation(
        lineNm: leg.line,
        stnNm: leg.station,
      );

      if (items.isEmpty) {
        return [
          SubwayDisplayRow.line(
            station: leg.station,
            trackShort: '',
            terminal: '',
            eta: '시간표 없음',
            trackKind: SubwayTrackKind.other,
          ),
        ];
      }

      final now = SubwayScheduleService.nowSeoul();

      final byKey = <String, _ScheduledCandidate>{};
      for (final m in items) {
        final rawT = SubwayScheduleService.arrivalAtStation(m);
        if (rawT == null) continue;

        final terminal = SubwayScheduleService.terminalFromItem(m);
        final updn = SubwayScheduleService.updnFromItem(m);
        final key = '$updn|$terminal';

        final nextT = _nextOccurrence(rawT, now);
        final cur = byKey[key];
        if (cur == null || nextT.isBefore(cur.time)) {
          byKey[key] = _ScheduledCandidate(
            time: nextT,
            updn: updn,
            terminal: terminal,
          );
        }
      }

      if (byKey.isEmpty) {
        return [
          SubwayDisplayRow.line(
            station: leg.station,
            trackShort: '',
            terminal: '',
            eta: '열차 시각 없음',
            trackKind: SubwayTrackKind.other,
          ),
        ];
      }

      final keys = byKey.keys.toList()
        ..sort((a, b) {
          final upA = SubwayScheduleService.kindFromUpdn(
                a.split('|').first,
                leg.line,
              ) ==
              SubwayTrackKind.up;
          final upB = SubwayScheduleService.kindFromUpdn(
                b.split('|').first,
                leg.line,
              ) ==
              SubwayTrackKind.up;
          if (upA != upB) return upA ? -1 : 1;
          return a.compareTo(b);
        });

      return keys.map((k) {
        final c = byKey[k]!;
        final trackShort =
            SubwayScheduleService.shortTrackLabelForQuery(c.updn, leg.line);
        final kind = SubwayScheduleService.kindFromUpdn(c.updn, leg.line);
        final eta = SubwayScheduleService.formatEta(c.time, now);
        return SubwayDisplayRow.line(
          station: leg.station,
          trackShort: trackShort,
          terminal: c.terminal.isEmpty ? '—' : c.terminal,
          eta: eta,
          trackKind: kind,
        );
      }).toList();
    } on TimeoutException {
      return [
        SubwayDisplayRow.line(
          station: leg.station,
          trackShort: '',
          terminal: '',
          eta: '시간 초과',
          trackKind: SubwayTrackKind.other,
        ),
      ];
    } catch (_) {
      return [
        SubwayDisplayRow.line(
          station: leg.station,
          trackShort: '',
          terminal: '',
          eta: '조회 실패',
          trackKind: SubwayTrackKind.other,
        ),
      ];
    }
  }

  /// 오늘 시각이 이미 지났으면 다음 날 같은 시각으로 간주(요일별 시간표 차이는 반영하지 않음)
  static tz.TZDateTime _nextOccurrence(tz.TZDateTime t, tz.TZDateTime now) {
    var x = t;
    while (!x.isAfter(now)) {
      x = x.add(const Duration(days: 1));
    }
    return x;
  }

}

class _ScheduledCandidate {
  _ScheduledCandidate({
    required this.time,
    required this.updn,
    required this.terminal,
  });

  final tz.TZDateTime time;
  final String updn;
  final String terminal;
}
