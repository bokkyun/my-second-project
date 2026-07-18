import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/buy_signal_types.dart';
import '../models/event.dart';

/// 캘린더 매수시그널 레이어 on/off (국내·미국·코인)
class StockSignalLayerFilter {
  const StockSignalLayerFilter({
    required this.includeKr,
    required this.includeUs,
    required this.includeCrypto,
  });

  final bool includeKr;
  final bool includeUs;
  final bool includeCrypto;

  bool get anyEnabled => includeKr || includeUs || includeCrypto;

  bool get queriesAllMarkets => includeKr && includeUs && includeCrypto;

  String get cacheKey => '$includeKr|$includeUs|$includeCrypto';
}

/// 레거시 2분할 호환
enum StockSignalMarketScope { all, krOnly, usOnly }

/// 웹 `useSignalEvents.js` / `signalDisplayMerge.js` 포팅: Supabase `signals` → 캘린더 일정.
class StockSignalsService {
  StockSignalsService._();

  static final _client = Supabase.instance.client;

  static const externalSourceKr = 'stock-signal-kr';
  static const externalSourceUs = 'stock-signal-us';
  static const externalSourceCrypto = 'stock-signal-crypto';
  /// 구버전 호환
  static const externalSourceLegacy = 'stock-signal';

  static const _krMarkets = {'KOSPI', 'KOSDAQ', 'KRX'};
  static const _usMarkets = {'US', 'NYSE', 'NASDAQ', 'AMEX', 'NYSEARCA', 'BATS'};
  static const _cryptoMarkets = {'UPBIT'};
  static const _krDbMarkets = ['KOSPI', 'KOSDAQ', 'KRX'];
  static const _usDbMarkets = ['US', 'NYSE', 'NASDAQ', 'AMEX', 'NYSEARCA', 'BATS'];
  static const _cryptoDbMarkets = ['UPBIT'];

  static bool isKrMarket(String? market) {
    final m = (market ?? '').trim().toUpperCase();
    if (m.isEmpty) return false;
    return _krMarkets.contains(m);
  }

  static bool isUsMarket(String? market) {
    final m = (market ?? '').trim().toUpperCase();
    if (m.isEmpty) return false;
    return _usMarkets.contains(m);
  }

  static bool isCryptoMarket(String? market) {
    final m = (market ?? '').trim().toUpperCase();
    return _cryptoMarkets.contains(m);
  }

  static bool isCryptoSignalRow(Map<String, dynamic> row) {
    if (isCryptoMarket('${row['market']}')) return true;
    final code = '${row['code'] ?? ''}'.trim().toUpperCase();
    return code.startsWith('KRW-');
  }

  /// DB `market` 또는 종목코드 형태로 KR/US 추정
  static bool isKrSignalRow(Map<String, dynamic> row) {
    if (isCryptoSignalRow(row)) return false;
    if (isKrMarket('${row['market']}')) return true;
    if (isUsMarket('${row['market']}')) return false;
    final code = '${row['code'] ?? ''}'.trim();
    if (RegExp(r'^\d{6}$').hasMatch(code)) return true;
    return !RegExp(r'^[A-Za-z]').hasMatch(code);
  }

  static bool isStockSignalEvent(CalendarEvent event) {
    final s = event.externalSource;
    return s == externalSourceKr ||
        s == externalSourceUs ||
        s == externalSourceCrypto ||
        s == externalSourceLegacy;
  }

  static bool isCryptoSignalEvent(CalendarEvent event) {
    if (!isStockSignalEvent(event)) return false;
    if (event.externalSource == externalSourceCrypto) return true;
    return _eventLooksCrypto(event);
  }

  static bool _eventLooksCrypto(CalendarEvent event) {
    final rawRows = event.externalRaw?['merged_rows'];
    if (rawRows is List) {
      for (final item in rawRows) {
        if (item is Map && isCryptoSignalRow(Map<String, dynamic>.from(item))) {
          return true;
        }
      }
    }
    final region = '${event.externalRaw?['region'] ?? ''}';
    if (region == 'crypto') return true;
    return false;
  }

  static bool isKrSignalEvent(CalendarEvent event) {
    if (!isStockSignalEvent(event)) return false;
    if (isCryptoSignalEvent(event)) return false;
    if (event.externalSource == externalSourceUs) return false;
    if (event.externalSource == externalSourceKr) return true;
    return !_eventLooksUs(event);
  }

  static bool isUsSignalEvent(CalendarEvent event) {
    if (!isStockSignalEvent(event)) return false;
    if (isCryptoSignalEvent(event)) return false;
    if (event.externalSource == externalSourceUs) return true;
    if (event.externalSource == externalSourceKr) return false;
    return _eventLooksUs(event);
  }

