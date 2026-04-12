import 'package:flutter/material.dart';

/// 상행·내선 vs 하행·외선 구분(표시 색용)
enum SubwayTrackKind {
  up,
  down,
  other,
}

/// 지하철 하단 패널 한 줄(또는 출근/퇴근 구역 제목)
class SubwayDisplayRow {
  const SubwayDisplayRow._({
    required this.kind,
    this.sectionLabel,
    this.station,
    this.trackShort = '',
    this.terminal = '',
    this.eta = '',
    this.trackKind = SubwayTrackKind.other,
  });

  final SubwayRowKind kind;
  final String? sectionLabel;
  final String? station;
  /// 상·하 등 짧은 표기
  final String trackShort;
  final String terminal;
  final String eta;
  final SubwayTrackKind trackKind;

  bool get isSection => kind == SubwayRowKind.section;

  factory SubwayDisplayRow.section(String label) {
    return SubwayDisplayRow._(
      kind: SubwayRowKind.section,
      sectionLabel: label,
    );
  }

  factory SubwayDisplayRow.line({
    required String station,
    required String trackShort,
    required String terminal,
    required String eta,
    required SubwayTrackKind trackKind,
  }) {
    return SubwayDisplayRow._(
      kind: SubwayRowKind.line,
      station: station,
      trackShort: trackShort,
      terminal: terminal,
      eta: eta,
      trackKind: trackKind,
    );
  }

  Color accentColor(ColorScheme scheme) {
    switch (trackKind) {
      case SubwayTrackKind.up:
        return scheme.primary;
      case SubwayTrackKind.down:
        return scheme.tertiary;
      case SubwayTrackKind.other:
        return scheme.onSurfaceVariant;
    }
  }
}

enum SubwayRowKind { section, line }
