import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/group.dart';
import '../utils/reb_apt_field_labels.dart';

class EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;
  final List<Group> groups;
  final String currentUserId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const EventDetailSheet({
    super.key,
    required this.event,
    required this.groups,
    required this.currentUserId,
    required this.onEdit,
    required this.onDelete,
  });

  String _fmt(DateTime dt, bool isAllDay) => isAllDay
      ? DateFormat('yyyy.MM.dd (E)', 'ko').format(dt)
      : DateFormat('yyyy.MM.dd (E) HH:mm', 'ko').format(dt);

  Widget _buildRebAptLabeledBlock(BuildContext context, Map<String, dynamic> raw) {
    final sec = getRebAptDialogSections(raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sec.summary.isNotEmpty) ...[
          Text(
            '주요 항목',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sec.summary.map((e) => _rebAptLabeledRow(e, compact: true)).toList(),
            ),
          ),
        ],
        if (sec.rest.isNotEmpty) ...[
          if (sec.summary.isNotEmpty) const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          Text(
            '전체 항목',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '한글 라벨은 앱에서 매핑한 것이며, 괄호는 API 키입니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: sec.rest.map((e) => _rebAptLabeledRow(e, compact: false)).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rebAptLabeledRow(RebAptLabeledEntry e, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 10),
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: compact ? const Color(0xFF0d47a1) : Colors.grey.shade400,
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11, height: 1.25, color: Colors.black87),
                children: [
                  TextSpan(
                    text: e.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
                  ),
                  TextSpan(
                    text: '  (${e.k})',
                    style: const TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              e.v,
              style: TextStyle(fontSize: compact ? 13 : 14, height: 1.35, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDartIpoFields(Map<String, dynamic> raw) {
    const keys = <String, String>{
      'corp_name': '기업명',
      'flr_nm': '제출인',
      'report_nm': '보고서명',
      'rcept_dt': '접수일(공시제출일)',
      'rcept_no': '접수번호',
      'stock_code': '종목코드',
      'corp_cls': '시장 구분',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '공시 정보',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.green.shade800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in keys.entries) ...[
                if (raw[e.key] != null && raw[e.key].toString().trim().isNotEmpty) ...[
                  Text(e.value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                  const SizedBox(height: 2),
                  SelectableText(
                    raw[e.key].toString(),
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 읽기 전용(한국부동산원·Open DART·공공 API 등)
  Widget _buildExternalBody(BuildContext context) {
    final isIpo = event.externalSource == 'ipo';
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: event.flutterColor.withOpacity(0.12),
                border: Border(left: BorderSide(color: event.flutterColor, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(
                      isIpo ? 'Open DART(금감원 공시)' : '아파트 청약·분양(공공데이터)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: event.flutterColor.withOpacity(0.2),
                    side: BorderSide(color: event.flutterColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (event.creatorNickname != null)
                    Text(
                      '출처: ${event.creatorNickname}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.isAllDay
                              ? '${_fmt(event.startsAt, true)} (하루 종일)'
                              : '${_fmt(event.startsAt, false)} ~ ${_fmt(event.endsAt, false)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(event.description!, style: const TextStyle(fontSize: 13, height: 1.35)),
                  ],
                  if (event.externalRaw != null) ...[
                    const SizedBox(height: 12),
                    if (isIpo) _buildDartIpoFields(event.externalRaw!) else _buildRebAptLabeledBlock(context, event.externalRaw!),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (event.isExternal) {
      return _buildExternalBody(context);
    }
    final isOwner = event.creatorId == currentUserId;
    final isGroupAdmin = event.groupIds.any(
      (gid) => groups.any((g) => g.id == gid && g.myRole == 'admin'),
    );
    final canEdit = isOwner || isGroupAdmin;
    final sharedGroups = groups.where((g) => event.groupIds.contains(g.id)).toList();

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 4, width: 40, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),

        // 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: event.flutterColor.withOpacity(0.12),
            border: Border(left: BorderSide(color: event.flutterColor, width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (event.isGroupEvent) ...[
              const SizedBox(height: 6),
              Chip(
                label: const Text('그룹 이벤트', style: TextStyle(fontSize: 12)),
                backgroundColor: event.flutterColor.withOpacity(0.2),
                side: BorderSide(color: event.flutterColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
            if (event.creatorNickname != null)
              Text('등록: ${event.creatorNickname}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 시간
            Row(children: [
              const Icon(Icons.schedule, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(
                event.isAllDay
                    ? '${_fmt(event.startsAt, true)} (하루 종일)'
                    : '${_fmt(event.startsAt, false)} ~ ${_fmt(event.endsAt, false)}',
                style: const TextStyle(fontSize: 14),
              )),
            ]),

            // 메모
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(event.description!, style: const TextStyle(fontSize: 14))),
              ]),
            ],

            // 공유 그룹
            if (sharedGroups.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.group, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Wrap(
                  spacing: 6, runSpacing: 4,
                  children: sharedGroups.map((g) => Chip(
                    label: Text(g.name, style: const TextStyle(fontSize: 12)),
                    backgroundColor: g.flutterColor.withOpacity(0.15),
                    side: BorderSide(color: g.flutterColor.withOpacity(0.3)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  )).toList(),
                )),
              ]),
            ],

            if (canEdit) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('수정'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('삭제', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
      ),
    );
  }
}
