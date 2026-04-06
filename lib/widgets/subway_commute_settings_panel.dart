import 'package:flutter/material.dart';

import '../services/subway_prefs.dart';
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
            direction: e.direction.text.trim(),
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
        const SnackBar(content: Text('최소 1개 역/방향을 입력해 주세요.')),
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
                children: [
                  Expanded(
                    child: TextField(
                      controller: list[i].station,
                      decoration: InputDecoration(
                        labelText: isFirst ? '역 이름' : '환승역 $i',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: list[i].direction,
                      decoration: const InputDecoration(labelText: '방향'),
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
          '예: 흑석역 중앙보훈병원행, 동작역 오이도행',
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
  _LegEdit({String station = '', String direction = ''})
      : station = TextEditingController(text: station),
        direction = TextEditingController(text: direction);

  factory _LegEdit.fromLeg(SubwayLeg leg) =>
      _LegEdit(station: leg.station, direction: leg.direction);

  final TextEditingController station;
  final TextEditingController direction;

  void dispose() {
    station.dispose();
    direction.dispose();
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
