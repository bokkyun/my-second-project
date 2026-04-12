import 'package:flutter/material.dart';

import '../services/subway_prefs.dart';
import '../services/subway_station_search_service.dart';
import '../services/widget_sync_service.dart';

class SubwayCommuteSettingsPanel extends StatefulWidget {
  const SubwayCommuteSettingsPanel({super.key});

  @override
  State<SubwayCommuteSettingsPanel> createState() =>
      _SubwayCommuteSettingsPanelState();
}

class _SubwayCommuteSettingsPanelState extends State<SubwayCommuteSettingsPanel> {
  bool _loading = true;
  bool _saving = false;
  final List<_LegEdit> _go = [];
  final List<_LegEdit> _home = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final e in [..._go, ..._home]) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await SubwayPrefs.load();
    if (!mounted) return;
    setState(() {
      _go
        ..clear()
        ..addAll(cfg.goToWork.map((e) => _LegEdit.fromLeg(e)));
      _home
        ..clear()
        ..addAll(cfg.comeHome.map((e) => _LegEdit.fromLeg(e)));
      if (_go.isEmpty) _go.add(_LegEdit());
      if (_home.isEmpty) _home.add(_LegEdit());
      _loading = false;
    });
  }

  List<SubwayLeg> _toLegs(List<_LegEdit> source) => source
      .map((e) => SubwayLeg(
            station: e.station.text.trim(),
            direction: '',
            line: e.line,
          ))
      .where((e) => e.isValid)
      .toList();

  Future<void> _save() async {
    final cfg = SubwayCommuteConfig(
      goToWork: _toLegs(_go),
      comeHome: _toLegs(_home),
    );
    if (!cfg.hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 1개 역을 입력해 주세요.')),
      );
      return;
    }
    setState(() => _saving = true);
    await SubwayPrefs.save(cfg);
    await WidgetSyncService.syncSubwayOnly();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('출퇴근 지하철 경로를 저장했습니다.')),
    );
    Navigator.pop(context);
  }

  Future<void> _pickStation(_LegEdit leg) async {
    final picked = await showDialog<SubwayStationCandidate>(
      context: context,
      builder: (_) => const _StationSearchDialog(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      leg.station.text = picked.stationName;
      leg.line = picked.lineName;
    });
  }

  Widget _section(String title, List<_LegEdit> list) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...List.generate(list.length, (i) {
              final isFirst = i == 0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: list[i].station,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: isFirst ? '역 이름' : '환승역 $i',
                            hintText: '돋보기로 역 검색',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: '역 검색',
                              onPressed: () => _pickStation(list[i]),
                            ),
                          ),
                        ),
                        if (list[i].line.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(
                                '선택 노선: ${list[i].line}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: list.length <= 1
                        ? null
                        : () {
                            setState(() {
                              final removed = list.removeAt(i);
                              removed.dispose();
                            });
                          },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => list.add(_LegEdit())),
              icon: const Icon(Icons.add),
              label: const Text('환승역 추가'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '출근/퇴근 역·노선을 선택하면, 공공데이터 시간표 기준 다음 열차 안내를 표시합니다.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _section('출근 경로', _go),
        _section('퇴근 경로', _home),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_saving ? '저장 중...' : '저장'),
        ),
      ],
    );
  }
}

class _LegEdit {
  _LegEdit({
    String station = '',
    this.line = '',
  }) : station = TextEditingController(text: station);

  factory _LegEdit.fromLeg(SubwayLeg leg) => _LegEdit(
        station: leg.station,
        line: leg.line,
      );

  final TextEditingController station;
  String line;

  void dispose() {
    station.dispose();
  }
}

class _StationSearchDialog extends StatefulWidget {
  const _StationSearchDialog();

  @override
  State<_StationSearchDialog> createState() => _StationSearchDialogState();
}

class _StationSearchDialogState extends State<_StationSearchDialog> {
  final TextEditingController _query = TextEditingController();
  bool _loading = false;
  String? _error;
  List<SubwayStationCandidate> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _query.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SubwayStationSearchService.searchStations(keyword);
      if (!mounted) return;
      setState(() => _results = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '역 검색 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('역 검색'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              decoration: InputDecoration(
                hintText: '예: 흑석, 동작, 강남',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _loading ? null : _search,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_results.isEmpty)
              const Text('역명을 입력하고 검색해 주세요.')
            else
              SizedBox(
                height: 260,
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = _results[i];
                    return ListTile(
                      dense: true,
                      title: Text(item.stationName),
                      subtitle: Text(item.lineName),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

Future<void> showSubwayCommuteSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.paddingOf(ctx).bottom + 16,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '출퇴근 지하철 설정',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const SubwayCommuteSettingsPanel(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
