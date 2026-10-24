import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/voice_command.dart';
import '../localization/app_strings.dart';
import 'pedestrian_navigation_service.dart';
import 'speech_service.dart';
import 'storage_service.dart';
import 'tts_service.dart';
import 'voice_command_parser.dart';

/// Current conversational and visual processing state of Alice.
enum AssistantState {
  ready,
  listening,
  processing,
  speaking,
}

/// Interface for screens that provide contextual handling for voice commands.
abstract class VoiceCommandDelegate {
  /// Attempt to handle [command]. Returns `true` if handled, `false` to let coordinator handle it.
  bool handleVoiceCommand(VoiceCommand command);

  /// Human-readable screen title for accessible announcements.
  String get screenName;
}

/// Centralized voice interaction coordinator for the entire application.
///
/// Ensures a single voice session lifecycle, eliminates duplicate command parsing,
/// prevents TTS acoustic feedback loops, and enables voice-first navigation across screens.
class VoiceSessionCoordinator extends ChangeNotifier {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final GlobalKey<NavigatorState> navigatorKey;

  VoiceCommandDelegate? _activeDelegate;
  bool _isSessionActive = false;
  bool _isProcessing = false;
  bool _awaitingConversationalReply = false;
  bool _isWakeWordStandby = false;
  int _emptyTimeoutCount = 0;
  int _standbyCycles = 0;
  int _standbyConsecutiveErrors = 0;
  static const int _maxIdleStandbyCycles = 45; // ~4-5 minutes continuous silence without user activity
  static const int _maxConsecutiveStandbyErrors = 4;
  String _lastTranscript = '';
  String _statusText = '';
  DateTime? _lastCommandTime;
  String _lastProcessedText = '';

