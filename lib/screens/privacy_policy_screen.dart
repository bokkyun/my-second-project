import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 웹 `PrivacyPage.jsx`와 동일한 조항 (TeamSync 개인정보처리방침)
class _Section {
  const _Section(this.title, this.content);
  final String title;
  final String content;
}

const _intro = '''
TeamSync(이하 "서비스")는 「개인정보 보호법」 제30조에 따라 정보 주체의 개인정보를 보호하고
이와 관련한 고충을 신속하고 원활하게 처리할 수 있도록 하기 위하여 다음과 같이 개인정보
처리방침을 수립·공개합니다.''';

const _sections = <_Section>[
  _Section(
    '제1조 (개인정보의 처리 목적)',
    '''TeamSync(이하 "서비스")는 다음의 목적을 위하여 개인정보를 처리합니다. 처리하고 있는 개인정보는 다음의 목적 이외의 용도로는 이용되지 않으며, 이용 목적이 변경되는 경우에는 개인정보 보호법 제18조에 따라 별도의 동의를 받는 등 필요한 조치를 이행할 예정입니다.

1. 회원 가입 및 관리: 회원 가입 의사 확인, 회원제 서비스 제공에 따른 본인 식별·인증, 회원 자격 유지·관리
2. 서비스 제공: 일정 등록 및 관리, 그룹 서비스 제공, 알림 서비스 제공
3. 고충 처리: 민원인의 신원 확인, 민원 사항 확인, 사실 조사를 위한 연락·통지, 처리 결과 통보''',
  ),
  _Section(
    '제2조 (수집하는 개인정보 항목)',
    '''서비스는 회원 가입, 서비스 이용 과정에서 아래와 같은 개인정보를 수집합니다.

【필수 항목】
- 아이디 (이메일 형식)
- 비밀번호 (암호화하여 저장)
- 닉네임

【서비스 이용 과정에서 자동 수집되는 정보】
- 서비스 이용 기록, 접속 IP 정보, 접속 일시
- 일정 데이터 (제목, 날짜, 시간, 장소, 메모)
- 그룹 활동 정보''',
  ),
  _Section(
    '제3조 (개인정보의 처리 및 보유 기간)',
    '''① 서비스는 법령에 따른 개인정보 보유·이용 기간 또는 정보 주체로부터 개인정보를 수집 시에 동의 받은 개인정보 보유·이용 기간 내에서 개인정보를 처리·보유합니다.

② 각각의 개인정보 처리 및 보유 기간은 다음과 같습니다.

- 회원 정보: 회원 탈퇴 시까지 (단, 관련 법령에 따라 일정 기간 보존)
- 일정 데이터: 회원 탈퇴 후 30일 이내 파기
- 접속 기록: 3개월

③ 관련 법령에 의한 보존의 필요가 있는 경우 다음과 같이 관련 법령에서 정한 일정 기간 보존합니다.
- 계약 또는 청약 철회 등에 관한 기록: 5년 (전자상거래법)
- 소비자 불만 또는 분쟁 처리에 관한 기록: 3년 (전자상거래법)''',
  ),
  _Section(
    '제4조 (개인정보의 제3자 제공)',
    '''① 서비스는 정보 주체의 개인정보를 제1조에서 명시한 범위 내에서만 처리하며, 정보 주체의 동의, 법률의 특별한 규정 등에 해당하는 경우에만 개인정보를 제3자에게 제공합니다.

② 현재 서비스는 이용자의 개인정보를 원칙적으로 외부에 제공하지 않습니다. 단, 아래의 경우에는 예외로 합니다.
- 이용자가 사전에 동의한 경우
- 법령의 규정에 의거하거나, 수사 목적으로 법령에 정해진 절차와 방법에 따라 수사 기관의 요구가 있는 경우''',
  ),
  _Section(
    '제5조 (개인정보 처리 위탁)',
    '''서비스는 원활한 서비스 운영을 위해 다음과 같이 개인정보 처리 업무를 위탁하고 있습니다.

- 위탁받는 자: Supabase Inc.
- 위탁 업무: 데이터베이스 운영 및 관리, 서버 호스팅
- 보유 및 이용 기간: 위탁 계약 종료 시까지

위탁 업체가 개인정보를 안전하게 처리하도록 관리·감독하고 있으며, 위탁 계약 시 개인정보가 안전하게 관리될 수 있도록 필요한 사항을 규정하고 있습니다.''',
  ),
  _Section(
    '제6조 (정보 주체의 권리·의무 및 행사 방법)',
    '''① 정보 주체는 서비스에 대해 언제든지 다음 각 호의 개인정보 보호 관련 권리를 행사할 수 있습니다.
- 개인정보 처리 정보에 대한 열람 요구
- 오류 등이 있을 경우 정정 요구
- 삭제 요구
- 처리 정지 요구

② 위 권리 행사는 서비스에 대해 서면, 이메일 등을 통하여 하실 수 있으며 서비스는 이에 대해 지체 없이 조치하겠습니다.

③ 개인정보의 정정 및 삭제 요구는 다른 법령에서 그 개인정보가 수집 대상으로 명시되어 있는 경우에는 그 삭제를 요구할 수 없습니다.

④ 정보 주체의 권리 행사에 따른 열람, 정정·삭제, 처리 정지의 요구는 회원 탈퇴를 통해서도 행사하실 수 있습니다.''',
  ),
  _Section(
    '제7조 (개인정보의 파기)',
    '''① 서비스는 개인정보 보유 기간의 경과, 처리 목적 달성 등 개인정보가 불필요하게 되었을 때에는 지체 없이 해당 개인정보를 파기합니다.

② 정보 주체로부터 동의 받은 개인정보 보유 기간이 경과하거나 처리 목적이 달성되었음에도 불구하고 다른 법령에 따라 개인정보를 계속 보존하여야 하는 경우에는, 해당 개인정보를 별도의 데이터베이스(DB)로 옮기거나 보관 장소를 달리하여 보존합니다.

③ 개인정보 파기의 절차 및 방법은 다음과 같습니다.
- 파기 절차: 파기 사유가 발생한 개인정보를 선정하고, 개인정보 보호 책임자의 승인을 받아 개인정보를 파기합니다.
- 파기 방법: 전자적 파일 형태로 기록·저장된 개인정보는 기록을 재생할 수 없도록 로우 레벨 포맷 등의 방법을 이용하여 파기합니다.''',
  ),
  _Section(
    '제8조 (개인정보의 안전성 확보 조치)',
    '''서비스는 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.

1. 개인정보 암호화: 이용자의 비밀번호는 암호화되어 저장 및 관리되고 있어 본인만이 알 수 있습니다.
2. 해킹 등에 대비한 기술적 대책: SSL/TLS 암호화 통신을 통해 개인정보가 안전하게 전송됩니다.
3. 개인정보 접근 제한: 개인정보를 처리하는 데이터베이스 시스템에 대한 접근 권한을 최소화합니다.''',
  ),
  _Section(
    '제9조 (개인정보 보호 책임자)',
    '''① 서비스는 개인정보 처리에 관한 업무를 총괄해서 책임지고, 정보 주체의 개인정보 관련 불만 처리 및 피해 구제 등을 위하여 아래와 같이 개인정보 보호 책임자를 지정하고 있습니다.

▶ 개인정보 보호 책임자
- 이메일: bchoi4284@gmail.com

② 정보 주체는 서비스를 이용하시면서 발생한 모든 개인정보 보호 관련 문의, 불만 처리, 피해 구제 등에 관한 사항을 개인정보 보호 책임자에게 문의하실 수 있습니다. 서비스는 정보 주체의 문의에 대해 지체 없이 답변 및 처리해드릴 것입니다.''',
  ),
  _Section(
    '제10조 (개인정보 처리방침의 변경)',
    '''① 이 개인정보처리방침은 2026년 3월 30일부터 적용됩니다.

② 이전의 개인정보 처리방침은 아래에서 확인하실 수 있습니다.
- 해당 없음 (최초 시행)

③ 개인정보처리방침 내용의 추가, 삭제 및 수정이 있을 경우 개정 최소 7일 전에 서비스 공지를 통해 알려드리겠습니다.''',
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('개인정보처리방침'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: ColoredBox(
        color: cs.surfaceContainerLowest,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '개인정보처리방침',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '시행일: 2026년 3월 30일',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Text(
              _intro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.7,
                    color: Colors.grey[800],
                  ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < _sections.length; i++) ...[
              if (i > 0) const Divider(height: 40),
              Text(
                _sections[i].title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                _sections[i].content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.75,
                      color: Colors.grey[800],
                    ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
