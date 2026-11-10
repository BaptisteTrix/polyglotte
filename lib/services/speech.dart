import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models.dart';

/// Synthèse vocale (voix intégrées d'Android).
class Tts {
  Tts._();
  static final FlutterTts _tts = FlutterTts();
  static double rate = 0.45;
  static Lang? _current;

  static Future<void> speak(String text, Lang lang, {double? speed}) async {
    try {
      await _tts.stop();
      if (_current != lang) {
        await _tts.setLanguage(lang.ttsLocale);
        _current = lang;
      }
      await _tts.setSpeechRate(speed ?? rate);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  static Future<bool> isAvailable(Lang lang) async {
    try {
      final r = await _tts.isLanguageAvailable(lang.ttsLocale);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() => _tts.stop();
}

/// Reconnaissance vocale (moteur Google d'Android).
class Stt {
  Stt._();
  static final SpeechToText _stt = SpeechToText();
  static bool? _ready;
  static String? lastError;

  static Future<bool> init() async {
    if (_ready == true) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) => lastError = e.errorMsg,
      );
    } catch (e) {
      lastError = '$e';
      _ready = false;
    }
    return _ready!;
  }

  static bool get isListening => _stt.isListening;

  static Future<bool> listen(
    Lang lang, {
    required void Function(String words, bool isFinal) onResult,
  }) async {
    if (!await init()) return false;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: lang.sttLocale,
        partialResults: true,
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
    return true;
  }

  static Future<void> stop() => _stt.stop();
}

/// Normalise un texte pour comparer une prononciation reconnue à l'attendu.
String normalizeForCompare(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll('́', '')
    .replaceAll(RegExp(r'[\s.,!?;:«»"。，！？；：、\-]'), '');

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Similarité entre 0 et 1.
double similarity(String heard, String expected) {
  final a = normalizeForCompare(heard);
  final b = normalizeForCompare(expected);
  if (a.isEmpty || b.isEmpty) return 0;
  final d = _levenshtein(a, b);
  final m = a.length > b.length ? a.length : b.length;
  return 1 - d / m;
}