  VoiceSessionCoordinator({
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    required this.navigatorKey,
  }) {
    // When TTS finishes, pause briefly to clear audio echo then resume listening or standby.
    ttsService.onSpeechCompleted = _handleSpeechCompleted;
    ttsService.addListener(notifyListeners);
    speechService.addListener(notifyListeners);

    // Controlled timeout handling with silent standby recovery & battery protection
    speechService.onListeningTimeout = () async {
      debugPrint('[Coordinator] Listening timeout. emptyCount: $_emptyTimeoutCount, awaitingReply: $_awaitingConversationalReply, isWakeWordStandby: $_isWakeWordStandby');
      if (!_isSessionActive) return;

      // Normal silence / timeout during wake-word standby is silent, with battery quota guard:
      if (_isWakeWordStandby) {
        _standbyCycles++;
        if (_standbyCycles >= _maxIdleStandbyCycles) {
          _isWakeWordStandby = false;
          _isSessionActive = false;
          _statusText = strings.isKannada
              ? 'ಬ್ಯಾಟರಿ ಉಳಿಸಲು ಸ್ಟ್ಯಾಂಡ್‌ಬೈ ವಿರಾಮಗೊಂಡಿದೆ. ಮೈಕ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
              : 'Standby resting to save battery. Tap mic to wake.';
          notifyListeners();
          return;
        }

        Future.delayed(const Duration(milliseconds: 600), () {
          if (_isSessionActive && _isWakeWordStandby && !speechService.isListening && !ttsService.isSpeaking) {
            startWakeWordStandby();
          }
        });
        return;
      }

      if (_emptyTimeoutCount == 0 && _awaitingConversationalReply) {
        _emptyTimeoutCount++;
        _statusText = strings.isKannada
            ? 'ನಾನು ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ, ದಯವಿಟ್ಟು ನಿಮ್ಮ ಆಜ್ಞೆಯನ್ನು ಹೇಳಿ.'
            : 'I am listening. Please speak your command.';
        notifyListeners();
        await ttsService.speak(_statusText);
      } else {
        // Quietly return to wake-word standby without complaining or saying "I cannot understand"
        _emptyTimeoutCount = 0;
        _awaitingConversationalReply = false;
        _statusText = strings.stoppedListening;
        notifyListeners();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_isSessionActive && !speechService.isListening && !ttsService.isSpeaking) {
            startWakeWordStandby();
          }
        });
      }
    };

    speechService.onErrorOccurred = (errorMsg, category) {
      debugPrint('[Coordinator] STT error occurred: $errorMsg ($category)');
      _emptyTimeoutCount = 0;
      _awaitingConversationalReply = false;
      if (_isSessionActive) {
        if (_isWakeWordStandby) {
          // In standby, retry with exponential backoff up to max errors to protect against quota exhaustion
          if (category != SpeechErrorCategory.permission) {
            _standbyConsecutiveErrors++;
            if (_standbyConsecutiveErrors >= _maxConsecutiveStandbyErrors) {
              _isWakeWordStandby = false;
              _isSessionActive = false;
              _statusText = strings.isKannada
                  ? 'ಧ್ವನಿ ಸೇವೆ ವಿರಾಮದಲ್ಲಿದೆ. ಮಾತನಾಡಲು ಮೈಕ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
                  : 'Speech service resting. Tap mic to activate.';
              notifyListeners();
              return;
            }

            final delayMs = 1000 * _standbyConsecutiveErrors;
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_isSessionActive && _isWakeWordStandby && !speechService.isListening && !ttsService.isSpeaking) {
                startWakeWordStandby();
              }
            });
            return;
          }
        }
        _isSessionActive = false;
        _statusText = 'Microphone: $errorMsg';
        notifyListeners();
      }
    };
  }

  bool get isSessionActive => _isSessionActive;
  bool get isListening => speechService.isListening;
  bool get isProcessing => _isProcessing;
  bool get isWakeWordStandby => _isWakeWordStandby;
  String get lastTranscript => _lastTranscript;
  String get statusText => _statusText;

  AssistantState get assistantState {
    if (ttsService.isSpeaking) return AssistantState.speaking;
    if (_isProcessing) return AssistantState.processing;
    if (speechService.isListening) {
      return _isWakeWordStandby ? AssistantState.ready : AssistantState.listening;
    }
    return AssistantState.ready;
  }

  AppLanguage get currentLanguage =>
      AppLanguage.fromCode(storageService.appLanguage);

  AppStrings get strings => AppStrings(currentLanguage);

  // ── Screen Delegate Registration ──────────────────────────────────────────

  void registerDelegate(VoiceCommandDelegate delegate) {
    _activeDelegate = delegate;
  }

  void unregisterDelegate(VoiceCommandDelegate delegate) {
    if (_activeDelegate == delegate) {
      _activeDelegate = null;
    }
  }

  // ── Session Control ───────────────────────────────────────────────────────

  /// Starts or toggles listening. Can be triggered from any button or gesture.
  Future<void> toggleListening() async {
    if (speechService.isListening) {
      await stopListening(spokenFeedback: true);
    } else {
      await startListening();
    }
  }

  /// Starts an active voice listening session for commands.
  Future<bool> startListening({
    bool isInteractiveSession = true,
    bool awaitingReply = true,
  }) async {
    _isSessionActive = isInteractiveSession;
    _awaitingConversationalReply = awaitingReply;
    _isWakeWordStandby = false;
    _standbyCycles = 0;
    _standbyConsecutiveErrors = 0;

    // 1. Prevent feedback: stop any ongoing TTS before opening the mic
    await ttsService.stop();

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    _statusText = strings.micListening;
    _lastTranscript = '';
    notifyListeners();

    final lang = currentLanguage;
    final started = await speechService.startListening(
      localeId: lang.sttLocale,
      onResult: (words, isFinal) async {
        _lastTranscript = words;
        _statusText = strings.heardText(words);
        notifyListeners();

        if (isFinal && words.trim().isNotEmpty) {
          _emptyTimeoutCount = 0;
          _awaitingConversationalReply = false;
          // Stop listening immediately before processing command
          await speechService.stopListening();
          await processRecognizedText(words);
        }
      },
    );

    if (!started) {
      _isSessionActive = false;
      _awaitingConversationalReply = false;
      final errorMsg = speechService.lastError ?? 'Unable to activate microphone.';
      _statusText = errorMsg;
      notifyListeners();
      await ttsService.speak('Microphone error: $errorMsg');
      return false;
    }

    return true;
  }

  /// Starts passive listening for the wake word ("Alice").
  /// Treats silences and timeouts as normal standby without any spoken error announcements.
  Future<bool> startWakeWordStandby() async {
    _isSessionActive = true;
    _awaitingConversationalReply = false;
    _isWakeWordStandby = true;
    _emptyTimeoutCount = 0;

    // Prevent acoustic feedback
    await ttsService.stop();

    _statusText = 'Ready. Say "${storageService.assistantName}" to begin.';
    _lastTranscript = '';
    notifyListeners();

    final lang = currentLanguage;
    final started = await speechService.startListening(
      localeId: lang.sttLocale,
      onResult: (words, isFinal) async {
        _lastTranscript = words;
        _statusText = words;
        notifyListeners();

        final assistantName = storageService.assistantName.toLowerCase().trim();
        final lower = words.toLowerCase().trim();

        // Check if wake word is uttered
        final containsWakeWord = lower.contains(assistantName) ||
            lower.contains('hey $assistantName') ||
            lower.contains('ಆಲಿಸ್');

        if (containsWakeWord) {
          final parsed = VoiceCommandParser.parse(words, storageService.assistantName);
          final hasValidCommand = parsed.type != VoiceCommandType.startListening &&
              parsed.type != VoiceCommandType.none &&
              parsed.type != VoiceCommandType.unknown;

          // If a command was spoken WITH the wake word (e.g. "Alice, what am I looking at?"):
          if (hasValidCommand) {
            _isWakeWordStandby = false;
            _standbyCycles = 0;
            _standbyConsecutiveErrors = 0;
            await speechService.stopListening();
            await processRecognizedText(words);
          } else if (isFinal) {
            // Wake word alone ("Alice"): only prompt user once utterance finishes
            _isWakeWordStandby = false;
            _standbyCycles = 0;
            _standbyConsecutiveErrors = 0;
            await speechService.stopListening();
            _awaitingConversationalReply = true;
            final prompt = strings.isKannada
                ? 'ಹೇಳಿ, ನಾನು ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ.'
                : 'Yes? How can I help?';
            _statusText = prompt;
            notifyListeners();
            await ttsService.speak(prompt);
          }
        } else if (isFinal && words.trim().isNotEmpty) {
          // If a direct command was spoken even without wake word while in standby:
          final parsed = VoiceCommandParser.parse(words, storageService.assistantName);
          if (parsed.type != VoiceCommandType.unknown && parsed.type != VoiceCommandType.none) {
            _isWakeWordStandby = false;
            await speechService.stopListening();
            await processRecognizedText(words);
          }
        }
      },
    );

    return started;
  }

  /// Stops listening cleanly.
  Future<void> stopListening({bool spokenFeedback = false}) async {
    _isSessionActive = false;
    _awaitingConversationalReply = false;
    _isWakeWordStandby = false;
    _emptyTimeoutCount = 0;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    await speechService.stopListening();
    _statusText = strings.micTurnedOff;
    notifyListeners();

    if (spokenFeedback) {
      await ttsService.speak(strings.stoppedListening);
    }
  }

  void _handleSpeechCompleted() {
    debugPrint('[Coordinator] TTS completed. awaitingReply: $_awaitingConversationalReply, sessionActive: $_isSessionActive');
    if (!_isSessionActive) return;

    // Cooldown grace period of 600ms ensures speaker audio has cleared the microphone
    Future.delayed(const Duration(milliseconds: 600), () {
      if (ttsService.isSpeaking) return;
      if (_awaitingConversationalReply && !speechService.isListening) {
        startListening(isInteractiveSession: true, awaitingReply: true);
      } else if (!speechService.isListening) {
        // Return to wake-word standby automatically after responding
        startWakeWordStandby();
      }
    });
  }

  // ── Centralized Command Processing ────────────────────────────────────────

  /// Normalizes, parses, and executes any voice input.
  /// Prevents concurrent execution and debounces identical commands within 1500ms.
  Future<void> processRecognizedText(String rawText) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (_isProcessing) {
      debugPrint('[Coordinator] Already processing a command. Skipping concurrent: "$trimmed"');
      return;
    }
    if (_lastCommandTime != null &&
        now.difference(_lastCommandTime!).inMilliseconds < 1500 &&
        _lastProcessedText.toLowerCase() == trimmed.toLowerCase()) {
      debugPrint('[Coordinator] Debouncing identical repeated command within 1500ms: "$trimmed"');
      return;
    }

    _lastCommandTime = now;
    _lastProcessedText = trimmed;
    _isProcessing = true;
    _emptyTimeoutCount = 0;
    _awaitingConversationalReply = false;
    notifyListeners();

    try {
      final assistantName = storageService.assistantName;
      final command = VoiceCommandParser.parse(trimmed, assistantName);

      debugPrint('[Coordinator] Dispatching: $command');

      // 1. Give active screen delegate first chance to handle contextual commands
      if (_activeDelegate != null && _activeDelegate!.handleVoiceCommand(command)) {
        return;
      }

      // 2. Global command execution
      await executeGlobalCommand(command);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> executeGlobalCommand(VoiceCommand command) async {
    switch (command.type) {
      case VoiceCommandType.startListening:
        _isSessionActive = true;
        _awaitingConversationalReply = true;
        await ttsService.speak('Listening. What can I do for you?');
        break;

      case VoiceCommandType.stopListening:
        await stopListening(spokenFeedback: true);
        break;

      case VoiceCommandType.stopSpeaking:
        await ttsService.stop();
        _statusText = strings.audioStopped;
        notifyListeners();
        break;

      case VoiceCommandType.repeat:
        await ttsService.repeat(emptyMessage: strings.noMessageToRepeat);
        break;

      case VoiceCommandType.help:
        final name = storageService.assistantName;
        await ttsService.speak(strings.helpCommands(name));
        break;

      case VoiceCommandType.openSettings:
        await ttsService.speak('Opening settings.');
        navigatorKey.currentState?.pushNamed('/settings');
        break;

      case VoiceCommandType.goBack:
        if (navigatorKey.currentState?.canPop() == true) {
          await ttsService.speak('Going back.');
          navigatorKey.currentState?.pop();
        } else {
          await ttsService.speak('Already at home screen.');
        }
        break;

      case VoiceCommandType.startNavigation:
        await ttsService.speak(strings.navStarting(storageService.assistantName));
        navigatorKey.currentState?.pushNamed('/navigation');
        break;

      case VoiceCommandType.stopNavigation:
        if (navigatorKey.currentState?.canPop() == true) {
          await ttsService.speak('Navigation stopped. Returning to home.');
          navigatorKey.currentState?.pop();
        } else {
          await ttsService.speak(strings.navNotActive);
        }
        break;

      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        await ttsService.speak('Setting route to $destination. Opening navigation.');
        navigatorKey.currentState?.pushNamed('/navigation', arguments: destination);
        break;

      case VoiceCommandType.whereAmI:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          await nav.announceCurrentLocation();
        } finally {
          nav.dispose();
        }
        break;

      case VoiceCommandType.describeSurroundings:
        await ttsService.speak(
          strings.isKannada
              ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Looking around.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'describe'});
        break;

      case VoiceCommandType.detectObjects:
        await ttsService.speak(
          strings.isKannada
              ? 'ವಸ್ತು ಪತ್ತೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Checking for obstacles.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'detect'});
        break;

      case VoiceCommandType.readText:
        final ocrMode = command.argument ?? 'smart';
        await ttsService.speak(
          strings.isKannada
              ? 'ಪಠ್ಯವನ್ನು ಓದಲಾಗುತ್ತಿದೆ.'
              : (ocrMode == 'all' ? 'Reading all text in view.' : 'Reading text in view.'),
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'ocr',
          'ocrMode': ocrMode,
        });
        break;

      case VoiceCommandType.recognizeCurrency:
        await ttsService.speak(
          strings.isKannada
              ? 'ಕರೆನ್ಸಿ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ.'
              : 'Checking banknote.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'currency'});
        break;

      case VoiceCommandType.readBusRoute:
        await ttsService.speak(
          strings.isKannada
              ? 'ಬಸ್ ಸಂಖ್ಯೆ ಪರಿಶೀಲಿಸಲು ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Checking approaching bus route number.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'bus'});
        break;

      case VoiceCommandType.saveItem:
        final item = command.argument ?? 'item';
        await storageService.addSavedItem(
          item,
          notes: 'Saved on ${DateTime.now().toString().split('.')[0]}',
        );
        await ttsService.speak(
          strings.isKannada
              ? '$item ವಸ್ತುವನ್ನು ಯಶಸ್ವಿಯಾಗಿ ಉಳಿಸಲಾಗಿದೆ.'
              : 'Registered "$item" in your saved items list.',
        );
        break;

      case VoiceCommandType.findItem:
        final item = command.argument ?? 'item';
        final lowerRaw = command.rawText.toLowerCase();
        final isSavedLookup = lowerRaw.contains('saved') ||
            lowerRaw.contains('leave') ||
            lowerRaw.contains('left') ||
            lowerRaw.contains('put');

        final matches = storageService.savedItems.where(
          (e) => (e['name'] ?? '').toLowerCase() == item.toLowerCase(),
        ).toList();

        if (isSavedLookup && matches.isNotEmpty) {
          final notes = matches.first['notes'];
          final noteDetail = (notes != null && notes.isNotEmpty) ? ', noted: $notes' : '';
          await ttsService.speak(
            strings.isKannada
                ? 'ಉಳಿಸಿದ ವಸ್ತು $item ಹುಡುಕಲಾಗುತ್ತಿದೆ.'
                : 'Searching for your saved $item$noteDetail.',
          );
        } else {
          await ttsService.speak(
            strings.isKannada
                ? '$item ಹುಡುಕಲಾಗುತ್ತಿದೆ.'
                : 'Searching for $item.',
          );
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'find',
          'visionArg': item,
          'isSavedLookup': isSavedLookup,
          'savedNotes': matches.isNotEmpty ? matches.first['notes'] : null,
        });
        break;

      case VoiceCommandType.findPerson:
        navigatorKey.currentState?.pushNamed('/feature_detail', arguments: {
          'title': 'Face Recognition',
          'status': 'In Development',
          'explanation': 'Face recognition and saved people requires explicit biometric enrollment with privacy safeguards.',
          'technicalNotes': 'On-device face embeddings using privacy-preserving local storage.',
          'icon': Icons.face,
        });
        break;

      case VoiceCommandType.increaseSpeechSpeed:
        final newRate = (storageService.speechRate + 0.1).clamp(0.2, 1.0);
        await storageService.setSpeechRate(newRate);
        await ttsService.updateSettings(rate: newRate);
        await ttsService.speak('Speech speed increased to ${(newRate * 2).toStringAsFixed(1)}x.');
        break;

      case VoiceCommandType.decreaseSpeechSpeed:
        final newRate = (storageService.speechRate - 0.1).clamp(0.2, 1.0);
        await storageService.setSpeechRate(newRate);
        await ttsService.updateSettings(rate: newRate);
        await ttsService.speak('Speech speed decreased to ${(newRate * 2).toStringAsFixed(1)}x.');
        break;

      case VoiceCommandType.switchLanguage:
        final targetLang = command.argument ?? 'en';
        final newLang = AppLanguage.fromCode(targetLang);
        await storageService.setAppLanguage(targetLang);
        final isAvailable = await ttsService.setLanguage(newLang.ttsLocale);
        final newStrings = AppStrings(newLang);

        if (newLang == AppLanguage.kn && !isAvailable) {
          await ttsService.speak(newStrings.kannadaTtsUnavailableWarning);
        } else {
          await ttsService.speak(newStrings.languageChangedConfirmation(newLang));
        }
        notifyListeners();
        break;

      case VoiceCommandType.emergency:
        HapticFeedback.heavyImpact();
        final contact = storageService.emergencyContact;
        await ttsService.speak(
          strings.isKannada
              ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ನಿಮ್ಮ ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆ $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
              : 'Emergency mode active. Emergency contact is $contact. Opening emergency assistance and acquiring location.',
        );
        navigatorKey.currentState?.pushNamed('/feature_detail', arguments: {
          'title': strings.featEmergencyTitle,
          'status': strings.statusAvailable,
          'explanation': strings.isKannada
              ? 'ತುರ್ತು ಸಂಪರ್ಕ: $contact. ತುರ್ತು ಪರಿಸ್ಥಿತಿಯಲ್ಲಿ ತಕ್ಷಣ 112 ಅಥವಾ ನಿಮ್ಮ ತುರ್ತು ಸಂಪರ್ಕಕ್ಕೆ ಕರೆ ಮಾಡಿ.'
              : 'Emergency contact: $contact. In an emergency, always call 112 or your emergency contact immediately.',
          'technicalNotes': 'GPS location and emergency contact guidance ready.',
          'icon': Icons.emergency,
        });
        break;

      case VoiceCommandType.aroundMe:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          await nav.announceNearbyAmenities();
        } finally {
          nav.dispose();
        }
        break;

      case VoiceCommandType.toggleTorch:
        await ttsService.speak(
          strings.isKannada
              ? 'ಟಾರ್ಚ್ ನಿಯಂತ್ರಣಕ್ಕಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera for flashlight control.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'torch',
          'torchState': command.argument,
        });
        break;

      case VoiceCommandType.toggleObstacleAlerts:
        await ttsService.speak(
          strings.isKannada
              ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ನಿಯಂತ್ರಿಸಲು ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera navigation for obstacle alerts.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'toggleAlerts',
        });
        break;

      case VoiceCommandType.batteryStatus:
        final isKn = strings.isKannada;
        final hasLocation = await Geolocator.isLocationServiceEnabled();
        final emergency = storageService.emergencyContact;
        final langName = isKn ? 'ಕನ್ನಡ' : 'English';
        final speed = (storageService.speechSpeed * 100).round();

        if (isKn) {
          final locStatus = hasLocation ? 'ಜಿಪಿಎಸ್ ಸಕ್ರಿಯವಾಗಿದೆ' : 'ಜಿಪಿಎಸ್ ಆಫ್ ಆಗಿದೆ';
          await ttsService.speak(
            'ಡಿವೈಸ್ ಸ್ಥಿತಿ: $locStatus. ಭಾಷೆ $langName, ಧ್ವನಿ ವೇಗ ಶೇಕಡಾ $speed. ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆ $emergency. ಎಲ್ಲ ವ್ಯವಸ್ಥೆಗಳು ಕಾರ್ಯನಿರ್ವಹಿಸುತ್ತಿವೆ.',
          );
        } else {
          final locStatus = hasLocation ? 'GPS is active' : 'GPS location is disabled';
          await ttsService.speak(
            'Device status: $locStatus. Assistant language is $langName, speech rate is $speed percent. Emergency contact is $emergency. All systems operational.',
          );
        }
        break;

      case VoiceCommandType.facingDirection:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        await nav.announceFacingDirection();
        break;

      case VoiceCommandType.checkTrafficLight:
        await ttsService.speak(
          strings.isKannada
              ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲನೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera to inspect traffic signal color.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'trafficLight',
        });
        break;

      case VoiceCommandType.saveFavoritePlace:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        final tag = command.argument ?? 'home';
        await nav.saveCurrentLocationAsFavorite(tag: tag);
        break;

      case VoiceCommandType.none:
        // Silence or empty input: silently return to standby without any error speech
        break;

      case VoiceCommandType.unknown:
        final raw = command.rawText.trim();
        // Ignore very short noise, coughs, or single stray characters
        if (raw.length <= 2) {
          break;
        }
        final reply = strings.unknownCommand(command.rawText);
        _statusText = reply;
        notifyListeners();
        await ttsService.speak(reply);
        break;
    }
  }
}
