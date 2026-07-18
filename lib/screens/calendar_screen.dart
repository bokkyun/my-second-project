import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event.dart';
import '../utils/event_display_color.dart';
import '../utils/modal_guard.dart';
import '../utils/reb_apt_sply_api.dart';
import '../utils/dart_ipo_api.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/push_messaging_service.dart';
import '../services/buy_signal_type_prefs.dart';
import '../services/calendar_layer_prefs.dart';
import '../services/economic_calendar_service.dart';
import '../services/stock_signals_service.dart';
import '../services/widget_sync_service.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_search_sheet.dart';
import '../widgets/group_info_sheet.dart';
import '../widgets/day_schedule_sheet.dart';
import '../widgets/calendar_signal_chip_leading.dart';
import '../models/stock_day_profit.dart';
import '../services/expense_calendar_service.dart';
import '../services/expense_service.dart';
import '../services/stock_trade_calendar_service.dart';
import '../services/stock_trade_save_service.dart';
import '../services/monthly_summary_service.dart';
import '../services/stock_stats_service.dart';
import '../widgets/calendar_day_cell_profit.dart';
import '../widgets/receipt_uploader_sheet.dart';
import '../widgets/stock_uploader_sheet.dart';

const Color _kFinanceRed = Color(0xFFc62828);

String _financeCountChip(String prefix, int count) =>
    calendarEventChipLabel('$prefix$count건');

/// 달력 셀 칸 너비에 맞춘 최대 글자 수(유니코드 grapheme)
const int _kCalendarChipMaxChars = 5;
String calendarEventChipLabel(String title) {
  final t = title.trim();
  if (t.isEmpty) return '·';
  final ch = t.characters;
  if (ch.length <= _kCalendarChipMaxChars) return ch.toString();
  return ch.take(_kCalendarChipMaxChars).toString();
}

String _compactExternalChipLabel(String prefix, int count) {
  final raw = '$prefix$count';
  final ch = raw.characters;
  if (ch.length <= _kCalendarChipMaxChars) return raw;
  return ch.take(_kCalendarChipMaxChars).toString();
}

bool calendarIsSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isCalendarWeekend(DateTime day) =>
    day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

Color? _calendarDayNumberColor(DateTime day, {required bool outside}) {
  final Color? base;
  if (day.weekday == DateTime.sunday) {
    base = const Color(0xFFE53935);
  } else if (day.weekday == DateTime.saturday) {
    base = const Color(0xFF1E88E5);
  } else {
    return null;
  }
  return outside ? base.withValues(alpha: 0.45) : base;
}

/// 주말(일·토) 칸은 좁아서 날짜를 한 자리씩 세로로 표시
Widget _buildCalendarDayNumber(DateTime day, TextStyle baseStyle) {
  final digits = '${day.day}';
  if (!_isCalendarWeekend(day)) {
    return Text(digits, style: baseStyle);
  }
  final verticalStyle = baseStyle.copyWith(
    fontSize: 11,
    height: 0.9,
    letterSpacing: 0,
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final d in digits.characters)
        Text(
          d,
          style: verticalStyle,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
    ],
  );
}

bool _isDayInFocusedMonth(DateTime day, DateTime focused) =>
    day.year == focused.year && day.month == focused.month;

class _MoneyCalAiTitle extends StatelessWidget {
  const _MoneyCalAiTitle();