  static bool _eventLooksUs(CalendarEvent event) {
    final rawRows = event.externalRaw?['merged_rows'];
    if (rawRows is List) {
      for (final item in rawRows) {
        if (item is Map) {
          if (isUsMarket('${item['market']}')) return true;
          if (isKrMarket('${item['market']}')) return false;
          final code = '${item['code'] ?? ''}'.trim();
          if (RegExp(r'^[A-Za-z]').hasMatch(code)) return true;
          if (RegExp(r'^\d{6}$').hasMatch(code)) return false;
        }
      }
    }
    final region = '${event.externalRaw?['region'] ?? ''}';
    if (region == 'us') return true;
    if (region == 'kr') return false;
    return false;
  }

  static String _externalSourceForRow(Map<String, dynamic> row) {
    if (isCryptoSignalRow(row)) return externalSourceCrypto;
    return isKrSignalRow(row) ? externalSourceKr : externalSourceUs;
  }

  static dynamic _applyLayerFilter(dynamic filterQuery, StockSignalLayerFilter layers) {
    if (layers.queriesAllMarkets) return filterQuery;

    final inList = <String>[];
    if (layers.includeUs) inList.addAll(_usDbMarkets);
    if (layers.includeCrypto) inList.addAll(_cryptoDbMarkets);

    final orParts = <String>[];
    if (inList.isNotEmpty) {
      orParts.add('market.in.(${inList.join(',')})');
    }
    if (layers.includeKr) {
      orParts.add('market.in.(${_krDbMarkets.join(',')})');
      orParts.add('market.is.null');
    }
    if (orParts.isEmpty) {
      return filterQuery.inFilter('market', ['__none__']);
    }
    if (orParts.length == 1 && !layers.includeKr) {
      return filterQuery.inFilter('market', inList);
    }
    return filterQuery.or(orParts.join(','));
  }

  static StockSignalLayerFilter layerFilterFromLegacyScope(StockSignalMarketScope scope) {
    switch (scope) {
      case StockSignalMarketScope.krOnly:
        return const StockSignalLayerFilter(
          includeKr: true,
          includeUs: false,
          includeCrypto: false,
        );
      case StockSignalMarketScope.usOnly:
        return const StockSignalLayerFilter(
          includeKr: false,
          includeUs: true,
          includeCrypto: false,
        );
      case StockSignalMarketScope.all:
        return const StockSignalLayerFilter(
          includeKr: true,
          includeUs: true,
          includeCrypto: true,
        );
    }
  }

  static const _pageSize = 1000;
  static const _maxRows = 150000;
  static const _queryCacheTtl = Duration(seconds: 30);

  static String? _queryCacheKey;
  static List<Map<String, dynamic>>? _queryCacheData;
  static DateTime? _queryCacheAt;

  static void clearQueryCache() {
    _queryCacheKey = null;
    _queryCacheData = null;
    _queryCacheAt = null;
  }

  static String _layerFilterCacheKey(StockSignalLayerFilter layers) => layers.cacheKey;

  static bool _rowMatchesLayers(Map<String, dynamic> row, StockSignalLayerFilter layers) {
    if (layers.queriesAllMarkets) return true;
    if (layers.includeKr && isKrSignalRow(row)) return true;
    if (layers.includeUs && !isKrSignalRow(row) && !isCryptoSignalRow(row)) return true;
    if (layers.includeCrypto && isCryptoSignalRow(row)) return true;
    return false;
  }

  static String _toYmd(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
  }

