import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/event.dart';

/// 음성으로 일정 안내 (STT + TTS)
class ScheduleVoiceAssistant {
  ScheduleVoiceAssistant._();

  static final SpeechToText _speech = SpeechToText();
  static final FlutterTts _tts = FlutterTts();
  static bool _speechInited = false;
  static bool _ttsInited = false;

  static Future<bool> initSpeech() async {
    if (_speechInited) return _speech.isAvailable;
    _speechInited = true;
    return _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
  }

  static Future<void> initTts() async {
    if (_ttsInited) return;
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ttsInited = true;
  }

  static Future<void> stopSpeaking() => _tts.stop();

  /// 인식된 문장으로 '오늘' vs '내일' 구분. 없으면 null → 호출부에서 오늘로 처리 가능.
  static DateTime? resolveTargetDay(String heard, {required DateTime now}) {
    final compact = heard.replaceAll(' ', '');
    if (compact.contains('내일')) {
      return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    }
    if (compact.contains('오늘') ||
        compact.contains('금일') ||
        compact.contains('스케줄') ||
        compact.contains('일정') ||
        compact.contains('예정') ||
        compact.contains('메모') ||
        compact.contains('알려') ||
        compact.contains('읽어') ||
        compact.contains('말해')) {
      return DateTime(now.year, now.month, now.day);
    }
    return null;
  }

  static String buildSpokenSummary(List<CalendarEvent> events, DateTime day) {
    final dateStr = DateFormat('M월 d일').format(day);
    if (events.isEmpty) {
      return '$dateStr에는 등록된 일정이 없습니다.';
    }

    final sorted = List<CalendarEvent>.from(events)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final buf = StringBuffer('$dateStr 일정은 총 ${sorted.length}건입니다. ');
    final timeFmt = DateFormat('H시 m분');

    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      buf.write('${i + 1}번째, ${e.title}');
      if (e.isAllDay) {
        buf.write(', 하루 종일');
      } else {
        buf.write(', ${timeFmt.format(e.startsAt)}부터');
      }
      final memo = e.description?.trim();
      if (memo != null && memo.isNotEmpty) {
        buf.write(', 메모 $memo');
      }
      buf.write('. ');
    }
    return buf.toString();
  }

  /// 짧게 듣고 마지막으로 인식된 문장을 반환합니다.
  static Future<String> listenOnce({
    Duration listenFor = const Duration(seconds: 14),
    Duration pauseFor = const Duration(seconds: 2, milliseconds: 800),
  }) async {
    await _speech.stop();
    var heard = '';
    await _speech.listen(
      onResult: (r) => heard = r.recognizedWords,
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: 'ko_KR',
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
    await _speech.stop();
    return heard.trim();
  }

  static Future<void> speak(String text) async {
    await initTts();
    await _tts.speak(text);
  }
}
