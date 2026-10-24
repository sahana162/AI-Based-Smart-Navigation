import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech wrapper around [FlutterTts].
///
/// Extends [ChangeNotifier] so services and widgets know when speech begins and ends,
/// preventing microphone feedback loops where the assistant hears its own voice.
class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  String _lastMessage = '';
  DateTime? _lastSpeakTime;
  bool _isSpeaking = false;
  String _currentLocale = 'en-US';
  VoidCallback? onSpeechCompleted;

  bool get isSpeaking => _isSpeaking;
  String get lastMessage => _lastMessage;
  String get currentLocale => _currentLocale;
  bool get isKannada => _currentLocale.toLowerCase().startsWith('kn');

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise with optional [rate] (0.0–1.0), [pitch] (0.5–2.0), and [language].
  Future<void> initialize({
    double rate = 0.5,
    double pitch = 1.0,
    String language = 'en-US',
  }) async {
    _currentLocale = language;
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.awaitSynthCompletion(true);

      // Bypass iOS hardware silent switch and duck background audio
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );

      _tts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
        onSpeechCompleted?.call();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });

      _tts.setErrorHandler((msg) {
        debugPrint('TtsService error: $msg');
        _isSpeaking = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('TtsService.initialize platform exception: $e');
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Speaks [text]. Stops any ongoing speech first.
  /// Automatically debounces duplicate identical messages within 1800ms.
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (_lastMessage.trim().toLowerCase() == trimmed.toLowerCase() &&
        _lastSpeakTime != null &&
        now.difference(_lastSpeakTime!).inMilliseconds < 1800) {
      debugPrint('[TtsService] Suppressed duplicate speech within 1800ms: "$trimmed"');
      return;
    }

    _lastMessage = trimmed;
    _lastSpeakTime = now;
    _isSpeaking = true;
    notifyListeners();
    try {
      await _tts.stop();
      await _tts.speak(trimmed);
    } catch (e) {
      debugPrint('TtsService.speak platform exception: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// High-priority speech for life-safety warnings (Emergency SOS, critical collision alerts).
  ///
  /// Guarantees maximum volume (1.0), immediately cuts off ongoing low-priority chatter,
  /// and delivers clear audible acoustic alerts in noisy environments.
  Future<void> emergencySpeak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (_lastMessage.trim().toLowerCase() == trimmed.toLowerCase() &&
        _lastSpeakTime != null &&
        now.difference(_lastSpeakTime!).inMilliseconds < 1500) {
      debugPrint('[TtsService] Suppressed duplicate emergency speech within 1500ms: "$trimmed"');
      return;
    }

    _lastMessage = trimmed;
    _lastSpeakTime = now;
    _isSpeaking = true;
    notifyListeners();
    try {
      await _tts.stop();
      await _tts.setVolume(1.0);
      await _tts.speak(trimmed);
    } catch (e) {
      debugPrint('TtsService.emergencySpeak platform exception: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Sets audio output volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    try {
      await _tts.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('TtsService.setVolume platform exception: $e');
    }
  }

  /// Stops the currently playing speech immediately.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TtsService.stop platform exception: $e');
    }
    if (_isSpeaking) {
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Repeats the last spoken message, or speaks [emptyMessage] if none exists.
  Future<void> repeat({String emptyMessage = 'No message to repeat.'}) {
    if (_lastMessage.isEmpty) {
      return speak(emptyMessage);
    }
    // Explicit user request to repeat: reset debounce timestamp so it is never dropped
    _lastSpeakTime = null;
    return speak(_lastMessage);
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Updates speech [rate] and/or [pitch] at runtime.
  Future<void> updateSettings({double? rate, double? pitch}) async {
    try {
      if (rate != null) await _tts.setSpeechRate(rate);
      if (pitch != null) await _tts.setPitch(pitch);
    } catch (e) {
      debugPrint('TtsService.updateSettings platform exception: $e');
    }
  }

  /// Attempts to switch TTS to [locale] (e.g. 'en-US' or 'kn-IN').
  ///
  /// Returns `true` if the language was accepted by the TTS engine,
  /// `false` if the engine reports the language is not available.
  Future<bool> setLanguage(String locale) async {
    try {
      final result = await _tts.setLanguage(locale);
      // flutter_tts returns 1 on success, other values on failure.
      if (result == 1) {
        _currentLocale = locale;
        return true;
      }

      // Some engine builds return null or 0 for unavailable locales.
      // Fall back to English so the app stays functional.
      await _tts.setLanguage('en-US');
      _currentLocale = 'en-US';
      return false;
    } catch (e) {
      debugPrint('TtsService.setLanguage platform exception: $e');
      return false;
    }
  }

  /// Checks whether [locale] is available on the current device's TTS engine.
  ///
  /// Returns `true` if supported, `false` otherwise.
  Future<bool> isLanguageAvailable(String locale) async {
    try {
      final available = await _tts.isLanguageAvailable(locale);
      return available == true || available == 1;
    } catch (_) {
      return false;
    }
  }
}
