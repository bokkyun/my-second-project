// 청약홈(ODcloud Applyhome) 응답 ↔ 한글 라벨 — 웹 `rebAptFieldLabels.js`와 동기

const Map<String, String> rebOdcloudFieldLabels = {
  'HOUSE_NM': '주택명',
  'HSMP_NM': '단지명',
  'PBLANC_NM': '공고명',
  'SPLY_HSMP_NM': '공급단지명',
  'HSSPLY_HSMP_NM': '공급주택명',
  'BIZ_NM': '사업명',
  'SPLY_BIZ_NM': '공급사업명',
  'BLDG_NM': '동·건물',
  '주택명': '주택명',
  '아파트명': '아파트명',
  '사업명': '사업명',
  'HSSPLY_ADRES': '공급위치(주소)',
  '주소': '주소',
  'CTPRVN_NM': '시·도',
  'SIGNGU_NM': '시·군·구',
  'TELNO': '문의전화',
  'FAX': '팩스',
  'HMPG_ADRES': '홈페이지',
  'PBLANC_URL': '공고 URL',
  'PBLANC_NO': '공고번호',
  'HOUSE_MGMT_NO': '주택관리번호',
  'HSMP_MGMT_NO': '단지관리번호',
  '공고번호': '공고번호',
  '주택관리번호': '주택관리번호',
  'BSNS_MBY_NM': '사업주체',
  'CNSTRCT_ENTRPS_NM': '시공사',
  'MDAT_TELNO': '정비사업전화',
  'CSTRN_WRKNDE': '착공일',
  'CSTRN_COMPLNDE': '준공(예정)일',
  'RCEPT_BGNDE': '청약접수 시작일',
  'RCEPT_ENDDE': '청약접수 마감일',
  'SPLY_RCEPT_BGNDE': '공급·접수 시작일',
  'SPLY_RCEPT_ENDDE': '공급·접수 마감일',
  'SPLY_RCEPT_STTDE': '공급접수기간(시작)',
  'SPLY_RCEPT_CLSDE': '공급접수기간(마감)',
  'SUBSCR_LMT': '청약(주택형)한도',
  'MNVL': '최소연령(만)',
  'MNVL2': '최대연령(만)',
  'GNRL_RNK1_CRSPAREA_RCPTDE': '1순위(해당지역) 접수일',
  'GNRL_RNK1_CRSPAREA_ENDDE': '1순위(해당지역) 마감일',
  'GNRL_RNK1_ETC_AREA_ENDDE': '1순위(기타지역) 마감일',
  'PRTTN_RCEPT_BGNDE': '특별공급 접수시작',
  'PRTTN_RCEPT_ENDDE': '특별공급 접수마감',
  'CNTRCT_CNCLS_BGNDE': '계약체결 시작일',
  'CNTRCT_CNCLS_ENDDE': '계약체결 마감일',
  'SPLY_HSHLDCO': '공급세대수',
  'TOTAR': '면적(㎡)',
  'RCPT_MTHD': '접수방법',
  'INTRC_DEAL_TELNO': '입주(분양)문의',
};

String rebAptFieldLabel(String key) {
  if (key.isEmpty) return key;
  return rebOdcloudFieldLabels[key] ?? key;
}

String _t(Map<String, dynamic> raw, String k) {
  final v = raw[k];
  if (v == null) return '';
  return v.toString().trim();
}

List<List<dynamic>> get _summaryCandidates => [
      [
        '명칭',
        ['주택명', 'HOUSE_NM', 'HSMP_NM', 'PBLANC_NM', 'SPLY_HSMP_NM', 'HSSPLY_HSMP_NM', '사업명', 'BIZ_NM', 'SPLY_BIZ_NM', 'BLDG_NM', '아파트명'],
      ],
      ['위치/주소', ['HSSPLY_ADRES', '주소', 'CTPRVN_NM', 'SIGNGU_NM']],
      ['접수기간(시작)', ['RCEPT_BGNDE', 'SPLY_RCEPT_BGNDE', 'SPLY_RCEPT_STTDE', '접수시작일', '청약접수시작일']],
      ['접수기간(마감)', ['RCEPT_ENDDE', 'SPLY_RCEPT_ENDDE', 'SPLY_RCEPT_CLSDE', '접수마감일', '접수종료일']],
      ['공고/관리번호', ['PBLANC_NO', '공고번호', 'HOUSE_MGMT_NO', 'HSMP_MGMT_NO', '주택관리번호']],
      ['사업주체', ['BSNS_MBY_NM']],
      ['시공사', ['CNSTRCT_ENTRPS_NM']],
      ['문의', ['TELNO', 'MDAT_TELNO', 'INTRC_DEAL_TELNO']],
      ['홈페이지', ['HMPG_ADRES', 'PBLANC_URL']],
    ];

class RebAptLabeledEntry {
  const RebAptLabeledEntry({required this.k, required this.label, required this.v});
  final String k;
  final String label;
  final String v;
}

({List<RebAptLabeledEntry> summary, List<RebAptLabeledEntry> rest}) getRebAptDialogSections(
  Map<String, dynamic> raw,
) {
  final summary = <RebAptLabeledEntry>[];
  for (final e in _summaryCandidates) {
    final keys = e[1] as List<String>;
    for (final k in keys) {
      final v = _t(raw, k);
      if (v.isNotEmpty) {
        summary.add(RebAptLabeledEntry(k: k, label: rebAptFieldLabel(k), v: v));
        break;
      }
    }
  }
  final used = summary.map((r) => r.k).toSet();
  final rest = <RebAptLabeledEntry>[];
  for (final e in raw.entries) {
    if (e.value == null) continue;
    final v = e.value.toString().trim();
    if (v.isEmpty) continue;
    if (used.contains(e.key)) continue;
    rest.add(RebAptLabeledEntry(k: e.key, label: rebAptFieldLabel(e.key), v: v));
  }
  rest.sort((a, b) => a.label.compareTo(b.label));
  return (summary: summary, rest: rest);
}
