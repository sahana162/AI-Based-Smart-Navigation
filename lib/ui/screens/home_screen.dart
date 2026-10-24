import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_strings.dart';
import '../../core/services/pedestrian_navigation_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_command.dart';
import '../widgets/accessible_button.dart';
import 'feature_detail_screen.dart';
import 'navigation_screen.dart';
import 'settings_screen.dart';

/// Clean, high-contrast, voice-first home screen centered on Alice.
///
/// Complies with Rule 3: Replaces the icon-heavy grid with a focused, accessible
/// interface featuring Alice, "Your AI Navigation Companion", a large central
/// touch area to start listening, a minimal status indicator, and secondary accessible actions.
class HomeScreen extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final VoiceSessionCoordinator? voiceCoordinator;

  const HomeScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    this.voiceCoordinator,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin
    implements VoiceCommandDelegate {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  String _lastVoiceTranscript = '';
  String _assistantStatus = '';
  bool _hasSpokenGreeting = false;

  @override
  String get screenName => 'Home';

  AppLanguage get _currentLanguage =>
      AppLanguage.fromCode(widget.storageService.appLanguage);

  AppStrings get _strings => AppStrings(_currentLanguage);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    widget.voiceCoordinator?.registerDelegate(this);
    widget.voiceCoordinator?.addListener(_onCoordinatorUpdate);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakWelcomeGreeting();
    });
  }

  void _onCoordinatorUpdate() {
    if (!mounted || widget.voiceCoordinator == null) return;
    final isListening = widget.voiceCoordinator!.isListening;
    if (isListening && !_animController.isAnimating) {
      _animController.repeat(reverse: true);
    } else if (!isListening && _animController.isAnimating) {
      _animController.stop();
      _animController.reset();
    }

    setState(() {
      if (widget.voiceCoordinator!.lastTranscript.isNotEmpty) {
        _lastVoiceTranscript = widget.voiceCoordinator!.lastTranscript;
      }
      if (widget.voiceCoordinator!.statusText.isNotEmpty) {
        _assistantStatus = widget.voiceCoordinator!.statusText;
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    widget.voiceCoordinator?.removeListener(_onCoordinatorUpdate);
    widget.voiceCoordinator?.unregisterDelegate(this);
    super.dispose();
  }

  Future<void> _speakWelcomeGreeting() async {
    if (_hasSpokenGreeting) return;
    _hasSpokenGreeting = true;
    final name = widget.storageService.assistantName;
    final strings = _strings;
    final isKn = strings.isKannada;
    final hasCompleted = widget.storageService.hasCompletedOnboarding;

    if (!hasCompleted) {
      await widget.storageService.setCompletedOnboarding(true);
      final walkthrough = isKn
          ? 'ಸ್ಮಾರ್ಟ್ ನ್ಯಾವಿಗೇಷನ್‌ಗೆ ಸುಸ್ವಾಗತ. ನಾನು ನಿಮ್ಮ ಧ್ವನಿ ಸಹಾಯಕ $name. ನೀವು ಯಾವುದೇ ಸಮಯದಲ್ಲಿ ಪರದೆಯ ಮೇಲೆ ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ ನನ್ನೊಂದಿಗೆ ಮಾತನಾಡಬಹುದು, ಅಥವಾ ಕೆಳಗಿನ ದೊಡ್ಡ ಮೈಕ್ ಬಟನ್ ಒತ್ತಬಹುದು. ತುರ್ತು ಸಹಾಯಕ್ಕಾಗಿ ಪರದೆಯ ಮೇಲೆ ದೀರ್ಘವಾಗಿ ಒತ್ತಿರಿ. ಸಹಾಯ ಪಡೆಯಲು "ಹೆಲ್ಪ್" ಅಥವಾ "ನಾನು ಎಲ್ಲಿದ್ದೇನೆ" ಎಂದು ಹೇಳಿ. ನಾನು ಸಿದ್ಧವಾಗಿದ್ದೇನೆ.'
          : 'Welcome to Smart Navigation. I am $name, your mobility and vision assistant. Double-tap anywhere on the screen at any time to speak to me, or tap the microphone button below. In an emergency, press and hold anywhere on the screen. Try saying "Where am I", "Take me home", or "Describe surroundings". I am ready to guide you.';
      setState(() {
        _assistantStatus = strings.assistantReady(name);
      });
      await widget.ttsService.speak(walkthrough);
      return;
    }

    final welcome = strings.welcomeGreeting(name);
    setState(() {
      _assistantStatus = strings.assistantReady(name);
    });
    await widget.ttsService.speak(welcome);
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.startNavigation:
        _openNavigationScreen(promptDestination: true);
        return true;
      case VoiceCommandType.stopNavigation:
        widget.ttsService.speak(_strings.navNotActive);
        return true;
      case VoiceCommandType.openSettings:
        _openSettings();
        return true;
      case VoiceCommandType.help:
        _speakHelp();
        return true;
      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        _openNavigationScreen(destination: destination);
        return true;
      case VoiceCommandType.switchLanguage:
        final targetLang = command.argument ?? 'en';
        _switchLanguage(targetLang);
        return true;
      case VoiceCommandType.repeat:
        widget.ttsService.repeat(emptyMessage: _strings.noMessageToRepeat);
        return true;
      case VoiceCommandType.stopSpeaking:
        widget.ttsService.stop();
        setState(() {
          _assistantStatus = _strings.audioStopped;
        });
        return true;
      case VoiceCommandType.stopListening:
        if (widget.voiceCoordinator != null) {
          widget.voiceCoordinator!.stopListening(spokenFeedback: true);
        } else {
          widget.speechService.stopListening();
          widget.ttsService.speak(_strings.stoppedListening);
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleMicToggle() async {
    if (widget.ttsService.isSpeaking) {
      await widget.ttsService.stop();
      return;
    }

    if (widget.voiceCoordinator != null) {
      await widget.voiceCoordinator!.toggleListening();
      return;
    }

    final speechService = widget.speechService;
    final ttsService = widget.ttsService;
    final strings = _strings;
    final lang = _currentLanguage;

    if (speechService.isListening) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
      await speechService.stopListening();
      setState(() {
        _assistantStatus = strings.micTurnedOff;
      });
      await ttsService.speak(strings.stoppedListening);
    } else {
      await ttsService.stop();
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
      setState(() {
        _assistantStatus = strings.micListening;
        _lastVoiceTranscript = '';
      });

      final started = await speechService.startListening(
        localeId: lang.sttLocale,
        onResult: (words, isFinal) async {
          setState(() {
            _lastVoiceTranscript = words;
            _assistantStatus = strings.heardText(words);
          });
          if (isFinal && words.trim().isNotEmpty) {
            await speechService.stopListening();
            _executeVoiceCommand(words);
          }
        },
      );

      if (!started) {
        final err = speechService.lastError ?? 'Unable to activate microphone.';
        setState(() {
          _assistantStatus = err;
        });
        await ttsService.speak('Could not start microphone: $err');
      }
    }
  }

  Future<void> _switchLanguage(String code) async {
    final newLang = AppLanguage.fromCode(code);
    await widget.storageService.setAppLanguage(code);
    final isAvailable = await widget.ttsService.setLanguage(newLang.ttsLocale);

    setState(() {});

    final strings = AppStrings(newLang);
    if (newLang == AppLanguage.kn && !isAvailable) {
      await widget.ttsService.speak(strings.kannadaTtsUnavailableWarning);
    } else {
      await widget.ttsService.speak(strings.languageChangedConfirmation(newLang));
    }
  }

  void _executeVoiceCommand(String rawText) {
    if (widget.voiceCoordinator != null) {
      widget.voiceCoordinator!.processRecognizedText(rawText);
      return;
    }

    final assistantName = widget.storageService.assistantName;
    final command = VoiceCommandParser.parse(rawText, assistantName);

    if (handleVoiceCommand(command)) return;

    final reply = _strings.unknownCommand(command.rawText);
    setState(() {
      _assistantStatus = reply;
    });
    widget.ttsService.speak(reply);
  }

  void _speakHelp() {
    final name = widget.storageService.assistantName;
    final strings = _strings;
    final helpText = strings.helpCommands(name);
    setState(() {
      _assistantStatus = strings.help;
    });
    widget.ttsService.speak(helpText);
  }

  void _announceAroundMe() {
    HapticFeedback.mediumImpact();
    final nav = PedestrianNavigationService(
      ttsService: widget.ttsService,
      storageService: widget.storageService,
    );
    nav.announceNearbyAmenities();
  }

  void _openNavigationScreen({
    String? destination,
    String? visionAction,
    String? visionArg,
    bool promptDestination = false,
  }) {
    final name = widget.storageService.assistantName;
    final strings = _strings;
    if (destination == null && visionAction == null && !promptDestination) {
      widget.ttsService.speak(strings.navStarting(name));
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          storageService: widget.storageService,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          initialDestination: destination,
          initialVisionAction: visionAction,
          initialVisionArg: visionArg,
          promptDestinationOnLoad: promptDestination,
          voiceCoordinator: widget.voiceCoordinator,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          storageService: widget.storageService,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          voiceCoordinator: widget.voiceCoordinator,
          onSettingsUpdated: () {
            setState(() {});
          },
        ),
      ),
    );
  }

  void _triggerEmergency() {
    HapticFeedback.heavyImpact();
    final contact = widget.storageService.emergencyContact;
    final isKn = _strings.isKannada;
    widget.ttsService.speak(
      isKn
          ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ತುರ್ತು ಸಂಪರ್ಕ: $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
          : 'Emergency assistance active. Contact is $contact. Calling 112 if needed.',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeatureDetailScreen(
          title: _strings.featEmergencyTitle,
          status: _strings.statusAvailable,
          explanation: isKn
              ? 'ತುರ್ತು ಸಂಪರ್ಕ: $contact. ತಕ್ಷಣ ಸ್ಥಳೀಯ ತುರ್ತು ಸೇವೆಗಳಿಗೆ ಕರೆ ಮಾಡಿ.'
              : 'Emergency contact: $contact. Call local emergency services immediately for medical or physical danger.',
          technicalNotes: 'Direct phone dial and GPS location guidance.',
          icon: Icons.emergency,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          storageService: widget.storageService,
          voiceCoordinator: widget.voiceCoordinator,
          assistantName: widget.storageService.assistantName,
        ),
      ),
    );
  }

  void _openFeatureDetailModal({
    required String title,
    required String status,
    required String explanation,
    required String technicalNotes,
    required IconData icon,
    String? visionAction,
    String? visionArg,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeatureDetailScreen(
          title: title,
          status: status,
          explanation: explanation,
          technicalNotes: technicalNotes,
          icon: icon,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          storageService: widget.storageService,
          voiceCoordinator: widget.voiceCoordinator,
          assistantName: widget.storageService.assistantName,
          visionAction: visionAction,
          visionArg: visionArg,
        ),
      ),
    );
  }

  void _showAllFeaturesDialog() {
    final strings = _strings;
    final isKn = strings.isKannada;
    HapticFeedback.selectionClick();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  isKn ? 'ವೈಶಿಷ್ಟ್ಯಗಳ ಪರಿಚಯ' : 'Assistive Capabilities Guide',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isKn
                    ? 'ಯಾವುದೇ ವೈಶಿಷ್ಟ್ಯದ ವಿವರಣೆ ತಿಳಿಯಲು ಮತ್ತು ನೇರವಾಗಿ ಪ್ರಾರಂಭಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ.'
                    : 'Tap any capability to hear spoken instructions and launch it immediately.',
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildFeatureTile(
                title: isKn ? 'ಅಡೆತಡೆ ನ್ಯಾವಿಗೇಷನ್' : 'Obstacle Detection',
                subtitle: strings.featObjDesc,
                icon: Icons.explore,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: strings.featObjTitle,
                    status: strings.statusAvailable,
                    explanation: strings.featObjDesc,
                    technicalNotes: 'Real-time SSD MobileNet obstacle bounding box inference with distance sonar.',
                    icon: Icons.explore,
                    visionAction: 'navigation',
                  );
                },
              ),
              _buildFeatureTile(
                title: strings.featSceneTitle,
                subtitle: strings.featSceneDesc,
                icon: Icons.visibility,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: strings.featSceneTitle,
                    status: strings.statusAvailable,
                    explanation: strings.featSceneDesc,
                    technicalNotes: 'Scene classification and multi-object spatial depth estimation.',
                    icon: Icons.visibility,
                    visionAction: 'describe',
                  );
                },
              ),
              _buildFeatureTile(
                title: strings.featOcrTitle,
                subtitle: strings.featOcrDesc,
                icon: Icons.document_scanner,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: strings.featOcrTitle,
                    status: strings.statusAvailable,
                    explanation: strings.featOcrDesc,
                    technicalNotes: 'Google ML Kit On-Device Text Recognition for Latin and Kannada scripts.',
                    icon: Icons.document_scanner,
                    visionAction: 'ocr',
                  );
                },
              ),
              _buildFeatureTile(
                title: strings.featCurrencyTitle,
                subtitle: strings.featCurrencyDesc,
                icon: Icons.payments,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: strings.featCurrencyTitle,
                    status: strings.statusAvailable,
                    explanation: strings.featCurrencyDesc,
                    technicalNotes: 'Bimodal RGB/HSV color tint analysis and Indian Rupee text parsing (₹10 to ₹2000).',
                    icon: Icons.payments,
                    visionAction: 'currency',
                  );
                },
              ),
              _buildFeatureTile(
                title: isKn ? 'ಬಸ್ ಸಂಖ್ಯೆ ರೀಡರ್' : 'City Bus Route Reader',
                subtitle: isKn
                    ? 'ಬರುವ ಸಿಟಿ ಬಸ್ಸುಗಳ ಸಂಖ್ಯೆ ಮತ್ತು ಬೋರ್ಡ್ ಓದಿ.'
                    : 'Reads oncoming city bus numbers and destination boards aloud.',
                icon: Icons.directions_bus,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: isKn ? 'ಬಸ್ ಸಂಖ್ಯೆ ರೀಡರ್' : 'City Bus Route Reader',
                    status: strings.statusAvailable,
                    explanation: isKn
                        ? 'ಬಸ್ ನಿಲ್ದಾಣದಲ್ಲಿ ಬರುವ ಬಸ್ ಸಂಖ್ಯೆ (ಉದಾಹರಣೆಗೆ 500-D, 335E) ಮತ್ತು ಗಮ್ಯಸ್ಥಾನ ಫಲಕವನ್ನು ಕ್ಯಾಮೆರಾ ಮೂಲಕ ತಕ್ಷಣ ಓದಿ ಹೇಳುತ್ತದೆ.'
                        : 'Reads oncoming bus route codes (e.g., 500-D, 335E) and destinations aloud to make public transit stress-free.',
                    technicalNotes: 'High-speed transit regex matching with upper frame bus headboard extraction.',
                    icon: Icons.directions_bus,
                    visionAction: 'bus',
                  );
                },
              ),
              _buildFeatureTile(
                title: isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ & ರಸ್ತೆ ದಾಟುವಿಕೆ' : 'Traffic Light & Crossing Assistant',
                subtitle: isKn
                    ? 'ಸಿಗ್ನಲ್ ಕೆಂಪು ಅಥವಾ ಹಸಿರು ಎಂದು ತಿಳಿಯಿರಿ.'
                    : 'Check whether oncoming pedestrian signals are red or green.',
                icon: Icons.traffic,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಅಸಿಸ್ಟೆಂಟ್' : 'Traffic Light Assistant',
                    status: strings.statusAvailable,
                    explanation: isKn
                        ? 'ಜಂಕ್ಷನ್‌ನಲ್ಲಿರುವ ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಕೆಂಪು, ಹಳದಿ ಅಥವಾ ಹಸಿರು ಎಂಬುದನ್ನು ಮತ್ತು ಸ್ಟಾಪ್ ಸೈನ್‌ಗಳನ್ನು ಕ್ಯಾಮೆರಾ ಮೂಲಕ ವಿಶ್ಲೇಷಿಸಿ ಸುರಕ್ಷಿತವಾಗಿ ರಸ್ತೆ ದಾಟಲು ಮಾರ್ಗದರ್ಶನ ನೀಡುತ್ತದೆ.'
                        : 'Analyzes intersection traffic signals and pedestrian crossing lights for red, amber, and green illuminated states, giving voice-first road crossing guidance.',
                    technicalNotes: 'Spatial bounding box extraction fused with chrominance dominance profiling and stop sign recognition.',
                    icon: Icons.traffic,
                    visionAction: 'trafficLight',
                  );
                },
              ),
              _buildFeatureTile(
                title: strings.featLostItemTitle,
                subtitle: strings.featLostItemDesc,
                icon: Icons.search,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: strings.featLostItemTitle,
                    status: strings.statusAvailable,
                    explanation: strings.featLostItemDesc,
                    technicalNotes: 'SSD MobileNet object recognition matched against user registered item catalogue.',
                    icon: Icons.search,
                    visionAction: 'find',
                    visionArg: 'item',
                  );
                },
              ),
              _buildFeatureTile(
                title: isKn ? 'ಸುತ್ತಮುತ್ತಲಿನ ಸ್ಥಳಗಳು' : 'Around Me Exploration',
                subtitle: isKn
                    ? '150 ಮೀಟರ್ ವ್ಯಾಪ್ತಿಯ ಸೌಲಭ್ಯಗಳನ್ನು ಗಡಿಯಾರ ಮುಳ್ಳಿನ ದಿಕ್ಕಿನಲ್ಲಿ ತಿಳಿಯಿರಿ.'
                    : 'Discover nearby bus stops, crossings, and shops with clock-face directions.',
                icon: Icons.radar,
                onTap: () {
                  Navigator.pop(ctx);
                  _openFeatureDetailModal(
                    title: isKn ? 'ಸುತ್ತಮುತ್ತಲಿನ ಸ್ಥಳಗಳು' : 'Around Me Exploration',
                    status: strings.statusAvailable,
                    explanation: isKn
                        ? 'ನಿಮ್ಮ 150 ಮೀಟರ್ ವ್ಯಾಪ್ತಿಯಲ್ಲಿರುವ ಬಸ್ ನಿಲ್ದಾಣಗಳು, ಪಾದಚಾರಿ ರಸ್ತೆದಾಟುಗಳು, ಔಷಧಿ ಅಂಗಡಿಗಳು ಮತ್ತು ಎಟಿಎಂಗಳನ್ನು ಗಡಿಯಾರ ಮುಳ್ಳಿನ ದಿಕ್ಕಿನಲ್ಲಿ ತಿಳಿಸುತ್ತದೆ.'
                        : 'Scans OpenStreetMap Overpass for amenities and transit within 150m and presents them with 12-hour clock directions.',
                    technicalNotes: 'Overpass spatial queries converted to relative heading bearings.',
                    icon: Icons.radar,
                    visionAction: 'around_me',
                  );
                },
              ),
              _buildFeatureTile(
                title: strings.featEmergencyTitle,
                subtitle: strings.featEmergencyDesc,
                icon: Icons.emergency,
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerEmergency();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHighlight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 26),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }

  AssistantState _getCurrentState() {
    if (widget.voiceCoordinator != null) {
      return widget.voiceCoordinator!.assistantState;
    }
    if (widget.ttsService.isSpeaking) return AssistantState.speaking;
    if (widget.speechService.isListening) return AssistantState.listening;
    return AssistantState.ready;
  }

  @override
  Widget build(BuildContext context) {
    final assistantName = widget.storageService.assistantName;
    final strings = _strings;
    final state = _getCurrentState();

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          Semantics(
            button: true,
            label: strings.isKannada ? 'ವೈಶಿಷ್ಟ್ಯಗಳ ಪರಿಚಯ' : 'Capabilities Guide',
            hint: 'Opens comprehensive guide of all navigation and vision features',
            child: IconButton(
              icon: const Icon(Icons.menu_book, size: 28),
              onPressed: _showAllFeaturesDialog,
            ),
          ),
          Semantics(
            button: true,
            label: strings.settingsTitle,
            hint: 'Opens voice, speed, and language configuration',
            child: IconButton(
              icon: const Icon(Icons.settings, size: 28),
              onPressed: _openSettings,
            ),
          ),
          Semantics(
            button: true,
            label: strings.help,
            hint: 'Speaks available voice commands',
            child: IconButton(
              icon: const Icon(Icons.help_outline, size: 28),
              onPressed: _speakHelp,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            HapticFeedback.selectionClick();
            final name = widget.storageService.assistantName;
            final msg = _strings.isKannada
                ? '$name ಸಿದ್ಧವಾಗಿದೆ. ಮಾತನಾಡಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ, ಅಥವಾ ತುರ್ತು ಸಹಾಯಕ್ಕಾಗಿ ದೀರ್ಘವಾಗಿ ಒತ್ತಿರಿ.'
                : 'Assistant $name is ready. Double tap to speak, or press and hold for emergency SOS.';
            widget.ttsService.speak(msg);
          },
          onDoubleTap: _handleMicToggle,
          onLongPress: () {
            HapticFeedback.heavyImpact();
            _triggerEmergency();
          },
          child: Column(
            children: [
              // 1. Safety Disclaimer Strip
              Container(
                width: double.infinity,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.health_and_safety,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.safetyBanner,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Central Alice Experience (Overflow-safe & accessible)
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * 0.52,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Assistant Identity
                        Column(
                          children: [
                            Semantics(
                              header: true,
                              label: 'Assistant: $assistantName',
                              child: Text(
                                'Assistant: $assistantName',
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              strings.isKannada
                                  ? 'ನಿಮ್ಮ AI ನ್ಯಾವಿಗೇಷನ್ ಸಹಾಯಕ'
                                  : 'Your AI Navigation Companion',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentCyan,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Large Central Touch Area (Rule 3)
                        _buildCentralTouchArea(assistantName, state),

                        const SizedBox(height: 12),

                        // Minimal Status Indicator (Rule 3)
                        _buildMinimalStatusIndicator(state),

                        const SizedBox(height: 14),

                        // Quick Tactile Vision Tools (accessible chips)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildQuickActionChip(
                              icon: Icons.visibility,
                              label: strings.isKannada ? 'ವಿವರಣೆ' : 'Describe',
                              hint: 'Describe surroundings using camera',
                              onTap: () => _openNavigationScreen(visionAction: 'describe'),
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.featSceneTitle,
                                status: strings.statusAvailable,
                                explanation: strings.featSceneDesc,
                                technicalNotes: 'Scene classification and multi-object spatial depth estimation.',
                                icon: Icons.visibility,
                                visionAction: 'describe',
                              ),
                            ),
                            _buildQuickActionChip(
                              icon: Icons.document_scanner,
                              label: strings.isKannada ? 'ಪಠ್ಯ ಓದಿ' : 'Read Text',
                              hint: 'Read visible signs and documents aloud',
                              onTap: () => _openNavigationScreen(visionAction: 'ocr'),
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.featOcrTitle,
                                status: strings.statusAvailable,
                                explanation: strings.featOcrDesc,
                                technicalNotes: 'Google ML Kit On-Device Text Recognition for Latin and Kannada scripts.',
                                icon: Icons.document_scanner,
                                visionAction: 'ocr',
                              ),
                            ),
                            _buildQuickActionChip(
                              icon: Icons.payments,
                              label: strings.isKannada ? 'ಕರೆನ್ಸಿ' : 'Currency',
                              hint: 'Identify banknote currency value',
                              onTap: () => _openNavigationScreen(visionAction: 'currency'),
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.featCurrencyTitle,
                                status: strings.statusAvailable,
                                explanation: strings.featCurrencyDesc,
                                technicalNotes: 'Bimodal RGB/HSV color tint analysis and Indian Rupee text parsing (₹10 to ₹2000).',
                                icon: Icons.payments,
                                visionAction: 'currency',
                              ),
                            ),
                            _buildQuickActionChip(
                              icon: Icons.search,
                              label: strings.isKannada ? 'ವಸ್ತು ಹುಡುಕಿ' : 'Find Item',
                              hint: 'Find personal items using object detection',
                              onTap: () => _openNavigationScreen(visionAction: 'find', visionArg: 'item'),
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.featLostItemTitle,
                                status: strings.statusAvailable,
                                explanation: strings.featLostItemDesc,
                                technicalNotes: 'SSD MobileNet object recognition matched against user registered item catalogue.',
                                icon: Icons.search,
                                visionAction: 'find',
                                visionArg: 'item',
                              ),
                            ),
                            _buildQuickActionChip(
                              icon: Icons.directions_bus,
                              label: strings.isKannada ? 'ಬಸ್ ಸಂಖ್ಯೆ' : 'Bus Route',
                              hint: 'Scan oncoming city bus number and destination',
                              onTap: () => _openNavigationScreen(visionAction: 'bus'),
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.isKannada ? 'ಬಸ್ ಸಂಖ್ಯೆ ರೀಡರ್' : 'City Bus Route Reader',
                                status: strings.statusAvailable,
                                explanation: strings.isKannada
                                    ? 'ಬಸ್ ನಿಲ್ದಾಣದಲ್ಲಿ ಬರುವ ಬಸ್ ಸಂಖ್ಯೆ ಮತ್ತು ಗಮ್ಯಸ್ಥಾನ ಫಲಕವನ್ನು ಕ್ಯಾಮೆರಾ ಮೂಲಕ ತಕ್ಷಣ ಓದಿ ಹೇಳುತ್ತದೆ.'
                                    : 'Reads oncoming city bus numbers and destination boards aloud using on-device optical character recognition.',
                                technicalNotes: 'High-speed transit regex matching with upper frame bus headboard extraction.',
                                icon: Icons.directions_bus,
                                visionAction: 'bus',
                              ),
                            ),
                            _buildQuickActionChip(
                              icon: Icons.radar,
                              label: strings.isKannada ? 'ಸುತ್ತಮುತ್ತ' : 'Around Me',
                              hint: 'Explore nearby amenities, transit, and crossings',
                              onTap: _announceAroundMe,
                              onLongPress: () => _openFeatureDetailModal(
                                title: strings.isKannada ? 'ಸುತ್ತಮುತ್ತಲಿನ ಸ್ಥಳಗಳು' : 'Around Me Exploration',
                                status: strings.statusAvailable,
                                explanation: strings.isKannada
                                    ? 'ನಿಮ್ಮ 150 ಮೀಟರ್ ವ್ಯಾಪ್ತಿಯಲ್ಲಿರುವ ಬಸ್ ನಿಲ್ದಾಣಗಳು, ಪಾದಚಾರಿ ರಸ್ತೆದಾಟುಗಳು, ಔಷಧಿ ಅಂಗಡಿಗಳು ಮತ್ತು ಎಟಿಎಂಗಳನ್ನು ಗಡಿಯಾರ ಮುಳ್ಳಿನ ದಿಕ್ಕಿನಲ್ಲಿ ತಿಳಿಸುತ್ತದೆ.'
                                    : 'Scans OpenStreetMap Overpass for amenities and transit within 150m and presents them with 12-hour clock directions.',
                                technicalNotes: 'Overpass spatial queries converted to relative heading bearings.',
                                icon: Icons.radar,
                                visionAction: 'around_me',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Accessible Capabilities Guide Trigger
                        Semantics(
                          button: true,
                          label: strings.isKannada ? 'ಎಲ್ಲಾ ವೈಶಿಷ್ಟ್ಯಗಳ ವಿವರಣೆ' : 'Explore All Features Guide',
                          hint: 'Browse spoken explanations of all assistive capabilities',
                          child: TextButton.icon(
                            icon: const Icon(Icons.menu_book, color: AppTheme.accentCyan, size: 20),
                            label: Text(
                              strings.isKannada ? 'ವೈಶಿಷ್ಟ್ಯಗಳ ಪರಿಚಯ ಕೇಳಿ' : 'Explore All Features',
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.accentCyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _showAllFeaturesDialog,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Secondary Accessible Controls (Rule 3)
              Container(
                color: AppTheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Primary Navigation Button
                        Expanded(
                          flex: 3,
                          child: AccessibleButton(
                            label: strings.startNavigation,
                            icon: Icons.explore,
                            isPrimary: true,
                            minHeight: 56,
                            semanticHint: strings.startNavigationHint,
                            onPressed: () => _openNavigationScreen(promptDestination: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Repeat Button
                        Expanded(
                          flex: 2,
                          child: AccessibleButton(
                            label: strings.repeat,
                            icon: Icons.replay,
                            minHeight: 56,
                            semanticHint: strings.repeatHint,
                            onPressed: () => widget.ttsService.repeat(
                              emptyMessage: strings.noMessageToRepeat,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Emergency Assistance Button
                    AccessibleButton(
                      label: strings.featEmergencyTitle,
                      icon: Icons.emergency,
                      isDestructive: true,
                      minHeight: 52,
                      semanticHint: 'Access emergency contact and location guidance',
                      onPressed: _triggerEmergency,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCentralTouchArea(String assistantName, AssistantState state) {
    final Color bgColor;
    final Color borderColor;
    final IconData stateIcon;
    final String stateLabel;
    final String semanticState;

    switch (state) {
      case AssistantState.listening:
        bgColor = AppTheme.danger;
        borderColor = Colors.white;
        stateIcon = Icons.mic;
        stateLabel = _strings.isKannada ? 'ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ...' : 'Listening...';
        semanticState = 'Listening to your voice. Tap to stop listening.';
        break;
      case AssistantState.processing:
        bgColor = AppTheme.primary;
        borderColor = Colors.white;
        stateIcon = Icons.hourglass_top;
        stateLabel = _strings.isKannada ? 'ಪ್ರಕ್ರಿಯೆಗೊಳಿಸಲಾಗುತ್ತಿದೆ...' : 'Processing...';
        semanticState = 'Processing your request.';
        break;
      case AssistantState.speaking:
        bgColor = AppTheme.accentCyan;
        borderColor = Colors.white;
        stateIcon = Icons.volume_up;
        stateLabel = _strings.isKannada ? 'ಮಾತನಾಡುತ್ತಿದ್ದೇನೆ...' : 'Speaking...';
        semanticState = 'Alice is speaking. Tap to stop audio.';
        break;
      case AssistantState.ready:
        bgColor = AppTheme.surfaceHighlight;
        borderColor = AppTheme.primary;
        stateIcon = Icons.mic_none;
        stateLabel = _strings.isKannada
            ? 'ಮಾತನಾಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ'
            : 'Tap to Talk to $assistantName';
        semanticState = 'Ready. Double tap to talk to $assistantName.';
        break;
    }

    final isListening = state == AssistantState.listening;

    return Semantics(
      button: true,
      label: semanticState,
      hint: 'Single tap on center area activates speech recognition',
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = isListening ? _pulseAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _handleMicToggle,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bgColor,
                    border: Border.all(
                      color: borderColor,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: bgColor.withValues(alpha: isListening ? 0.6 : 0.3),
                        blurRadius: isListening ? 26 : 14,
                        spreadRadius: isListening ? 6 : 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        stateIcon,
                        size: 68,
                        color: (state == AssistantState.processing ||
                                state == AssistantState.speaking)
                            ? Colors.black
                            : Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          stateLabel,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: (state == AssistantState.processing ||
                                    state == AssistantState.speaking)
                                ? Colors.black
                                : Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMinimalStatusIndicator(AssistantState state) {
    final String stateName;
    final IconData icon;
    final Color color;

    switch (state) {
      case AssistantState.listening:
        stateName = 'Listening';
        icon = Icons.graphic_eq;
        color = AppTheme.danger;
        break;
      case AssistantState.processing:
        stateName = 'Processing';
        icon = Icons.sync;
        color = AppTheme.primary;
        break;
      case AssistantState.speaking:
        stateName = 'Speaking';
        icon = Icons.volume_up;
        color = AppTheme.accentCyan;
        break;
      case AssistantState.ready:
        stateName = 'Ready';
        icon = Icons.check_circle_outline;
        color = AppTheme.success;
        break;
    }

    return Semantics(
      liveRegion: true,
      label: 'Status: $stateName. $_assistantStatus',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  stateName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            if (_lastVoiceTranscript.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _strings.heardText(_lastVoiceTranscript),
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.accentCyan,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Semantics(
      button: true,
      label: label,
      hint: onLongPress != null ? '$hint. Long press to learn more.' : hint,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ActionChip(
          avatar: Icon(icon, color: AppTheme.accentCyan, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          backgroundColor: AppTheme.surfaceHighlight,
          side: const BorderSide(color: AppTheme.border, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          onPressed: onTap,
        ),
      ),
    );
  }
}
