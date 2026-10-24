import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/pedestrian_navigation_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/vision_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_command.dart';
import '../widgets/accessible_button.dart';
import '../widgets/mic_button.dart';

class NavigationScreen extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final String? initialDestination;
  final String? initialVisionAction;
  final String? initialVisionArg;
  final String? initialOcrMode;
  final bool? isSavedLookup;
  final String? savedNotes;
  final PedestrianNavigationService? navigationService;
  final VisionService? visionService;
  final VoiceSessionCoordinator? voiceCoordinator;

  const NavigationScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    this.initialDestination,
    this.initialVisionAction,
    this.initialVisionArg,
    this.initialOcrMode,
    this.isSavedLookup,
    this.savedNotes,
    this.navigationService,
    this.visionService,
    this.voiceCoordinator,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver
    implements VoiceCommandDelegate {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  bool _isTorchOn = false;
  int _darkFrameCount = 0;
  String _statusMessage = 'Initializing camera feed...';
  List<CameraDescription> _availableCameras = [];

  bool _isLiveMonitoringActive = false;
  bool _isProcessingFrame = false;
  DateTime? _lastFrameProcessTime;
  DateTime? _lastAlertAnnouncementTime;
  String? _lastAnnouncedObstacle;

  late final PedestrianNavigationService _navService;
  bool _isLocalNavService = false;

  late final VisionService _visionService;
  bool _isLocalVisionService = false;

  @override
  String get screenName => 'Navigation';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.voiceCoordinator?.registerDelegate(this);

    if (widget.navigationService != null) {
      _navService = widget.navigationService!;
    } else {
      _navService = PedestrianNavigationService(
        ttsService: widget.ttsService,
        storageService: widget.storageService,
      );
      _isLocalNavService = true;
    }

    if (widget.visionService != null) {
      _visionService = widget.visionService!;
    } else {
      _visionService = VisionService();
      _isLocalVisionService = true;
    }

    _navService.addListener(_onNavServiceUpdated);
    _initializeCamera();

    if (widget.initialDestination != null && widget.initialDestination!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navService.startNavigationToDestination(widget.initialDestination!);
      });
    }
  }

  void _onNavServiceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        _stopLiveObstacleMonitoring();
        _cameraController?.dispose();
        _cameraController = null;
        _isCameraInitialized = false;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null && !_isPermissionDenied) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    final assistantName = widget.storageService.assistantName;
    setState(() {
      _statusMessage = 'Requesting camera access...';
    });

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _isPermissionDenied = true;
        _statusMessage =
            'Camera permission denied. Visual navigation cannot proceed without camera access.';
      });
      await widget.ttsService.speak(
        'Camera permission was denied. Please allow camera access in app settings to use visual navigation.',
      );
      return;
    }

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        setState(() {
          _statusMessage = 'No camera found on this device.';
        });
        await widget.ttsService.speak('No camera hardware was detected on this device.');
        return;
      }

      final camera = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _statusMessage = 'Camera is active and monitoring forward path.';
      });

      // Automatically engage live obstacle streaming if no one-off action was passed
      if (widget.initialVisionAction != null) {
        _runInitialVisionAction(
          widget.initialVisionAction!,
          widget.initialVisionArg,
          ocrMode: widget.initialOcrMode,
          isSavedLookup: widget.isSavedLookup ?? false,
          savedNotes: widget.savedNotes,
        );
      } else {
        final bool shouldStream = widget.storageService.obstacleAlertsDefaultEnabled;
        if (shouldStream) {
          _startLiveObstacleMonitoring();
        }
        if (widget.initialDestination == null) {
          final isKn = widget.ttsService.isKannada;
          final msg = isKn
              ? (shouldStream
                  ? '$assistantName ಸಿದ್ಧ. ಮುಂದೆ ಮಾರ್ಗ ಸ್ಪಷ್ಟವಾಗಿದೆ. ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು ಸಕ್ರಿಯವಾಗಿವೆ.'
                  : '$assistantName ಸಿದ್ಧ. ಮುಂದೆ ಮಾರ್ಗ ಸ್ಪಷ್ಟವಾಗಿದೆ.')
              : (shouldStream
                  ? '$assistantName is ready. Path ahead is clear. Live obstacle alerts active.'
                  : '$assistantName is ready. Path ahead is clear.');
          await widget.ttsService.speak(msg);
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing camera: $e';
      });
      await widget.ttsService.speak('Unable to open the camera: $e');
    }
  }

  void _startLiveObstacleMonitoring() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isLiveMonitoringActive) return;

    _isLiveMonitoringActive = true;
    if (mounted) setState(() {});

    try {
      _cameraController!.startImageStream(_handleCameraFrame);
      debugPrint('[NavigationScreen] Live obstacle streaming started.');
    } catch (e) {
      debugPrint('[NavigationScreen] Error starting image stream: $e');
    }
  }

  Future<void> _stopLiveObstacleMonitoring() async {
    if (!_isLiveMonitoringActive || _cameraController == null) return;
    _isLiveMonitoringActive = false;
    if (mounted) setState(() {});

    try {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
        debugPrint('[NavigationScreen] Live obstacle streaming stopped.');
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Error stopping image stream: $e');
    }
  }

  Future<void> _handleCameraFrame(CameraImage image) async {
    if (!_isLiveMonitoringActive || _isProcessingFrame) return;

    final now = DateTime.now();
    // Throttle inference: process 1 frame every 750 milliseconds
    if (_lastFrameProcessTime != null && now.difference(_lastFrameProcessTime!).inMilliseconds < 750) {
      return;
    }

    _lastFrameProcessTime = now;
    _isProcessingFrame = true;

    try {
      // Auto-exposure dark environment detection & auto-torch
      if (image.planes.isNotEmpty && image.planes.first.bytes.isNotEmpty) {
        final bytes = image.planes.first.bytes;
        int totalLum = 0;
        final int sampleStep = (bytes.length / 40).floor().clamp(1, 1000);
        int sampleCount = 0;
        for (int i = 0; i < bytes.length; i += sampleStep) {
          totalLum += bytes[i];
          sampleCount++;
        }
        if (sampleCount > 0) {
          final double avgLum = totalLum / sampleCount;
          if (avgLum < 20 && !_isTorchOn && widget.storageService.autoTorchEnabled) {
            _darkFrameCount++;
            if (_darkFrameCount >= 3) {
              _darkFrameCount = 0;
              _toggleTorch(true);
            }
          } else if (avgLum > 100) {
            _darkFrameCount = 0;
          }
        }
      }

      final sensorOrientation = _availableCameras.isNotEmpty
          ? _availableCameras.first.sensorOrientation
          : 90;

      final items = await _visionService.detectObjectsFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
      );

      if (!mounted || !_isLiveMonitoringActive) return;

      // Filter for prominent obstacles directly ahead or close by
      final obstacles = items.where((i) => i.isHighConfidence && (i.proximity == 'close' || i.proximity == 'near')).toList();

      if (obstacles.isNotEmpty) {
        // Sort with closest first
        obstacles.sort((a, b) => a.proximity == 'close' ? -1 : 1);
        final mostUrgent = obstacles.first;

        // Check debouncing: different obstacles announce immediately; same obstacle repeats at most every 3s (close/overhead) or 5s (near)
        final bool isSameObstacle = _lastAnnouncedObstacle == mostUrgent.label;
        final int elapsedSec = _lastAlertAnnouncementTime == null
            ? 999
            : now.difference(_lastAlertAnnouncementTime!).inSeconds;
        final int minRepeatIntervalSec = (mostUrgent.proximity == 'close' || mostUrgent.isOverheadHazard) ? 3 : 5;
        final bool shouldAnnounce = !isSameObstacle || elapsedSec >= minRepeatIntervalSec;

        if (shouldAnnounce) {
          _lastAnnouncedObstacle = mostUrgent.label;
          _lastAlertAnnouncementTime = now;

          final bool isKn = widget.ttsService.isKannada;
          final bool useSonar = widget.storageService.sonarCuesEnabled;
          final String spokenAlert;
          final distStr = mostUrgent.estimatedDistanceMeters != null
              ? '${mostUrgent.estimatedDistanceMeters}m'
              : '';

          if (isKn) {
            final labelKn = VisionService.translateLabelToKannada(mostUrgent.label);
            if (mostUrgent.isOverheadHazard) {
              spokenAlert = 'ಎಚ್ಚರಿಕೆ! ತಲೆಯ ಮಟ್ಟದಲ್ಲಿ ಅಡೆತಡೆ: $labelKn. ಬಾಗಿ ಅಥವಾ ನಿಲ್ಲಿ.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.heavyImpact();
            } else if (mostUrgent.proximity == 'close' && mostUrgent.position == 'center') {
              final dText = distStr.isNotEmpty ? 'ಸುಮಾರು ${mostUrgent.estimatedDistanceMeters} ಮೀಟರ್' : 'ಸಮೀಪದಲ್ಲಿದೆ';
              spokenAlert = 'ಎಚ್ಚರಿಕೆ! $labelKn ನೇರವಾಗಿ ಮುಂದೆ, $dText.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.heavyImpact();
            } else if (mostUrgent.position == 'center') {
              final dText = distStr.isNotEmpty ? ', ಸುಮಾರು ${mostUrgent.estimatedDistanceMeters} ಮೀಟರ್' : '';
              spokenAlert = 'ಮುಂದೆ ಅಡೆತಡೆ: $labelKn$dText.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.mediumImpact();
            } else {
              final posKn = mostUrgent.position == 'left' ? 'ಎಡಕ್ಕೆ' : 'ಬಲಕ್ಕೆ';
              spokenAlert = '$labelKn ನಿಮ್ಮ $posKn ಇದೆ.';
              HapticFeedback.lightImpact();
            }
          } else {
            if (mostUrgent.isOverheadHazard) {
              spokenAlert = 'Warning! Head-level obstacle ahead: ${mostUrgent.label}, low clearance.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.heavyImpact();
            } else if (mostUrgent.proximity == 'close' && mostUrgent.position == 'center') {
              final dText = distStr.isNotEmpty ? 'about ${mostUrgent.estimatedDistanceMeters} meters away' : 'close by';
              spokenAlert = 'Caution! ${mostUrgent.label} directly ahead, $dText.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.heavyImpact();
            } else if (mostUrgent.position == 'center') {
              final dText = distStr.isNotEmpty ? ' about ${mostUrgent.estimatedDistanceMeters} meters away' : '';
              spokenAlert = 'Obstacle ahead: ${mostUrgent.label}$dText.';
              if (useSonar) SystemSound.play(SystemSoundType.click);
              HapticFeedback.mediumImpact();
            } else {
              spokenAlert = '${mostUrgent.label} on your ${mostUrgent.position}.';
              HapticFeedback.lightImpact();
            }
          }

          setState(() {
            _statusMessage = spokenAlert;
          });
          await widget.ttsService.speak(spokenAlert);
        } else if (mostUrgent.proximity == 'close' || mostUrgent.position == 'center') {
          // Acoustic Sonar Earcon: Subtle pulse without repetitive verbal chatter
          if (widget.storageService.sonarCuesEnabled) {
            SystemSound.play(SystemSoundType.click);
          }
          HapticFeedback.selectionClick();
        }
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Live frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<XFile?> _captureImageSafely() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return null;
    final bool wasStreaming = _isLiveMonitoringActive;
    if (wasStreaming) {
      await _stopLiveObstacleMonitoring();
      await Future.delayed(const Duration(milliseconds: 150));
    }
    try {
      return await _cameraController!.takePicture();
    } finally {
      if (wasStreaming && mounted) {
        _startLiveObstacleMonitoring();
      }
    }
  }

  Future<void> _runInitialVisionAction(
    String action,
    String? arg, {
    String? ocrMode,
    bool isSavedLookup = false,
    String? savedNotes,
  }) async {
    switch (action) {
      case 'describe':
        await _describeSurroundings();
        break;
      case 'detect':
        await _detectObjects();
        break;
      case 'ocr':
        final mode = ocrMode == 'all'
            ? OcrReadingMode.all
            : (ocrMode == 'continue' ? OcrReadingMode.continueReading : OcrReadingMode.smart);
        await _readText(mode: mode);
        break;
      case 'currency':
        await _recognizeCurrency();
        break;
      case 'bus':
        await _recognizeBusRoute();
        break;
      case 'trafficLight':
        await _checkTrafficLight();
        break;
      case 'find':
        await _findItem(arg ?? 'item', isSavedLookup: isSavedLookup, savedNotes: savedNotes);
        break;
      case 'torch':
        final state = arg == 'on' ? true : (arg == 'off' ? false : null);
        await _toggleTorch(state);
        break;
      case 'toggleAlerts':
        if (_isLiveMonitoringActive) {
          await _stopLiveObstacleMonitoring();
          await widget.ttsService.speak(
            widget.ttsService.isKannada ? 'ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ವಿರಾಮಗೊಳಿಸಲಾಗಿದೆ.' : 'Live obstacle alerts paused.',
          );
        } else {
          _startLiveObstacleMonitoring();
          await widget.ttsService.speak(
            widget.ttsService.isKannada ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು ಸಕ್ರಿಯವಾಗಿವೆ.' : 'Live obstacle alerts active.',
          );
        }
        break;
      default:
        await _describeSurroundings();
        break;
    }
  }

  void _safeDeleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.delete().catchError((_) => file);
      }
    } catch (_) {}
  }

  void _triggerEmergency() {
    HapticFeedback.heavyImpact();
    final contact = widget.storageService.emergencyContact;
    final isKn = widget.ttsService.isKannada;
    widget.ttsService.emergencySpeak(
      isKn
          ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ತುರ್ತು ಸಂಪರ್ಕ: $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
          : 'Emergency alert activated. Emergency contact is $contact. Calling 112 if needed.',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeatureDetailScreen(
          title: isKn ? 'ತುರ್ತು ಸಹಾಯ' : 'Emergency SOS',
          status: isKn ? 'ಲಭ್ಯವಿದೆ' : 'Active',
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

  Future<void> _describeSurroundings() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _cameraController!.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final description = await _visionService.describeSceneFromPath(
        xFile.path,
        imageWidth: width,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = description;
      });
      await widget.ttsService.speak(description);
    } catch (e) {
      debugPrint('Describe surroundings error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ ಪಡೆಯಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not inspect surroundings: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  Future<void> _detectObjects() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _cameraController!.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final items = await _visionService.detectObjectsFromPath(
        xFile.path,
        imageWidth: width,
      );

      final bool isKn = widget.ttsService.isKannada;
      final String message;
      if (items.isEmpty) {
        message = isKn
            ? 'ನೇರವಾಗಿ ಮುಂದೆ ಯಾವುದೇ ಅಡೆತಡೆಗಳು ಅಥವಾ ವಸ್ತುಗಳು ಪತ್ತೆಯಾಗಿಲ್ಲ.'
            : 'No obstacles or objects detected directly ahead.';
      } else {
        if (isKn) {
          final summary = items.map((i) {
            final labelKn = VisionService.translateLabelToKannada(i.label);
            final posKn = i.position == 'left'
                ? 'ಎಡಕ್ಕೆ'
                : (i.position == 'right' ? 'ಬಲಕ್ಕೆ' : 'ಮುಂದೆ');
            return '$labelKn ನಿಮ್ಮ $posKn';
          }).toSet().join(', ');
          message = 'ಪತ್ತೆಯಾದವು: $summary.';
        } else {
          final summary = items.map((i) => '${i.label} on your ${i.position}').toSet().join(', ');
          message = 'Detected: $summary.';
        }
      }

      setState(() {
        _statusMessage = message;
      });
      await widget.ttsService.speak(message);
    } catch (e) {
      debugPrint('Detect objects error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ವಸ್ತುಗಳನ್ನು ಪತ್ತೆಹಚ್ಚಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not detect objects: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  Future<void> _readText({OcrReadingMode mode = OcrReadingMode.smart}) async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final text = await _visionService.recognizeTextFromPath(
        xFile.path,
        mode: mode,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = text;
      });
      await widget.ttsService.speak(text);
    } catch (e) {
      debugPrint('Read text error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಪಠ್ಯವನ್ನು ಓದಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Unable to read text: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  Future<void> _findItem(
    String target, {
    bool isSavedLookup = false,
    String? savedNotes,
  }) async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _cameraController!.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final result = await _visionService.searchForObject(
        xFile.path,
        target,
        imageWidth: width,
        isSavedLookup: isSavedLookup,
        savedNotes: savedNotes,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = result;
      });
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Find item error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? '$target ಹುಡುಕಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not search for $target: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  Future<void> _recognizeCurrency() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final result = await _visionService.recognizeCurrency(
        xFile.path,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = result;
      });
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Recognize currency error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕರೆನ್ಸಿ ಪರಿಶೀಲಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not check currency: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  /// Inspects approaching city bus to announce route number and destination board.
  Future<void> _recognizeBusRoute() async {
    final xfile = await _captureImageSafely();
    if (xfile == null) return;
    String? tempPath = xfile.path;
    try {
      final isKn = widget.ttsService.isKannada;
      final result = await _visionService.recognizeBusRoute(tempPath, isKannada: isKn);
      if (!mounted) return;
      setState(() {
        _statusMessage = result;
      });
      HapticFeedback.mediumImpact();
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Recognize bus route error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada
            ? 'ಬಸ್ ಸಂಖ್ಯೆ ಗುರುತಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
            : 'Could not read bus route: $e',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  /// Inspects oncoming traffic light color and pedestrian crossing signals.
  Future<void> _checkTrafficLight() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    await widget.ttsService.stop();
    HapticFeedback.mediumImpact();
    final isKn = widget.ttsService.isKannada;
    await widget.ttsService.speak(
      isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...' : 'Checking traffic signal...',
    );

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;

      final analysis = await _visionService.analyzeTrafficSignal(
        xFile.path,
        isKannada: isKn,
      );

      if (analysis.state == TrafficSignalState.red || analysis.state == TrafficSignalState.stopSign) {
        HapticFeedback.heavyImpact();
      } else if (analysis.state == TrafficSignalState.green) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }

      final speech = isKn ? analysis.descriptionKn : analysis.descriptionEn;
      if (mounted) {
        setState(() {
          _statusMessage = speech;
        });
      }
      await widget.ttsService.speak(speech);
    } catch (e) {
      debugPrint('[NavigationScreen] Traffic light inspection error: $e');
      await widget.ttsService.speak(
        isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.' : 'Unable to inspect traffic signal at this moment.',
      );
    } finally {
      if (tempPath != null) _safeDeleteFile(tempPath);
    }
  }

  /// Toggles device camera flashlight / torch for low-light obstacle & text detection.
  Future<void> _toggleTorch([bool? forceState]) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      final msg = widget.ttsService.isKannada
          ? 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧವಾಗಿಲ್ಲ.'
          : 'Camera is not ready.';
      await widget.ttsService.speak(msg);
      return;
    }
    try {
      final target = forceState ?? !_isTorchOn;
      await _cameraController!.setFlashMode(target ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() {
          _isTorchOn = target;
        });
      }
      HapticFeedback.mediumImpact();
      final feedback = target
          ? (widget.ttsService.isKannada ? 'ಬೆಳಕು ಆನ್ ಆಗಿದೆ.' : 'Flashlight on.')
          : (widget.ttsService.isKannada ? 'ಬೆಳಕು ಆಫ್ ಆಗಿದೆ.' : 'Flashlight off.');
      await widget.ttsService.speak(feedback);
    } catch (e) {
      final err = widget.ttsService.isKannada
          ? 'ಟಾರ್ಚ್ ನಿಯಂತ್ರಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
          : 'Unable to toggle flashlight.';
      await widget.ttsService.speak(err);
    }
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.stopNavigation:
      case VoiceCommandType.goBack:
        _stopNavigation();
        return true;

      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        _navService.startNavigationToDestination(destination);
        return true;

      case VoiceCommandType.whereAmI:
        _navService.announceCurrentLocation();
        return true;

      case VoiceCommandType.describeSurroundings:
        _describeSurroundings();
        return true;

      case VoiceCommandType.detectObjects:
        _detectObjects();
        return true;

      case VoiceCommandType.toggleObstacleAlerts:
        if (_isLiveMonitoringActive) {
          _stopLiveObstacleMonitoring();
          widget.ttsService.speak('Live obstacle alerts paused.');
        } else {
          _startLiveObstacleMonitoring();
          widget.ttsService.speak('Live obstacle alerts active.');
        }
        return true;

      case VoiceCommandType.toggleTorch:
        if (command.argument == 'on') {
          _toggleTorch(true);
        } else if (command.argument == 'off') {
          _toggleTorch(false);
        } else {
          _toggleTorch();
        }
        return true;

      case VoiceCommandType.aroundMe:
        _navService.announceNearbyAmenities();
        return true;

      case VoiceCommandType.facingDirection:
        _navService.announceFacingDirection();
        return true;

      case VoiceCommandType.readText:
        final mode = command.argument == 'all'
            ? OcrReadingMode.all
            : (command.argument == 'continue' ? OcrReadingMode.continueReading : OcrReadingMode.smart);
        _readText(mode: mode);
        return true;

      case VoiceCommandType.findItem:
        final item = command.argument ?? 'item';
        final isSaved = command.rawText.toLowerCase().contains('saved') ||
            command.rawText.toLowerCase().contains('leave') ||
            command.rawText.toLowerCase().contains('left') ||
            command.rawText.toLowerCase().contains('put');
        _findItem(item, isSavedLookup: isSaved);
        return true;

      case VoiceCommandType.recognizeCurrency:
        _recognizeCurrency();
        return true;

      case VoiceCommandType.readBusRoute:
        _recognizeBusRoute();
        return true;

      case VoiceCommandType.checkTrafficLight:
        _checkTrafficLight();
        return true;

      case VoiceCommandType.saveFavoritePlace:
        final tag = command.argument ?? 'home';
        _navService.saveCurrentLocationAsFavorite(tag: tag);
        return true;

      case VoiceCommandType.repeat:
        if (_navService.isNavigating) {
          _navService.repeatCurrentInstruction();
        } else if (_visionService.lastRecognizedText.isNotEmpty) {
          widget.ttsService.speak(_visionService.lastRecognizedText);
        } else {
          widget.ttsService.repeat();
        }
        return true;

      case VoiceCommandType.help:
        widget.ttsService.speak(
          'In camera mode, you can say: What can you see, Read the sign, Detect objects, Find an item, Where am I, Take me to a destination, or Stop navigation.',
        );
        return true;

      case VoiceCommandType.stopSpeaking:
        widget.ttsService.stop();
        return true;

      case VoiceCommandType.stopListening:
        if (widget.voiceCoordinator != null) {
          widget.voiceCoordinator!.stopListening(spokenFeedback: true);
        } else {
          widget.speechService.stopListening();
          widget.ttsService.speak('Stopped listening.');
        }
        return true;

      default:
        return false; // Delegate back to coordinator for global commands
    }
  }

  Future<void> _handleMicToggle() async {
    if (widget.voiceCoordinator != null) {
      await widget.voiceCoordinator!.toggleListening();
      return;
    }

    final speechService = widget.speechService;
    final ttsService = widget.ttsService;

    if (speechService.isListening) {
      await speechService.stopListening();
      await ttsService.speak('Stopped listening.');
    } else {
      await ttsService.stop();
      final started = await speechService.startListening(
        localeId: widget.storageService.appLanguage == 'kn' ? 'kn_IN' : 'en_US',
        onResult: (text, isFinal) async {
          if (isFinal && text.trim().isNotEmpty) {
            await speechService.stopListening();
            _executeVoiceCommand(text);
          }
        },
      );
      if (!started) {
        final err = speechService.lastError ?? 'Unable to activate microphone.';
        await ttsService.speak(err);
      }
    }
  }

  void _executeVoiceCommand(String rawText) {
    final assistantName = widget.storageService.assistantName;
    final cmd = VoiceCommandParser.parse(rawText, assistantName);

    if (handleVoiceCommand(cmd)) return;

    widget.ttsService.speak(
      'You said: ${cmd.rawText}. Say Where am I, Take me to a destination, or Stop navigation.',
    );
  }

  void _stopNavigation() {
    _navService.stopNavigation();
    widget.ttsService.speak('Navigation stopped. Returning to home screen.');
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.voiceCoordinator?.unregisterDelegate(this);
    _navService.removeListener(_onNavServiceUpdated);
    _stopLiveObstacleMonitoring();
    if (_isTorchOn) {
      try {
        _cameraController?.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
    if (_isLocalNavService) {
      _navService.dispose();
    }
    if (_isLocalVisionService) {
      _visionService.dispose();
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assistantName = widget.storageService.assistantName;
    final bool isKn = widget.ttsService.isKannada;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _navService.isNavigating
              ? (isKn ? 'ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನ' : 'Pedestrian Guidance')
              : (isKn ? 'ಕ್ಯಾಮೆರಾ ನ್ಯಾವಿಗೇಷನ್' : 'Live Navigation Camera'),
        ),
        leading: Semantics(
          label: isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ನಿಲ್ಲಿಸಿ ಮತ್ತು ಮನೆಗೆ ಮರಳಿ' : 'Stop Navigation and return home',
          hint: isKn ? 'ಕ್ಯಾಮೆರಾ ಮುಚ್ಚಿ ಮನೆ ಪರದೆಗೆ ಮರಳುತ್ತದೆ' : 'Exits camera mode and returns to home screen',
          child: IconButton(
            icon: const Icon(Icons.close, size: 30),
            onPressed: _stopNavigation,
          ),
        ),
        actions: [
          Semantics(
            label: isKn
                ? (_isTorchOn ? 'ಬೆಳಕು ಆಫ್ ಮಾಡಿ' : 'ಬೆಳಕು ಆನ್ ಮಾಡಿ')
                : (_isTorchOn ? 'Turn off flashlight' : 'Turn on flashlight'),
            hint: isKn ? 'ಕ್ಯಾಮೆರಾ ಬೆಳಕನ್ನು ನಿಯಂತ್ರಿಸುತ್ತದೆ' : 'Controls camera torch light',
            child: IconButton(
              icon: Icon(
                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isTorchOn ? AppTheme.accentYellow : AppTheme.textPrimary,
                size: 28,
              ),
              onPressed: () => _toggleTorch(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Semantics(
          label: isKn
              ? '$assistantName ಜೊತೆ ಮಾತನಾಡಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ, ಅಥವಾ ಸ್ಥಿತಿ ಕೇಳಲು ಒಮ್ಮೆ ಟ್ಯಾಪ್ ಮಾಡಿ'
              : 'Single tap to hear status, double tap to talk to $assistantName, or swipe horizontally to toggle flashlight',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              HapticFeedback.selectionClick();
              if (_navService.isNavigating) {
                _navService.repeatCurrentInstruction();
              } else {
                widget.ttsService.speak(_statusMessage);
              }
            },
            onDoubleTap: _handleMicToggle,
            onLongPress: _triggerEmergency,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 200) {
                _toggleTorch();
              }
            },
            child: Column(
              children: [
                // Safety Disclaimer Banner
                Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isKn
                              ? 'ಸುರಕ್ಷತೆ: ಯಾವಾಗಲೂ ನಿಮ್ಮ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಬಳಸಿ. ಕ್ಯಾಮೆರಾವನ್ನು ಮಾತ್ರ ಅವಲಂಬಿಸಬೇಡಿ.'
                              : 'SAFETY: Always use your cane or mobility aid. Never rely on camera alone.',
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

                // Camera & GPS Viewport
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isCameraInitialized && _cameraController != null)
                        CameraPreview(_cameraController!)
                      else
                        Container(
                          color: Colors.black,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isPermissionDenied
                                        ? Icons.no_photography
                                        : Icons.camera_alt,
                                    size: 64,
                                    color: _isPermissionDenied
                                        ? AppTheme.danger
                                        : AppTheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _statusMessage,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: AppTheme.textPrimary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_isPermissionDenied) ...[
                                    const SizedBox(height: 16),
                                    AccessibleButton(
                                      label: isKn ? 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ' : 'Open App Settings',
                                      icon: Icons.settings,
                                      onPressed: () => openAppSettings(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Overlay Guidance Card (GPS Turn-by-Turn or Camera Status)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _navService.isNavigating
                                    ? AppTheme.accentCyan
                                    : (_isCameraInitialized
                                        ? AppTheme.success
                                        : AppTheme.primary),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _navService.isNavigating
                                      ? Icons.directions_walk
                                      : (_isCameraInitialized
                                          ? Icons.videocam
                                          : Icons.hourglass_top),
                                  color: _navService.isNavigating
                                      ? AppTheme.accentCyan
                                      : (_isCameraInitialized
                                          ? AppTheme.success
                                          : AppTheme.primary),
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_navService.isNavigating && _navService.currentRoute != null)
                                        Text(
                                          isKn
                                              ? 'ಗಮ್ಯಸ್ಥಾನ: ${_navService.currentRoute!.destinationName}'
                                              : 'To: ${_navService.currentRoute!.destinationName}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.accentCyan,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      Text(
                                        _navService.isNavigating
                                            ? _navService.statusMessage
                                            : _statusMessage,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Navigation Controls
                Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Microphone Button
                      AnimatedBuilder(
                        animation: widget.speechService,
                        builder: (context, _) {
                          return MicButton(
                            isListening: widget.speechService.isListening,
                            onTap: _handleMicToggle,
                            assistantName: assistantName,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AccessibleButton(
                              label: _isLiveMonitoringActive
                                  ? (isKn ? 'ಅಡೆತಡೆ: ಆನ್' : 'Alerts: ON')
                                  : (isKn ? 'ಅಡೆತಡೆ: ಆಫ್' : 'Alerts: OFF'),
                              icon: _isLiveMonitoringActive ? Icons.notifications_active : Icons.notifications_off,
                              backgroundColor: _isLiveMonitoringActive ? AppTheme.surfaceHighlight : AppTheme.surface,
                              textColor: _isLiveMonitoringActive ? AppTheme.accentCyan : AppTheme.textMuted,
                              semanticHint: isKn
                                  ? 'ನೈಜ ಸಮಯದ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ಆನ್/ಆಫ್ ಮಾಡುತ್ತದೆ'
                                  : 'Toggles real-time continuous obstacle announcements',
                              onPressed: () async {
                                if (_isLiveMonitoringActive) {
                                  await _stopLiveObstacleMonitoring();
                                  await widget.ttsService.speak(
                                    isKn ? 'ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ವಿರಾಮಗೊಳಿಸಲಾಗಿದೆ.' : 'Live obstacle alerts paused.',
                                  );
                                } else {
                                  _startLiveObstacleMonitoring();
                                  await widget.ttsService.speak(
                                    isKn ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು ಸಕ್ರಿಯವಾಗಿವೆ.' : 'Live obstacle alerts active.',
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleButton(
                              label: _navService.isNavigating
                                  ? (isKn ? 'ನನ್ನ ಸ್ಥಳ' : 'Where Am I')
                                  : (isKn ? 'ವಿವರಣೆ' : 'Describe'),
                              icon: _navService.isNavigating ? Icons.my_location : Icons.visibility,
                              semanticLabel: _navService.isNavigating
                                  ? (isKn ? 'ಪ್ರಸ್ತುತ ಸ್ಥಳ ಹೇಳಿ' : 'Speak current location')
                                  : (isKn ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ' : 'Describe surroundings'),
                              semanticHint: _navService.isNavigating
                                  ? (isKn ? 'ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ವಿಳಾಸವನ್ನು ಹೇಳುತ್ತದೆ' : 'Speaks current GPS street address')
                                  : (isKn ? 'ಕ್ಯಾಮೆರಾ ಬಳಸಿ ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ ನೀಡುತ್ತದೆ' : 'Describes surroundings using camera'),
                              onPressed: () {
                                if (_navService.isNavigating) {
                                  _navService.announceCurrentLocation();
                                } else {
                                  _describeSurroundings();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AccessibleButton(
                              label: isKn ? 'ಮತ್ತೆ ಹೇಳಿ' : 'Repeat',
                              icon: Icons.replay,
                              semanticHint: isKn ? 'ಕೊನೆಯ ಮಾರ್ಗದರ್ಶನವನ್ನು ಮತ್ತೆ ಹೇಳುತ್ತದೆ' : 'Repeats the last instruction',
                              onPressed: () {
                                if (_navService.isNavigating) {
                                  _navService.repeatCurrentInstruction();
                                } else {
                                  widget.ttsService.repeat();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleButton(
                              label: isKn ? 'ನಿಲ್ಲಿಸಿ' : 'Stop',
                              icon: Icons.stop_circle,
                              isDestructive: true,
                              semanticHint: isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ಮುಗಿಸಿ ಮನೆ ಪರದೆಗೆ ಮರಳುತ್ತದೆ' : 'Exits navigation and returns to home screen',
                              onPressed: _stopNavigation,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
