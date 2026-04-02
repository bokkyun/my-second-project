/// DNS·소켓 오류 등 기술 문구를 사용자용 안내로 바꿉니다.
String? friendlyNetworkMessage(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('failed host lookup') ||
      s.contains('no address associated with hostname') ||
      s.contains('socketexception') ||
      s.contains('errno = 7')) {
    return '서버 주소를 찾지 못했습니다(DNS). Wi‑Fi·모바일 데이터 연결을 확인하고, '
        '설정에서 비공개 DNS(자동/끄기)를 바꿔 보세요. 에뮬레이터는 Cold Boot 후 '
        'PC 방화벽·VPN을 확인해주세요.';
  }
  if (s.contains('network is unreachable') || s.contains('connection refused')) {
    return '서버에 연결할 수 없습니다. 잠시 후 다시 시도하거나 네트워크를 확인해주세요.';
  }
  return null;
}
