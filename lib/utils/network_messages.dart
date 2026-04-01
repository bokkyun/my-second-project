/// DNS·소켓 오류 등 기술 문구를 사용자용 안내로 바꿉니다.
String? friendlyNetworkMessage(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('failed host lookup') ||
      s.contains('no address associated with hostname') ||
      s.contains('socketexception')) {
    return '인터넷에 연결할 수 없습니다. Wi‑Fi 또는 모바일 데이터를 확인하세요. '
        '에뮬레이터는 PC 인터넷·DNS 설정을 확인한 뒤 다시 시도해주세요.';
  }
  if (s.contains('network is unreachable') || s.contains('connection refused')) {
    return '서버에 연결할 수 없습니다. 잠시 후 다시 시도하거나 네트워크를 확인해주세요.';
  }
  return null;
}