  static String? _addDaysToYmd(String ymd, int deltaDays) {
    final parts = ymd.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((n) => n == null)) return null;
    final dt = DateTime(parts[0]!, parts[1]!, parts[2]!);
    return _toYmd(dt.add(Duration(days: deltaDays)));
  }

  static int _spanDaysInclusive(String startYmd, String endYmd) {
    final ps = startYmd.split('-').map(int.tryParse).toList();
    final pe = endYmd.split('-').map(int.tryParse).toList();
    if (ps.length != 3 || pe.length != 3) return 0;
    final t1 = DateTime(ps[0]!, ps[1]!, ps[2]!).millisecondsSinceEpoch;
    final t2 = DateTime(pe[0]!, pe[1]!, pe[2]!).millisecondsSinceEpoch;
    final days = ((t2 - t1) / 86400000).round() + 1;
    return days;
  }

  /// 주·격자 구간이 짧을 때 시그널만 좁게 잡히는 것을 완화 (기본 최소 42일).
  static ({String start, String end}) widenSignalQueryYmdRange(
    String startYmd,
    String endYmd, {
    int minSpanDays = 42,
  }) {
    if (startYmd.isEmpty || endYmd.isEmpty) {
      return (start: startYmd, end: endYmd);
    }
    final span = _spanDaysInclusive(startYmd, endYmd);
    if (span >= minSpanDays) return (start: startYmd, end: endYmd);
    final pad = ((minSpanDays - span) / 2).ceil();
    final s = _addDaysToYmd(startYmd, -pad) ?? startYmd;
    final e = _addDaysToYmd(endYmd, pad) ?? endYmd;
    return (start: s, end: e);
  }

  static String _categoryColor(String? category) {
    return '#f57c00';
  }

  /// 종목명에 스팩(SPAC)이 포함되면 제외 (`realtime_scanner.py` 규칙과 동일)
  static bool isSpacSignalRow(Map<String, dynamic> row) {
    final name = '${row['name'] ?? ''}'.trim();
    if (name.isEmpty) return false;
    if (name.contains('스팩')) return true;
    if (name.toUpperCase().contains('SPAC')) return true;
    return false;
  }

  static List<List<Map<String, dynamic>>> groupSignalRowsForDisplay(
      List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return [];
    final m = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final code = '${row['code'] ?? ''}'.trim();
      final name = '${row['name'] ?? ''}'.trim();
      final stockKey = code.isEmpty ? 'name:$name' : code;
      final cat = '${row['signal_category'] ?? '기타'}'.trim().isEmpty
          ? '기타'
          : '${row['signal_category'] ?? '기타'}';
      final date = '${row['date'] ?? ''}';
      final k = '$date|$cat|$stockKey';
      m.putIfAbsent(k, () => []).add(Map<String, dynamic>.from(row));
    }
    return m.values.map((grp) {
      final byType = <String, Map<String, dynamic>>{};
      for (final r in grp) {
        final st = '${r['signal_type'] ?? ''}';
        byType.putIfAbsent(st, () => r);
      }
      final vals = byType.values.toList()
        ..sort((a, b) =>
            '${a['signal_type']}'.compareTo('${b['signal_type']}'));
      return vals;
    }).toList();
  }

  static Future<({List<Map<String, dynamic>> data, PostgrestException? error})>
      fetchSignalsRawForYmdRange(
    String startYmd,
    String endYmd, {
    StockSignalLayerFilter? layerFilter,
    StockSignalMarketScope? marketScope,
    bool forceRefresh = false,
  }) async {
    final layers = layerFilter ??
        (marketScope != null
            ? layerFilterFromLegacyScope(marketScope)
            : const StockSignalLayerFilter(
                includeKr: true,
                includeUs: true,
                includeCrypto: true,
              ));
    if (!layers.anyEnabled) {
      return (data: <Map<String, dynamic>>[], error: null);
    }

    final cacheKey = '$startYmd|$endYmd|${_layerFilterCacheKey(layers)}';
    if (!forceRefresh &&
        _queryCacheKey == cacheKey &&
        _queryCacheData != null &&
        _queryCacheAt != null &&
        DateTime.now().difference(_queryCacheAt!) < _queryCacheTtl) {
      return (data: List<Map<String, dynamic>>.from(_queryCacheData!), error: null);
    }

    final seen = <String>{};
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    for (;;) {
      try {
        var filterQuery = _client
            .from('signals')
            .select(
                'date, code, name, market, signal_type, signal_category, signal_name')
            .gte('date', startYmd)
            .lte('date', endYmd);
        filterQuery = _applyLayerFilter(filterQuery, layers);
        final res = await filterQuery
            .order('date', ascending: true)
            .range(offset, offset + _pageSize - 1);
        final chunk = List<Map<String, dynamic>>.from(
            (res as List).map((e) => Map<String, dynamic>.from(e as Map)));

        for (final row in chunk) {
          if (!_rowMatchesLayers(row, layers)) continue;
          final k =
              '${row['date']}|${row['code']}|${row['signal_type']}';
          if (seen.contains(k)) continue;
          seen.add(k);
          all.add(row);
        }
        if (chunk.length < _pageSize) break;
        offset += _pageSize;
        if (all.length >= _maxRows) break;
      } on PostgrestException catch (e) {
        return (data: <Map<String, dynamic>>[], error: e);
      } catch (e, st) {
        debugPrint('[StockSignals] fetchSignalsRawForYmdRange: $e\n$st');
        rethrow;
      }
    }
    _queryCacheKey = cacheKey;
    _queryCacheData = List<Map<String, dynamic>>.from(all);
    _queryCacheAt = DateTime.now();
    return (data: all, error: null);
  }

  /// [gridFirstDay]·[gridLastDay]: 달력 격자의 첫/마지막 날짜(시간 무시).
  static Future<({List<CalendarEvent> events, String? error})>
      fetchCalendarEvents({
    required DateTime gridFirstDay,
    required DateTime gridLastDay,
    Set<String> enabledSignalTypes = const {},
    StockSignalLayerFilter? layerFilter,
    StockSignalMarketScope? marketScope,
    bool forceRefresh = false,
  }) async {
    try {
      final layers = layerFilter ??
          (marketScope != null
              ? layerFilterFromLegacyScope(marketScope)
              : const StockSignalLayerFilter(
                  includeKr: true,
                  includeUs: true,
                  includeCrypto: true,
                ));
      if (!layers.anyEnabled) {
        return (events: <CalendarEvent>[], error: null);
      }

      final startYmd = _toYmd(gridFirstDay);
      final endYmd = _toYmd(gridLastDay);
      final widened = widenSignalQueryYmdRange(startYmd, endYmd);

      final raw = await fetchSignalsRawForYmdRange(
        widened.start,
        widened.end,
        layerFilter: layers,
        forceRefresh: forceRefresh,
      );
      if (raw.error != null) {
        final msg =
            raw.error!.message.trim().isNotEmpty ? raw.error!.message : '$raw.error';
        return (events: <CalendarEvent>[], error: msg);
      }

      var rows = raw.data;
      if (!coversAllBuySignalTypes(enabledSignalTypes)) {
        rows = rows.where((r) => enabledSignalTypes.contains('${r['signal_type'] ?? ''}')).toList();
      }
      rows = rows.where((r) => !isSpacSignalRow(r)).toList();

      final groups = groupSignalRowsForDisplay(rows);
      final events = groups.map(_groupToCalendarEvent).whereType<CalendarEvent>().toList();
      return (events: events, error: null);
    } catch (e, st) {
      debugPrint('[StockSignals] fetchCalendarEvents: $e\n$st');
      final msg =
          e is PostgrestException && e.message.trim().isNotEmpty ? e.message : '$e';
      return (events: <CalendarEvent>[], error: msg);
    }
  }

  static CalendarEvent? _groupToCalendarEvent(List<Map<String, dynamic>> grp) {
    if (grp.isEmpty) return null;
    final sorted = grp;
    final row = sorted.first;
    final dateStr = '${row['date'] ?? ''}'.trim();
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;

    final multi = sorted.length > 1;
    final indicatorLabels = <String>{
      for (final r in sorted)
        '${r['signal_name'] ?? r['signal_type'] ?? ''}'.trim(),
    }.where((s) => s.isNotEmpty).toList()
      ..sort();

    final stock = '${row['name'] ?? ''}'.trim().isNotEmpty
        ? '${row['name']}'.trim()
        : '${row['code'] ?? ''}'.trim();
    final signalLabel =
        '${row['signal_name'] ?? row['signal_type'] ?? ''}'.trim();
    final title = multi
        ? stock
        : signalLabel.isNotEmpty
            ? '$stock $signalLabel'
            : stock;

    final codeKey = '${row['code'] ?? ''}'.trim().isNotEmpty
        ? '${row['code']}'.trim()
        : 'name:${'${row['name'] ?? ''}'.trim()}';
    final id = multi
        ? 'signal-$dateStr-$codeKey-${row['signal_category'] ?? '기타'}-merged'
        : 'signal-$dateStr-${row['code']}-${row['signal_type']}';

    final startsAt = DateTime(y, m, d);
    final endsAt = DateTime(y, m, d, 23, 59);

    final serializedRows = sorted.map(Map<String, dynamic>.from).toList();

    return CalendarEvent(
      id: id,
      title: title.trim().isEmpty ? '매수 시그널' : title.trim(),
      memo: null,
      recurrenceType: 'none',
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: true,
      color: _categoryColor('${row['signal_category'] ?? ''}'.trim()),
      creatorId: CalendarEvent.kExternalCreatorId,
      creatorNickname: '매수 시그널',
      groupIds: [],
      eventKind: 'schedule',
      externalSource: _externalSourceForRow(row),
      externalRaw: {
        'indicator_labels': indicatorLabels,
        'merged_rows': serializedRows,
        'is_merged': multi,
        'date': dateStr,
        'region': isCryptoSignalRow(row)
            ? 'crypto'
            : (isKrSignalRow(row) ? 'kr' : 'us'),
      },
    );
  }
}