  static const _aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C4DFF),
      Color(0xFF00BCD4),
      Color(0xFF00E676),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 21,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.42,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MoneyCal', style: baseStyle),
        ShaderMask(
          shaderCallback: (bounds) => _aiGradient.createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            'AI',
            style: baseStyle.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

/// 0: 사용자 일정 · 1: 청약 · 2: 공모주(DART) · 3: 매수 시그널 · 4~: 거시 등 기타 외부
int _calendarEventKindOrder(CalendarEvent e) {
  if (ExpenseCalendarService.isExpenseEvent(e) ||
      StockTradeCalendarService.isStockTradeEvent(e)) {
    return 0;
  }
  if (!e.isExternal) return 0;
  final s = e.externalSource ?? '';
  if (s == 'reb-apt' || s == 'reb-odcloud') return 1;
  if (s == 'ipo') return 2;
  if (s == 'stock-signal' ||
      s == 'stock-signal-kr' ||
      s == 'stock-signal-us' ||
      s == 'stock-signal-crypto') return 3;
  if (s == 'fred' || s == 'bok') return 4;
  if (s == 'monthly-expense' || s == 'monthly-stock-profit') return 5;
  return 6;
}

const double _kEventBarHeight = 20;
const double _kEventBarGap = 1.5;
const int _kMaxSingleDayBarsShown = 7;
/// 날짜 숫자 영역(대략) + 셀 아래 여백
const double _kCalendarDayHeaderHeight = 24;
const double _kMoreLineHeight = 14;
const double _kWeekRowBottomPad = 3;
/// 일정이 거의 없을 때도 셀 높이가 너무 줄어들지 않도록 하는 최소 이벤트 영역
const double _kMinWeekRowEventAreaHeight = 20;
/// 주말 칸을 줄이고 평일 칸을 넓혀 월~금 일정 요약 텍스트 공간을 확보.
const List<int> _kCalendarColumnFlexes = [5, 13, 13, 13, 13, 13, 5];

class _WeekMultiSegment {
  _WeekMultiSegment({
    required this.event,
    required this.startCol,
    required this.endCol,
    required this.continuesFromPrevWeek,
    required this.continuesToNextWeek,
  });

  final CalendarEvent event;
  final int startCol;
  final int endCol;
  final bool continuesFromPrevWeek;
  final bool continuesToNextWeek;
  int lane = 0;
}

class _DayGridItem {
  const _DayGridItem({
    required this.title,
    required this.color,
    required this.order,
    this.chipLabel,
    this.externalChipKind,
  });

  factory _DayGridItem.fromEvent(CalendarEvent event, Color color) {
    return _DayGridItem(
      title: event.displayTitle,
      color: color,
      order: _calendarEventKindOrder(event),
    );
  }

  final String title;
  final Color color;
  final int order;
  /// 셀 칩에 쓸 짧은 라벨(외부 일정 요약). null이면 [title]을 잘라 표시.
  final String? chipLabel;
  /// 외부 일정 칩 — 아이콘 + 짧은 라벨(숫자 없음)
  final CalendarExternalChipKind? externalChipKind;
}

class _DayGridItemsSplit {
  const _DayGridItemsSplit({
    required this.userItems,
    required this.externalItems,
  });

  final List<_DayGridItem> userItems;
  final List<_DayGridItem> externalItems;

  int get totalCount => userItems.length + externalItems.length;
}

class _ExternalDaySummarySpec {
  const _ExternalDaySummarySpec({
    required this.key,
    required this.label,
    required this.color,
    required this.order,
  });

  final String key;
  final String label;
  final Color color;
  final int order;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.initialOpenEventId,
    this.initialDate,
  });

  /// 푸시 탭 등으로 열 이벤트 id
  final String? initialOpenEventId;

  /// 홈 위젯 날짜 탭 등 (yyyy-MM-dd)
  final String? initialDate;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  List<Group> _groups = [];
  Set<String> _visibleGroupIds = {};
  bool _onlyMySchedules = false;
  List<CalendarEvent> _events = [];
  List<CalendarEvent>? _allVisibleEventsCache;
  final Map<String, List<CalendarEvent>> _eventsForDayCache = {};
  final Map<String, List<CalendarEvent>> _singleDayEventsCache = {};
  final Map<String, _DayGridItemsSplit> _dayGridItemsCache = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _nickname;
  bool _loadingGroups = true;
  String? _pendingEventId;

  RealtimeChannel? _realtimeChannel;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _realtimeDebounce;
  Timer? _signalRealtimeDebounce;
  Timer? _pollTimer;
  Timer? _signalPollTimer;
  Timer? _widgetSyncDebounce;

  /// 한국부동산원 청약홈(공공데이터) — 드로어에서 끄면 요청 없음
  bool _showRebAptSply = true;
  List<CalendarEvent> _rebAptEvents = [];
  bool _rebAptLoading = false;
  String? _rebAptError;

  /// Open DART 증권신고(지분증권) 공시 제출일만
  bool _showDartIpo = false;
  List<CalendarEvent> _dartIpoEvents = [];
  bool _dartIpoLoading = false;
  String? _dartIpoError;
  int _dartIpoCacheYm = 0; // YYYY*100+MM — 같은 달이면 재요청 생략
  String? _appVersionLabel;

  /// 미국 FRED/ISM PMI (Supabase + Edge Function 동기화)
  bool _showFred = true;
  List<CalendarEvent> _fredEvents = [];
  bool _fredLoading = false;
  String? _fredError;

  /// 한국은행 통계 공표일정 (`fetch-bok-releases`)
  bool _showBok = true;
  List<CalendarEvent> _bokEvents = [];
  bool _bokLoading = false;
  String? _bokError;

  /// 매수 시그널 (`signals`) — 국내·미국·코인 분리 표시
  bool _showKrStockSignals = true;
  bool _showUsStockSignals = true;
  bool _showCryptoStockSignals = false;
  List<CalendarEvent> _stockSignalEvents = [];
  bool _stockSignalLoading = false;
  String? _stockSignalError;
  Set<String> _enabledBuySignalTypes = BuySignalTypePrefs.defaultEnabled;

  /// `stock_trades` 일별 실현손익 (국내/해외)
  Map<String, StockDayProfit> _dailyStockProfits = {};

  /// 월말 지출·주식 수익 합계 일정 (실시간 집계)
  List<CalendarEvent> _monthlySummaryEvents = [];

  /// 날짜별 지출 (expenses)
  List<CalendarEvent> _expenseEvents = [];

  /// 날짜별 체결 (stock_trades)
  List<CalendarEvent> _stockTradeEvents = [];

  List<CalendarEvent> get _krStockSignalEvents => _stockSignalEvents
      .where(StockSignalsService.isKrSignalEvent)
      .toList(growable: false);

  List<CalendarEvent> get _usStockSignalEvents => _stockSignalEvents
      .where(StockSignalsService.isUsSignalEvent)
      .toList(growable: false);

  List<CalendarEvent> get _cryptoStockSignalEvents => _stockSignalEvents
      .where(StockSignalsService.isCryptoSignalEvent)
      .toList(growable: false);

  bool get _anyStockSignalLayerOn =>
      _showKrStockSignals || _showUsStockSignals || _showCryptoStockSignals;

  String _cacheDayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  void _clearCalendarCaches() {
    _allVisibleEventsCache = null;
    _eventsForDayCache.clear();
    _singleDayEventsCache.clear();
    _dayGridItemsCache.clear();
  }

  bool _eventsShallowEqual(List<CalendarEvent> a, List<CalendarEvent> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].startsAt != b[i].startsAt ||
          a[i].endsAt != b[i].endsAt ||
          a[i].title != b[i].title) {
        return false;
      }
    }
    return true;
  }

  StockSignalLayerFilter get _stockSignalLayerFilter => StockSignalLayerFilter(
        includeKr: _showKrStockSignals,
        includeUs: _showUsStockSignals,
        includeCrypto: _showCryptoStockSignals,
      );

  void _scheduleHomeWidgetSync() {
    _widgetSyncDebounce?.cancel();
    _widgetSyncDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) unawaited(_syncHomeWidget());
    });
  }

  DateTime? _parseInitialDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return DateTime.tryParse(raw);
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _syncHomeWidget() async {
    try {
      await WidgetSyncService.syncCalendarEvents(
        _allVisibleEvents,
        groups: _groups,
        currentUserId: AuthService.currentUser?.id,
      );
    } catch (e) {
      debugPrint('[CalendarScreen] widget sync error: $e');
    }
  }

  Color _eventDisplayColor(CalendarEvent event) => eventDisplayColor(
        event,
        groups: _groups,
        currentUserId: AuthService.currentUser?.id,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = _parseInitialDate(widget.initialDate);
    _focusedDay = initial ?? DateTime.now();
    _selectedDay = initial ?? DateTime.now();
    _pendingEventId = widget.initialOpenEventId;
    _loadAll();
    unawaited(_loadLayerPrefs());
    unawaited(_loadAppVersion());
    unawaited(_refreshStockProfits());
    unawaited(_refreshMonthlySummaries());
    unawaited(_refreshExpenses());
    unawaited(_refreshStockTrades());
    _loadProfile();
    _subscribeCalendarRealtime();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      unawaited(_refreshMonthlySummaries());
      unawaited(_refreshExpenses());
      unawaited(_refreshStockTrades());
      unawaited(_refreshStockProfits());
    });
    if (widget.initialDate != null && initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDaySchedulePopup(initial);
      });
    }
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) {
        unawaited(_refreshEventsQuietly());
        unawaited(_refreshMonthlySummaries());
        unawaited(_refreshExpenses());
    unawaited(_refreshStockTrades());
      }
    });
    _signalPollTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _anyStockSignalLayerOn) {
        unawaited(_refreshStockSignalsLayer(showGlobalLoading: false, forceRefresh: true));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeDebounce?.cancel();
    _signalRealtimeDebounce?.cancel();
    _pollTimer?.cancel();
    _signalPollTimer?.cancel();
    _widgetSyncDebounce?.cancel();
    unawaited(_authSubscription?.cancel());
    _unsubscribeCalendarRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshEventsQuietly());
      if (_showRebAptSply) unawaited(_fetchRebAptEvents());
      if (_showFred || _showBok) unawaited(_refreshEconomicLayers());
      if (_anyStockSignalLayerOn) {
        unawaited(_refreshStockSignalsLayer(showGlobalLoading: false, forceRefresh: true));
      }
      unawaited(_refreshStockProfits());
      unawaited(_refreshMonthlySummaries());
      unawaited(_refreshExpenses());
    unawaited(_refreshStockTrades());
      unawaited(WidgetSyncService.requestWidgetRefresh());
    }
  }

  void _subscribeCalendarRealtime() {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return;
    try {
      _unsubscribeCalendarRealtime();
      final client = Supabase.instance.client;
      _realtimeChannel = client
          .channel('calendar-sync-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) => _debouncedEventsRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'event_visibility',
            callback: (_) => _debouncedEventsRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'signals',
            callback: (_) => _debouncedSignalsRefresh(),
          );
      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('[CalendarScreen] Realtime subscription failed: $e');
    }
  }

  void _unsubscribeCalendarRealtime() {
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch != null) {
      try {
        unawaited(Supabase.instance.client.removeChannel(ch));
      } catch (_) {}
    }
  }

  void _debouncedEventsRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_refreshEventsQuietly());
    });
  }

  void _debouncedSignalsRefresh() {
    if (!_anyStockSignalLayerOn) return;
    _signalRealtimeDebounce?.cancel();
    _signalRealtimeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_anyStockSignalLayerOn) return;
      StockSignalsService.clearQueryCache();
      unawaited(_refreshStockSignalsLayer(showGlobalLoading: false, forceRefresh: true));
    });
  }

  /// ????? ?????? ???? ???? ???? (Realtime??????? ???)
  Future<void> _refreshEventsQuietly() async {
    if (!mounted) return;
    try {
      final events = await EventService.fetchEvents(
        AuthService.currentUser!.id, _visibleGroupIds.toList());
      if (!mounted) return;
      if (_eventsShallowEqual(events, _events)) return;
      setState(() {
        _events = events;
        _clearCalendarCaches();
      });
      try {
        await NotificationService.scheduleTodayEvents(events);
      } catch (e) {
        debugPrint('[CalendarScreen] notification schedule error: $e');
      }
      _scheduleHomeWidgetSync();
    } catch (e) {
      debugPrint('[CalendarScreen] _refreshEventsQuietly error: $e');
    }
  }

  Future<void> _loadProfile() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('nickname')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) setState(() => _nickname = p?['nickname'] as String?);
    } catch (_) {
      if (mounted) setState(() => _nickname = null);
    }
  }

  Future<void> _loadAll() async {
    await _loadGroups();
    await _loadEvents();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupService.fetchMyGroups(AuthService.currentUser!.id);
      if (mounted) {
        setState(() {
          _groups = groups;
          _visibleGroupIds = groups.map((g) => g.id).toSet();
          _loadingGroups = false;
          _clearCalendarCaches();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groups = [];
          _loadingGroups = false;
          _clearCalendarCaches();
        });
      }
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await EventService.fetchEvents(
          AuthService.currentUser!.id, _visibleGroupIds.toList());
      if (mounted) {
        setState(() {
          _events = events;
          _clearCalendarCaches();
        });
        try {
          await NotificationService.scheduleTodayEvents(events);
        } catch (e) {
          debugPrint('[CalendarScreen] notification schedule error: $e');
        }
        _scheduleHomeWidgetSync();
        await _runPendingNotificationActions();
      }
    } catch (e) {
      debugPrint('[CalendarScreen] _loadEvents error: $e');
      if (mounted) {
        setState(() {
          _events = [];
          _clearCalendarCaches();
        });
        try { await WidgetSyncService.syncCalendarEvents([]); } catch (_) {}
        try { await NotificationService.scheduleDailySummaryFromPrefs([]); } catch (_) {}
        await _runPendingNotificationActions();
      }
    }
  }

  /// ???? ?????: ????? ????? ??? ?????? ??????
  Future<void> _runPendingNotificationActions() async {
    if (!mounted) return;

    final eventId = _pendingEventId;
    if (eventId != null) {
      _pendingEventId = null;
      CalendarEvent? ev;
      for (final e in _allVisibleEvents) {
        if (e.id == eventId) {
          ev = e;
          break;
        }
      }
      if (ev == null &&
          !eventId.startsWith('reb-apt-') &&
          !eventId.startsWith('reb-od-') &&
          !eventId.startsWith('dart-ipo-') &&
          !eventId.startsWith('fred-') &&
          !eventId.startsWith('bok-') &&
          !eventId.startsWith('ism-pmi-')) {
        ev = await EventService.fetchEventById(eventId);
      }
      if (!mounted) return;
      context.go('/calendar');
      final toShow = ev;
      if (toShow != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openEventDetail(toShow);
          }
        });
      }
    }
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    final cacheKey = _cacheDayKey(day);
    final cached = _eventsForDayCache[cacheKey];
    if (cached != null) return cached;

    Iterable<CalendarEvent> list = _allVisibleEvents;
    if (_onlyMySchedules) {
      list = list.where(
        (e) =>
            !e.isExternal ||
            MonthlySummaryService.isSummaryEvent(e) ||
            ExpenseCalendarService.isExpenseEvent(e) ||
            StockTradeCalendarService.isStockTradeEvent(e),
      );
    }
    final result = list.where((e) {
      final start = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final end = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      final d = DateTime(day.year, day.month, day.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
    // ① 사용자 등록 ② 아파트 청약 ③ 공모주 순, 같은 묶음에서는 시작 시각
    result.sort((a, b) {
      final oa = _calendarEventKindOrder(a);
      final ob = _calendarEventKindOrder(b);
      if (oa != ob) return oa.compareTo(ob);
      return a.startsAt.compareTo(b.startsAt);
    });
    final frozen = List<CalendarEvent>.unmodifiable(result);
    _eventsForDayCache[cacheKey] = frozen;
    return frozen;
  }

  /// ???????? ?????? ?????? ??????? ?? ????????? ????
  bool _isAdminOfEvent(CalendarEvent event) {
    if (event.creatorId == AuthService.currentUser!.id) return false;
    return event.groupIds.any(
      (gid) => _groups.any((g) => g.id == gid && g.myRole == 'admin'),
    );
  }

  Future<void> _loadLayerPrefs() async {
    try {
      await _loadBuySignalTypePrefs();
      final s = await CalendarLayerPrefs.load();
      if (mounted) {
        setState(() {
          _onlyMySchedules = s.onlyMySchedules;
          _showRebAptSply = s.showRebApt;
          _showDartIpo = s.showDartIpo;
          _showKrStockSignals = s.showKrStockSignals;
          _showUsStockSignals = s.showUsStockSignals;
          _showCryptoStockSignals = s.showCryptoStockSignals;
          _showFred = s.showFred;
          _showBok = s.showBok;
          _clearCalendarCaches();
        });
      }
      await Future.wait([
        _fetchRebAptEvents(),
        _fetchDartIpoForFocusedMonth(),
        _refreshEconomicLayers(),
        _refreshStockSignalsLayer(),
      ]);
    } catch (e) {
      debugPrint('[CalendarScreen] _loadLayerPrefs: $e');
    } finally {
      if (mounted) _scheduleHomeWidgetSync();
    }
  }

  Future<void> _loadBuySignalTypePrefs() async {
    try {
      _enabledBuySignalTypes = await BuySignalTypePrefs.loadEnabled();
    } catch (e) {
      debugPrint('[CalendarScreen] _loadBuySignalTypePrefs: $e');
    }
  }

  Future<void> _openBuySignalTypeSettings() async {
    Navigator.pop(context);
    await context.push('/calendar/buy-signal-types');
    if (mounted) {
      await _loadBuySignalTypePrefs();
      await _refreshStockSignalsLayer();
    }
  }

  Future<void> _openLayerSettings() async {
    Navigator.pop(context);
    await context.push('/calendar/layer-settings');
    if (mounted) {
      await _loadLayerPrefs();
      _scheduleHomeWidgetSync();
    }
  }

  /// pubspec `version`이 앱 설정(Android versionName / versionCode 등)에 반영된 값
  Future<void> _loadAppVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersionLabel = 'v${p.version} (빌드 ${p.buildNumber})';
        });
      }
    } catch (e) {
      debugPrint('[CalendarScreen] _loadAppVersion: $e');
    }
  }

  Future<void> _fetchRebAptEvents({bool forceRefresh = false}) async {
    if (!_showRebAptSply) {
      if (mounted) {
        setState(() {
          _rebAptEvents = [];
          _rebAptError = null;
          _rebAptLoading = false;
          _clearCalendarCaches();
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _rebAptLoading = true;
        _rebAptError = null;
      });
    }
    final r = await fetchRebAptSplyList(forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      _rebAptLoading = false;
      _rebAptEvents = r.events;
      _rebAptError = r.error;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  Future<void> _setShowRebAptSply(bool value) async {
    setState(() {
      _showRebAptSply = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowRebApt(value);
    if (value) {
      clearRebAptSessionCache();
      await _fetchRebAptEvents(forceRefresh: true);
    } else {
      clearRebAptSessionCache();
      await _fetchRebAptEvents();
    }
  }

  (DateTime, DateTime) _monthRangeFor(DateTime d) {
    final start = DateTime(d.year, d.month, 1);
    final end = DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);
    return (start, end);
  }

  Future<void> _fetchDartIpoForFocusedMonth({bool invalidateCache = false}) async {
    if (!_showDartIpo) {
      if (mounted) {
        setState(() {
          _dartIpoEvents = [];
          _dartIpoError = null;
          _dartIpoLoading = false;
          _clearCalendarCaches();
        });
      }
      return;
    }
    final (start, end) = _monthRangeFor(_focusedDay);
    final ym = _focusedDay.year * 100 + _focusedDay.month;
    if (invalidateCache) clearDartIpoCache(ym);
    if (mounted) {
      setState(() {
        _dartIpoLoading = true;
        _dartIpoError = null;
      });
    }
    final r = await fetchDartIpoList(start, end);
    if (!mounted) return;
    setState(() {
      _dartIpoLoading = false;
      _dartIpoEvents = r.events;
      _dartIpoError = r.error;
      _dartIpoCacheYm = ym;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
    // 다음 달도 백그라운드로 미리 가져오기 (캐시 적중 시 페이지 전환이 즉시)
    final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1);
    final (ns, ne) = _monthRangeFor(nextMonth);
    unawaited(fetchDartIpoList(ns, ne));
  }

  Future<void> _setShowDartIpo(bool value) async {
    setState(() {
      _showDartIpo = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowDartIpo(value);
    await _fetchDartIpoForFocusedMonth();
  }

  Future<void> _refreshEconomicLayers({bool showGlobalLoading = true}) async {
    final days = _monthGridDays(_focusedDay);
    final range = EconomicCalendarService.paddedRangeForGrid(
      gridFirstDay: days.first,
      gridLastDay: days.last,
    );
    if (showGlobalLoading && mounted) {
      setState(() {
        _fredLoading = _showFred;
        _bokLoading = _showBok;
        if (_showFred) _fredError = null;
        if (_showBok) _bokError = null;
      });
    }
    final fr = _showFred
        ? await EconomicCalendarService.fetchFredEvents(
            rangeFrom: range.$1,
            rangeTo: range.$2,
          )
        : (events: <CalendarEvent>[], error: null);
    final br = _showBok
        ? await EconomicCalendarService.fetchBokEvents(
            rangeFrom: range.$1,
            rangeTo: range.$2,
          )
        : (events: <CalendarEvent>[], error: null);
    if (!mounted) return;
    setState(() {
      _fredLoading = false;
      _bokLoading = false;
      _fredEvents = _showFred ? fr.events : [];
      _fredError = _showFred ? fr.error : null;
      _bokEvents = _showBok ? br.events : [];
      _bokError = _showBok ? br.error : null;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  Future<void> _setShowFred(bool value) async {
    setState(() {
      _showFred = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowFred(value);
    await _refreshEconomicLayers();
  }

  Future<void> _setShowBok(bool value) async {
    setState(() {
      _showBok = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowBok(value);
    await _refreshEconomicLayers();
  }

  Future<void> _setShowKrStockSignals(bool value) async {
    setState(() {
      _showKrStockSignals = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowKrStockSignals(value);
    await _refreshStockSignalsLayer();
  }

  Future<void> _setShowUsStockSignals(bool value) async {
    setState(() {
      _showUsStockSignals = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowUsStockSignals(value);
    await _refreshStockSignalsLayer();
  }

  Future<void> _setShowCryptoStockSignals(bool value) async {
    setState(() {
      _showCryptoStockSignals = value;
      _clearCalendarCaches();
    });
    await CalendarLayerPrefs.saveShowCryptoStockSignals(value);
    await _refreshStockSignalsLayer();
  }

  Future<void> _refreshStockSignalsLayer({
    bool showGlobalLoading = true,
    bool forceRefresh = false,
  }) async {
    await _loadBuySignalTypePrefs();
    if (!_anyStockSignalLayerOn) {
      if (mounted) {
        setState(() {
          _stockSignalEvents = [];
          _stockSignalError = null;
          _stockSignalLoading = false;
          _clearCalendarCaches();
        });
      }
      return;
    }
    final days = _monthGridDays(_focusedDay);
    if (showGlobalLoading && mounted) {
      setState(() {
        _stockSignalLoading = true;
        _stockSignalError = null;
      });
    }
    final r = await StockSignalsService.fetchCalendarEvents(
      gridFirstDay: days.first,
      gridLastDay: days.last,
      enabledSignalTypes: _enabledBuySignalTypes,
      layerFilter: _stockSignalLayerFilter,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _stockSignalLoading = false;
      _stockSignalEvents = r.events;
      _stockSignalError = r.error;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  /// Supabase + (옵션) 청약홈·DART 외부 일정
  List<CalendarEvent> get _allVisibleEvents {
    final cached = _allVisibleEventsCache;
    if (cached != null) return cached;

    var out = List<CalendarEvent>.from(_events);
    if (_showRebAptSply) out = [...out, ..._rebAptEvents];
    if (_showDartIpo) out = [...out, ..._dartIpoEvents];
    if (_showKrStockSignals) out = [...out, ..._krStockSignalEvents];
    if (_showUsStockSignals) out = [...out, ..._usStockSignalEvents];
    if (_showCryptoStockSignals) out = [...out, ..._cryptoStockSignalEvents];
    if (_showFred) out = [...out, ..._fredEvents];
    if (_showBok) out = [...out, ..._bokEvents];
    out = [...out, ..._expenseEvents];
    out = [...out, ..._stockTradeEvents];
    out = [...out, ..._monthlySummaryEvents];
    final frozen = List<CalendarEvent>.unmodifiable(out);
    _allVisibleEventsCache = frozen;
    return frozen;
  }

  void _openEventForm({DateTime? date, CalendarEvent? editEvent}) {
    final adminGroupIds = _groups
        .where((g) => g.myRole == 'admin')
        .map((g) => g.id)
        .toSet();

    ModalGuard.showBottomSheet(
      context: context,
      guardKey: 'event-form:${editEvent?.id ?? _cacheDayKey(date ?? DateTime.now())}',
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventFormSheet(
        defaultDate: date,
        editEvent: editEvent,
        groups: _groups,
        adminGroupIds: editEvent == null ? adminGroupIds : const {},
        onFetchMembers: editEvent == null ? GroupService.fetchGroupMembers : null,
        onSave: ({required title, memo, location, url, required recurrenceType, required startsAt, required endsAt, required isAllDay, required color, required groupIds, String? targetUserId, required eventKind}) async {
          final currentUserId = AuthService.currentUser!.id;
          if (editEvent != null) {
            await EventService.updateEvent(
              eventId: editEvent.id, userId: currentUserId,
              title: title, memo: memo, location: location, url: url,
              recurrenceType: recurrenceType,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
              isAdminOverride: _isAdminOfEvent(editEvent),
              eventKind: eventKind,
            );
          } else {
            await EventService.createEvent(
              userId: currentUserId, title: title, memo: memo,
              location: location, url: url, recurrenceType: recurrenceType,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
              eventKind: eventKind, targetUserId: targetUserId,
            );
          }
          await _loadEvents();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(editEvent != null ? '일정이 수정되었습니다.' : '일정이 저장되었습니다!')));
          }
        },
      ),
    );
  }

  Future<void> _confirmAndDeleteEvent(CalendarEvent event) async {
    final isExpense = ExpenseCalendarService.isExpenseEvent(event);
    final isStockTrade = StockTradeCalendarService.isStockTradeEvent(event);

    final title = isExpense
        ? '지출 삭제'
        : isStockTrade
            ? '매매 삭제'
            : '일정 삭제';
    final content = isExpense
        ? '이 지출 기록을 삭제하시겠습니까?'
        : isStockTrade
            ? '이 매매 기록을 삭제하시겠습니까?'
            : '\'${event.title}\' 일정을 삭제하시겠습니까?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final userId = AuthService.currentUser!.id;
      if (isExpense) {
        final id = ExpenseCalendarService.recordIdFromEvent(event);
        if (id == null) throw StateError('기록 ID를 찾을 수 없습니다.');
        await ExpenseService.deleteExpense(userId: userId, expenseId: id);
        await _refreshExpenses();
        await _refreshMonthlySummaries();
      } else if (isStockTrade) {
        final id = StockTradeCalendarService.recordIdFromEvent(event);
        if (id == null) throw StateError('기록 ID를 찾을 수 없습니다.');
        await StockTradeSaveService.deleteStockTrade(
          userId: userId,
          tradeId: id,
        );
        await _refreshStockTrades();
        await _refreshMonthlySummaries();
        await _refreshStockProfits();
      } else {
        await EventService.deleteEvent(
          event.id,
          userId,
          isAdminOverride: _isAdminOfEvent(event),
        );
        await _loadEvents();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isExpense
                  ? '지출이 삭제되었습니다.'
                  : isStockTrade
                      ? '매매 기록이 삭제되었습니다.'
                      : '일정이 삭제되었습니다.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제에 실패했습니다: $e')),
        );
      }
    }
  }

  void _openEventDetail(CalendarEvent event) {
    ModalGuard.showBottomSheet(
      context: context,
      guardKey: 'event-detail:${event.id}',
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailSheet(
        event: event,
        groups: _groups,
        currentUserId: AuthService.currentUser!.id,
        onEdit: () {
          Navigator.pop(context);
          _openEventForm(editEvent: event);
        },
        onDelete: () async {
          Navigator.pop(context);
          await _confirmAndDeleteEvent(event);
        },
      ),
    );
  }

  void _showDaySchedulePopup(DateTime day) {
    final list = _eventsForDay(day);
    ModalGuard.showBottomSheet<void>(
      context: context,
      guardKey: 'day-schedule:${_cacheDayKey(day)}',
      isScrollControlled: true,
      useSafeArea: false,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DayScheduleSheet(
        day: day,
        events: list,
        groups: _groups,
        currentUserId: AuthService.currentUser?.id,
        onEventTap: (ev) {
          Navigator.pop(sheetContext);
          _openEventDetail(ev);
        },
        onAddEvent: () {
          Navigator.pop(sheetContext);
          _openEventForm(date: day);
        },
      ),
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _monthGridDays(DateTime focused) {
    final first = DateTime(focused.year, focused.month, 1);
    final leading = first.weekday % 7;
    final start = first.subtract(Duration(days: leading));
    return List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
  }

  List<CalendarEvent> _singleDayEventsForDay(DateTime day) {
    final cacheKey = _cacheDayKey(day);
    final cached = _singleDayEventsCache[cacheKey];
    if (cached != null) return cached;

    final result = _eventsForDay(day).where((e) {
      final s = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final ed = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      return s == ed;
    }).toList();
    final frozen = List<CalendarEvent>.unmodifiable(result);
    _singleDayEventsCache[cacheKey] = frozen;
    return frozen;
  }

  _ExternalDaySummarySpec _externalSummarySpec(CalendarEvent event) {
    final source = event.externalSource ?? '';
    if (source == 'reb-apt' || source == 'reb-odcloud') {
      return const _ExternalDaySummarySpec(
        key: 'reb-apt',
        label: '아파트청약',
        color: Color(0xFF1565C0),
        order: 1,
      );
    }
    if (source == 'ipo') {
      return const _ExternalDaySummarySpec(
        key: 'ipo',
        label: '공모주청약',
        color: Color(0xFF1B8E3E),
        order: 2,
      );
    }
    if (source == 'stock-signal' || source == 'stock-signal-kr') {
      return const _ExternalDaySummarySpec(
        key: 'stock-signal-kr',
        label: '국내매수',
        color: kBuySignalColor,
        order: 3,
      );
    }
    if (source == 'stock-signal-us') {
      return const _ExternalDaySummarySpec(
        key: 'stock-signal-us',
        label: '미국매수',
        color: kBuySignalColor,
        order: 3,
      );
    }
    if (source == 'stock-signal-crypto') {
      return const _ExternalDaySummarySpec(
        key: 'stock-signal-crypto',
        label: '코인매수',
        color: kBuySignalColor,
        order: 3,
      );
    }
    if (source == 'fred') {
      return const _ExternalDaySummarySpec(
        key: 'fred',
        label: '미국지표',
        color: Color(0xFF6A1B9A),
        order: 4,
      );
    }
    if (source == 'bok') {
      return const _ExternalDaySummarySpec(
        key: 'bok',
        label: '한은일정',
        color: Color(0xFF0D47A1),
        order: 5,
      );
    }
    return const _ExternalDaySummarySpec(
      key: 'external',
      label: '외부일정',
      color: Color(0xFF455A64),
      order: 6,
    );
  }

  CalendarExternalChipKind? _externalChipKindForKey(String key) {
    switch (key) {
      case 'stock-signal-kr':
        return CalendarExternalChipKind.krSignal;
      case 'stock-signal-us':
        return CalendarExternalChipKind.usSignal;
      case 'stock-signal-crypto':
        return CalendarExternalChipKind.cryptoSignal;
      case 'reb-apt':
        return CalendarExternalChipKind.apt;
      case 'ipo':
        return CalendarExternalChipKind.ipo;
      default:
        return null;
    }
  }

  String _externalSummaryChipTitle(String key, int count) {
    switch (key) {
      case 'reb-apt':
        return '청약일정';
      case 'ipo':
        return '공모주';
      case 'stock-signal':
      case 'stock-signal-kr':
      case 'stock-signal-us':
      case 'stock-signal-crypto':
        return '시그널';
      case 'fred':
        return _compactExternalChipLabel('미국', count);
      case 'bok':
        return _compactExternalChipLabel('한은', count);
      default:
        return _compactExternalChipLabel('외부', count);
    }
  }

  _DayGridItemsSplit _dayGridItemsSplitForDay(DateTime day, DateTime focusedMonth) {
    if (!_isDayInFocusedMonth(day, focusedMonth)) {
      return const _DayGridItemsSplit(userItems: [], externalItems: []);
    }
    final cacheKey = _cacheDayKey(day);
    final cached = _dayGridItemsCache[cacheKey];
    if (cached != null) return cached;

    final internalEvents = _singleDayEventsForDay(day)
        .where(
          (e) =>
              !e.isExternal ||
              MonthlySummaryService.isSummaryEvent(e),
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final expenseEvents =
        _eventsForDay(day).where(ExpenseCalendarService.isExpenseEvent).toList();
    final tradeEvents = _eventsForDay(day)
        .where(StockTradeCalendarService.isStockTradeEvent)
        .toList();

    final userItems = <_DayGridItem>[
      for (final e in internalEvents)
        _DayGridItem.fromEvent(e, _eventDisplayColor(e)),
      if (expenseEvents.isNotEmpty)
        _DayGridItem(
          title: '지출 ${expenseEvents.length}건',
          chipLabel: _financeCountChip('지출', expenseEvents.length),
          color: _kFinanceRed,
          order: 1,
        ),
      if (tradeEvents.isNotEmpty)
        _DayGridItem(
          title: '매매 ${tradeEvents.length}건',
          chipLabel: _financeCountChip('매매', tradeEvents.length),
          color: _kFinanceRed,
          order: 1,
        ),
      for (final e in _eventsForDay(day)
          .where(MonthlySummaryService.isSummaryEvent))
        _dayGridItemForEvent(e),
    ];

    final counts = <String, int>{};
    final specs = <String, _ExternalDaySummarySpec>{};
    for (final event in _eventsForDay(day).where(
      (e) =>
          e.isExternal &&
          !MonthlySummaryService.isSummaryEvent(e) &&
          !ExpenseCalendarService.isExpenseEvent(e) &&
          !StockTradeCalendarService.isStockTradeEvent(e),
    )) {
      final spec = _externalSummarySpec(event);
      counts[spec.key] = (counts[spec.key] ?? 0) + 1;
      specs[spec.key] = spec;
    }

    final externalItems = specs.values.map((spec) {
      final count = counts[spec.key] ?? 0;
      final chipKind = _externalChipKindForKey(spec.key);
      return _DayGridItem(
        title: _externalSummaryChipTitle(spec.key, count),
        chipLabel: chipKind == null
            ? _externalSummaryChipTitle(spec.key, count)
            : null,
        externalChipKind: chipKind,
        color: spec.color,
        order: spec.order,
      );
    }).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final result = _DayGridItemsSplit(
      userItems: List<_DayGridItem>.unmodifiable(userItems),
      externalItems: List<_DayGridItem>.unmodifiable(externalItems),
    );
    _dayGridItemsCache[cacheKey] = result;
    return result;
  }

  List<_WeekMultiSegment> _multiDaySegmentsForWeek(
    List<DateTime> weekDays,
    DateTime focusedMonth,
  ) {
    final w0 = _dateOnly(weekDays.first);
    final w6 = _dateOnly(weekDays.last);
    final byId = <String, _WeekMultiSegment>{};

    for (var i = 0; i < 7; i++) {
      if (!_isDayInFocusedMonth(weekDays[i], focusedMonth)) continue;
      for (final e in _eventsForDay(weekDays[i])) {
        if (e.isExternal) continue;
        final s = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
        final ed = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
        if (ed.isBefore(s) || s == ed) continue;
        if (ed.isBefore(w0) || s.isAfter(w6)) continue;
        final segS = s.isBefore(w0) ? w0 : s;
        final segE = ed.isAfter(w6) ? w6 : ed;
        int? sc;
        int? ec;
        for (var j = 0; j < 7; j++) {
          final wd = _dateOnly(weekDays[j]);
          if (wd == segS) sc = j;
          if (wd == segE) ec = j;
        }
        if (sc == null || ec == null) continue;
        int? clipSc;
        int? clipEc;
        for (var j = sc; j <= ec; j++) {
          if (_isDayInFocusedMonth(weekDays[j], focusedMonth)) {
            clipSc ??= j;
            clipEc = j;
          }
        }
        if (clipSc == null || clipEc == null) continue;
        byId[e.id] = _WeekMultiSegment(
          event: e,
          startCol: clipSc,
          endCol: clipEc,
          continuesFromPrevWeek: s.isBefore(_dateOnly(weekDays[clipSc])),
          continuesToNextWeek: ed.isAfter(_dateOnly(weekDays[clipEc])),
        );
      }
    }
    return byId.values.toList();
  }

  void _assignWeekLanes(List<_WeekMultiSegment> segments) {
    segments.sort((a, b) {
      final k = _calendarEventKindOrder(a.event).compareTo(_calendarEventKindOrder(b.event));
      if (k != 0) return k;
      final t = a.event.startsAt.compareTo(b.event.startsAt);
      if (t != 0) return t;
      if (a.startCol != b.startCol) return a.startCol.compareTo(b.startCol);
      final al = a.endCol - a.startCol;
      final bl = b.endCol - b.startCol;
      return bl.compareTo(al);
    });
    final occupied = <List<bool>>[];
    for (final seg in segments) {
      var laneIdx = 0;
      while (true) {
        while (laneIdx >= occupied.length) {
          occupied.add(List<bool>.filled(7, false));
        }
        var ok = true;
        for (var c = seg.startCol; c <= seg.endCol; c++) {
          if (occupied[laneIdx][c]) {
            ok = false;
            break;
          }
        }
        if (ok) {
          for (var c = seg.startCol; c <= seg.endCol; c++) {
            occupied[laneIdx][c] = true;
          }
          seg.lane = laneIdx;
          break;
        }
        laneIdx++;
      }
    }
  }

  double _weekMultiLaneBarPitch() => _kEventBarHeight + _kEventBarGap;

  Widget _buildSingleDayEventBar(_DayGridItem item) {
    final color = item.color;
    return Padding(
      padding: const EdgeInsets.only(left: 0.5, right: 0.5, bottom: 1.5),
      child: Container(
        height: _kEventBarHeight,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        alignment: Alignment.centerLeft,
        child: item.externalChipKind != null
            ? CalendarExternalChipLabel(kind: item.externalChipKind!)
            : Text(
                item.chipLabel ?? calendarEventChipLabel(item.title),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                ),
              ),
      ),
    );
  }

  void _onMonthChangedByNav() {
    final ym = _focusedDay.year * 100 + _focusedDay.month;
    if (_showDartIpo && ym != _dartIpoCacheYm) {
      unawaited(_fetchDartIpoForFocusedMonth());
    }
    if (_showFred || _showBok) {
      unawaited(_refreshEconomicLayers());
    }
    if (_anyStockSignalLayerOn) {
      unawaited(_refreshStockSignalsLayer());
    }
    unawaited(_refreshStockProfits());
    unawaited(_refreshMonthlySummaries());
    unawaited(_refreshExpenses());
    unawaited(_refreshStockTrades());
  }

  Future<void> _refreshExpenses() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _expenseEvents = [];
          _clearCalendarCaches();
        });
      }
      return;
    }
    final days = _monthGridDays(_focusedDay);
    final res = await ExpenseCalendarService.fetchCalendarEvents(
      userId: uid,
      gridFirstDay: days.first,
      gridLastDay: days.last,
    );
    if (!mounted) return;
    if (res.error != null) {
      debugPrint('[CalendarScreen] expenses: ${res.error}');
    }
    setState(() {
      _expenseEvents = res.events;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  Future<void> _refreshStockTrades() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _stockTradeEvents = [];
          _clearCalendarCaches();
        });
      }
      return;
    }
    final days = _monthGridDays(_focusedDay);
    final res = await StockTradeCalendarService.fetchCalendarEvents(
      userId: uid,
      gridFirstDay: days.first,
      gridLastDay: days.last,
    );
    if (!mounted) return;
    if (res.error != null) {
      debugPrint('[CalendarScreen] stock trades: ${res.error}');
    }
    setState(() {
      _stockTradeEvents = res.events;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  Future<void> _refreshMonthlySummaries() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _monthlySummaryEvents = [];
          _clearCalendarCaches();
        });
      }
      return;
    }
    final days = _monthGridDays(_focusedDay);
    final res = await MonthlySummaryService.fetchSummaryEvents(
      userId: uid,
      gridFirstDay: days.first,
      gridLastDay: days.last,
    );
    if (!mounted) return;
    if (res.error != null) {
      debugPrint('[CalendarScreen] monthly summaries: ${res.error}');
    }
    setState(() {
      _monthlySummaryEvents = res.events;
      _clearCalendarCaches();
    });
    _scheduleHomeWidgetSync();
  }

  String _monthlySummaryChipLabel(CalendarEvent event) {
    if (event.externalSource == 'monthly-expense') return '월지출';
    if (event.externalSource == 'monthly-stock-profit') return '월수익';
    return calendarEventChipLabel(event.title);
  }

  _DayGridItem _dayGridItemForEvent(CalendarEvent event) {
    return _DayGridItem(
      title: event.title,
      chipLabel: _monthlySummaryChipLabel(event),
      color: _eventDisplayColor(event),
      order: _calendarEventKindOrder(event),
    );
  }

  Future<void> _refreshStockProfits() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _dailyStockProfits = {});
      return;
    }
    final days = _monthGridDays(_focusedDay);
    final res = await StockStatsService.fetchDailyProfitsByRange(
      userId: uid,
      gridFirstDay: days.first,
      gridLastDay: days.last,
    );
    if (!mounted) return;
    if (res.error != null) {
      debugPrint('[CalendarScreen] stock profits: ${res.error}');
    }
    setState(() => _dailyStockProfits = res.byDate);
  }

  StockDayProfit _stockProfitForDay(DateTime day) =>
      _dailyStockProfits[_cacheDayKey(day)] ?? StockDayProfit.empty;

  bool _isPinnedFinanceItem(_DayGridItem item) {
    final label = item.chipLabel;
    if (label == '월지출' || label == '월수익') return true;
    if (label != null && (label.startsWith('지출') || label.startsWith('매매'))) {
      return true;
    }
    return item.color.toARGB32() == _kFinanceRed.toARGB32();
  }

  List<_DayGridItem> _visibleCalendarDayItems(List<_DayGridItem> all) {
    final pinned = all.where(_isPinnedFinanceItem).toList();
    final rest = all.where((e) => !_isPinnedFinanceItem(e)).toList();
    final slots = _kMaxSingleDayBarsShown - pinned.length;
    if (slots <= 0) {
      return pinned.take(_kMaxSingleDayBarsShown).toList(growable: false);
    }
    return [
      ...rest.take(slots),
      ...pinned,
    ];
  }

  void _refreshFinanceData() {
    unawaited(_refreshStockProfits());
    unawaited(_refreshMonthlySummaries());
    unawaited(_refreshExpenses());
    unawaited(_refreshStockTrades());
  }

  void _openReceiptUploader() {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return;
    ModalGuard.showBottomSheet(
      context: context,
      guardKey: 'receipt-uploader',
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceiptUploaderSheet(
        userId: uid,
        onSaved: _refreshFinanceData,
      ),
    );
  }

  void _openStockUploader() {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return;
    ModalGuard.showBottomSheet(
      context: context,
      guardKey: 'stock-uploader',
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockUploaderSheet(
        userId: uid,
        onSaved: _refreshFinanceData,
      ),
    );
  }

  Widget _buildFinanceActionBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _openStockUploader,
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('체결 등록'),
            ),
            OutlinedButton.icon(
              onPressed: _openReceiptUploader,
              icon: Icon(Icons.receipt_long, size: 18, color: scheme.error),
              label: const Text('영수증 등록'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarHeaderRow() {
    final scheme = Theme.of(context).colorScheme;
    final title = DateFormat('yyyy년 M월', 'ko_KR').format(_focusedDay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1);
              });
              _onMonthChangedByNav();
            },
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1);
              });
              _onMonthChangedByNav();
            },
          ),
          TextButton(
            onPressed: () {
              final n = DateTime.now();
              setState(() {
                _focusedDay = n;
                _selectedDay = n;
              });
              _onMonthChangedByNav();
            },
            child: const Text('오늘'),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayLabelsRow() {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 2),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: _kCalendarColumnFlexes[i],
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _stackHeightForItems(int itemCount) {
    if (itemCount <= 0) return 0;
    final barPitch = _weekMultiLaneBarPitch();
    final n = math.min(_kMaxSingleDayBarsShown, itemCount);
    final more = itemCount - n;
    return n * barPitch + (more > 0 ? _kMoreLineHeight : 0.0);
  }

  double _weekMaxSingleDayStackHeight(List<DateTime> weekDays, DateTime focusedMonth) {
    var maxH = 0.0;
    for (final d in weekDays) {
      maxH = math.max(
        maxH,
        _stackHeightForItems(_dayGridItemsSplitForDay(d, focusedMonth).totalCount),
      );
    }
    return maxH;
  }

  Widget _buildWeekRow(List<DateTime> weekDays, DateTime focusedMonth) {
    final segments = _multiDaySegmentsForWeek(weekDays, focusedMonth).toList();
    _assignWeekLanes(segments);
    final laneCount = segments.isEmpty
        ? 0
        : 1 + segments.map((s) => s.lane).reduce(math.max);
    final barPitch = _weekMultiLaneBarPitch();
    final multiReserve = laneCount * barPitch;
    final singleDayStackH = _weekMaxSingleDayStackHeight(weekDays, focusedMonth);
    final eventArea = math.max(
      singleDayStackH + multiReserve,
      _kMinWeekRowEventAreaHeight,
    );
    final rowH = _kCalendarDayHeaderHeight + eventArea + _kWeekRowBottomPad;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalFlex = _kCalendarColumnFlexes.reduce((a, b) => a + b);
        final colWidths = [
          for (final flex in _kCalendarColumnFlexes)
            constraints.maxWidth * flex / totalFlex,
        ];
        final colLefts = <double>[];
        var x = 0.0;
        for (final w in colWidths) {
          colLefts.add(x);
          x += w;
        }
        return SizedBox(
          height: rowH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      flex: _kCalendarColumnFlexes[i],
                      child: _buildCalendarDayCell(
                        context,
                        weekDays[i],
                        focusedMonth,
                        singleDayEvents: _dayGridItemsSplitForDay(weekDays[i], focusedMonth),
                        singleDayStackHeight: singleDayStackH,
                        multiDayReserve: multiReserve,
                      ),
                    ),
                ],
              ),
              ...segments.map((seg) {
                final leftInset = seg.continuesFromPrevWeek ? 0.0 : 2.0;
                final rightInset = seg.continuesToNextWeek ? 0.0 : 2.0;
                final left = colLefts[seg.startCol] + leftInset;
                final width = colWidths
                        .sublist(seg.startCol, seg.endCol + 1)
                        .fold<double>(0, (sum, w) => sum + w) -
                    leftInset -
                    rightInset;
                final top = _kCalendarDayHeaderHeight + seg.lane * barPitch;
                final rL = Radius.circular(seg.continuesFromPrevWeek ? 0 : 4);
                final rR = Radius.circular(seg.continuesToNextWeek ? 0 : 4);
                final color = _eventDisplayColor(seg.event);
                final label = calendarEventChipLabel(seg.event.displayTitle);
                return Positioned(
                  left: left,
                  width: width,
                  height: _kEventBarHeight,
                  top: top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openEventDetail(seg.event),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.only(
                          topLeft: rL,
                          bottomLeft: rL,
                          topRight: rR,
                          bottomRight: rR,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonthCalendarGrid() {
    final days = _monthGridDays(_focusedDay);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCalendarHeaderRow(),
        _buildWeekdayLabelsRow(),
        for (var w = 0; w < 6; w++)
          _buildWeekRow(days.sublist(w * 7, w * 7 + 7), _focusedDay),
      ],
    );
  }

  Widget _buildCalendarDayCell(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required _DayGridItemsSplit singleDayEvents,
    required double singleDayStackHeight,
    required double multiDayReserve,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final outside = day.month != focusedDay.month || day.year != focusedDay.year;
    final isToday = calendarIsSameDay(day, DateTime.now());
    final sel = _selectedDay;
    final isSelected = sel != null && calendarIsSameDay(day, sel);

    final isWeekend = _isCalendarWeekend(day);

    final allItems = [
      ...singleDayEvents.userItems,
      ...singleDayEvents.externalItems,
    ];
    final visible = _visibleCalendarDayItems(allItems);
    final more = allItems.length - visible.length;

    final dayNumStyle = TextStyle(
      fontSize: 13,
      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
      height: 1,
      color: _calendarDayNumberColor(day, outside: outside) ??
          (outside
              ? scheme.outline.withValues(alpha: 0.45)
              : scheme.onSurface),
    );

    // 기본 배경(날짜 경계 시각화) → 선택·오늘은 강조색으로 덮어씀
    BoxDecoration deco = BoxDecoration(
      color: outside
          ? scheme.surfaceContainerLowest.withValues(alpha: 0.45)
          : scheme.surfaceContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        width: 0.5,
      ),
    );
    if (isSelected) {
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary, width: 2),
        color: scheme.primary.withValues(alpha: 0.08),
      );
    } else if (isToday) {
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 0.5,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final dayKey = _cacheDayKey(day);
        if (ModalGuard.isOpen('day-schedule:$dayKey')) return;
        setState(() {
          _selectedDay = day;
          _focusedDay = day;
        });
        _onMonthChangedByNav();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showDaySchedulePopup(day);
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0.4),
        decoration: deco,
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _kCalendarDayHeaderHeight,
              child: Align(
                alignment: isWeekend ? Alignment.topCenter : Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isWeekend ? 0 : 3,
                    4,
                    isWeekend ? 0 : 4,
                    2,
                  ),
                  child: _buildCalendarDayNumber(day, dayNumStyle),
                ),
              ),
            ),
            if (multiDayReserve > 0) SizedBox(height: multiDayReserve),
            SizedBox(
              height: singleDayStackHeight,
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    for (final e in visible) _buildSingleDayEventBar(e),
                    if (more > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 3, top: 1),
                        child: Text(
                          '+$more 미표시',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: scheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            CalendarDayCellProfit(
              profit: _stockProfitForDay(day),
              compact: isWeekend,
            ),
          ],
        ),
      ),
    );
  }

  void _openGroupInfo(Group group) {
    ModalGuard.showBottomSheet(
      context: context,
      guardKey: 'group-info:${group.id}',
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupInfoSheet(
        group: group,
        onLeave: (gid) async {
          await GroupService.leaveGroup(gid, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹에서 탈퇴했습니다.')));
        },
        onDelete: (gid) async {
          await GroupService.deleteGroup(gid, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹이 삭제되었습니다.')));
        },
        onChangeAdmin: (gid, newAdminUserId) async {
          await GroupService.changeGroupAdmin(gid, newAdminUserId, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('관리자가 변경되었습니다.')));
        },
        onChangePassword: (gid, newPassword) async {
          await GroupService.changeGroupPassword(gid, AuthService.currentUser!.id, newPassword);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarLetter = (_nickname ?? '?')[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const _MoneyCalAiTitle(),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '일정 검색',
            onPressed: () {
              ModalGuard.showBottomSheet(
                context: context,
                guardKey: 'event-search',
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => EventSearchSheet(
                  events: _events,
                  groups: _groups,
                  currentUserId: AuthService.currentUser?.id ?? '',
                  onPickEvent: _openEventDetail,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: '로그아웃',
            onPressed: () async {
              await PushMessagingService.clearTokenForLogout();
              await AuthService.signOut();
              if (mounted) context.go('/login');
            },
          ),
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(avatarLetter, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          if (AuthService.currentUser != null) _buildFinanceActionBar(),
          Expanded(
            child: SingleChildScrollView(
              child: _buildMonthCalendarGrid(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final menuTileSubtitleStyle = TextStyle(
      fontSize: 12,
      height: 1.15,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(children: [
              Icon(Icons.menu, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('메뉴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17,
                  color: Theme.of(context).colorScheme.primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '캘린더 표시 기본값',
                onPressed: _openLayerSettings,
              ),
            ]),
          ),
          const Divider(height: 1),

          // 필터 체크박스 (고정 순서)
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('내 일정만', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            value: _onlyMySchedules,
            onChanged: (v) {
              final on = v ?? false;
              setState(() {
                _onlyMySchedules = on;
                _clearCalendarCaches();
              });
              unawaited(CalendarLayerPrefs.saveOnlyMySchedules(on));
            },
            secondary: const Icon(Icons.person_outline, size: 22),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('아파트 청약·분양', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: _rebAptLoading
                ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                : (_rebAptError != null && _showRebAptSply
                    ? Text(
                        _rebAptError!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : null),
            value: _showRebAptSply,
            onChanged: (v) => unawaited(_setShowRebAptSply(v ?? false)),
            secondary: _rebAptLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: Padding(padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.apartment_outlined, size: 22),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('공모주(공시 제출)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: _dartIpoLoading
                ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                : (_dartIpoError != null && _showDartIpo
                    ? Text(
                        _dartIpoError!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : null),
            value: _showDartIpo,
            onChanged: (v) => unawaited(_setShowDartIpo(v ?? false)),
            secondary: _dartIpoLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: Padding(padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.show_chart, size: 22, color: Colors.green),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text('국내 매수 시그널', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: _stockSignalLoading
                        ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                        : (_stockSignalError != null && _showKrStockSignals
                            ? Text(
                                _stockSignalError!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.15,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : null),
                    value: _showKrStockSignals,
                    onChanged: (v) => unawaited(_setShowKrStockSignals(v ?? false)),
                    secondary: IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 22),
                      tooltip: '매수 시그널 종류 설정',
                      onPressed: _openBuySignalTypeSettings,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                ),
                _stockSignalLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.trending_up, size: 22, color: kBuySignalColor),
                      ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text('미국 매수 시그널', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: _stockSignalLoading
                        ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                        : (_stockSignalError != null && _showUsStockSignals
                            ? Text(
                                _stockSignalError!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.15,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : null),
                    value: _showUsStockSignals,
                    onChanged: (v) => unawaited(_setShowUsStockSignals(v ?? false)),
                    secondary: IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 22),
                      tooltip: '매수 시그널 종류 설정',
                      onPressed: _openBuySignalTypeSettings,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                ),
                _stockSignalLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.currency_exchange, size: 22, color: kBuySignalColor),
                      ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text('코인 매수 시그널', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: _stockSignalLoading
                        ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                        : (_stockSignalError != null && _showCryptoStockSignals
                            ? Text(
                                _stockSignalError!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.15,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : null),
                    value: _showCryptoStockSignals,
                    onChanged: (v) => unawaited(_setShowCryptoStockSignals(v ?? false)),
                    secondary: IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 22),
                      tooltip: '매수 시그널 종류 설정',
                      onPressed: _openBuySignalTypeSettings,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                ),
                _stockSignalLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.currency_bitcoin, size: 22, color: kBuySignalColor),
                      ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('미국 거시지표 (FRED·ISM)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: _fredLoading
                ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                : (_fredError != null && _showFred
                    ? Text(
                        _fredError!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : null),
            value: _showFred,
            onChanged: (v) => unawaited(_setShowFred(v ?? false)),
            secondary: _fredLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: Padding(padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.query_stats, size: 22, color: Color(0xFF6a1b9a)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('한국은행 경제통계 일정', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: _bokLoading
                ? Text('불러오는 중…', style: menuTileSubtitleStyle)
                : (_bokError != null && _showBok
                    ? Text(
                        _bokError!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : null),
            value: _showBok,
            onChanged: (v) => unawaited(_setShowBok(v ?? false)),
            secondary: _bokLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: Padding(padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.account_balance, size: 22, color: Color(0xFF0d47a1)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          const Divider(height: 1),

          // 그룹 목록 (남은 공간 차지, 스크롤 가능)
          Expanded(
            child: ListView(
              children: [
                // 새로운 그룹 생성하기+
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  leading: Icon(Icons.add_circle_outline,
                      size: 22, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    '새로운 그룹 생성하기',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  trailing: Icon(Icons.add,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onTap: () { Navigator.pop(context); context.push('/groups/create'); },
                ),
                const Divider(height: 1),

                if (_loadingGroups)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '그룹에 가입하거나 새로운 그룹을 만들어 보세요.',
                      style: TextStyle(fontSize: 13, height: 1.2, color: Colors.grey.shade500),
                    ),
                  )
                else ...[
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text('전체', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    value: _visibleGroupIds.length == _groups.length
                        ? true
                        : _visibleGroupIds.isEmpty
                            ? false
                            : null,
                    tristate: true,
                    onChanged: (_) {
                      setState(() {
                        if (_visibleGroupIds.length == _groups.length) {
                          _visibleGroupIds.clear();
                        } else {
                          _visibleGroupIds = _groups.map((g) => g.id).toSet();
                        }
                        _clearCalendarCaches();
                      });
                      _loadEvents();
                    },
                  ),
                  const Divider(height: 1),
                  ..._groups.map((g) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: g.flutterColor, shape: BoxShape.circle),
                    ),
                    title: Text(g.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Checkbox(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        value: _visibleGroupIds.contains(g.id),
                        activeColor: g.flutterColor,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) _visibleGroupIds.add(g.id);
                            else _visibleGroupIds.remove(g.id);
                            _clearCalendarCaches();
                          });
                          _loadEvents();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () { Navigator.pop(context); _openGroupInfo(g); },
                      ),
                    ]),
                  )),
                ],
              ],
            ),
          ),

          // 하단 메뉴
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () { Navigator.pop(context); context.push('/groups/join'); },
                icon: const Icon(Icons.group_add, size: 20),
                label: const Text('그룹 가입'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: const Icon(Icons.person, size: 22),
            title: const Text('프로필 설정', style: TextStyle(fontSize: 15)),
            onTap: () { Navigator.pop(context); context.push('/profile'); },
          ),
          if (_appVersionLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Text(
                _appVersionLabel!,
                style: TextStyle(fontSize: 12, height: 1.15, color: Colors.grey.shade600),
              ),
            ),
        ]),
      ),
    );
  }
}

