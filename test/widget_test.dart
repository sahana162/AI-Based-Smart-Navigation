import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blind_navigation/core/services/storage_service.dart';
import 'package:blind_navigation/core/services/voice_command_parser.dart';
import 'package:blind_navigation/models/voice_command.dart';
import 'package:blind_navigation/models/navigation_step.dart';
import 'package:blind_navigation/core/services/tts_service.dart';
import 'package:blind_navigation/core/services/speech_service.dart';
import 'package:blind_navigation/core/services/voice_session_coordinator.dart';
import 'package:blind_navigation/ui/screens/feature_detail_screen.dart';
import 'package:blind_navigation/ui/screens/settings_screen.dart';
import 'package:blind_navigation/core/services/vision_service.dart';
import 'package:blind_navigation/core/services/object_detector_service.dart';
import 'package:blind_navigation/main.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (MethodCall call) async {
      return 1;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('speech_to_text'), (MethodCall call) async {
      return true;
    });
  });

  group('VoiceCommandParser Tests', () {
    test('parses start navigation with default assistant name', () {
      final cmd = VoiceCommandParser.parse('Alice, start navigation', 'Alice');
      expect(cmd.type, VoiceCommandType.startNavigation);
    });

    test('parses start navigation without name prefix', () {
      final cmd = VoiceCommandParser.parse('start navigation', 'Alice');
      expect(cmd.type, VoiceCommandType.startNavigation);
    });

    test('parses stop navigation', () {
      final cmd = VoiceCommandParser.parse('stop navigation', 'Alice');
      expect(cmd.type, VoiceCommandType.stopNavigation);
    });

    test('parses describe surroundings with hey prefix', () {
      final cmd = VoiceCommandParser.parse('hey Alice, describe surroundings', 'Alice');
      expect(cmd.type, VoiceCommandType.describeSurroundings);
    });

    test('parses read text command', () {
      final cmd = VoiceCommandParser.parse('Alice read text', 'Alice');
      expect(cmd.type, VoiceCommandType.readText);
    });

    test('parses find item command with argument', () {
      final cmd = VoiceCommandParser.parse('find my keys', 'Alice');
      expect(cmd.type, VoiceCommandType.findItem);
      expect(cmd.argument, 'my keys');
    });

    test('parses repeat and help commands', () {
      expect(VoiceCommandParser.parse('repeat', 'Alice').type, VoiceCommandType.repeat);
      expect(VoiceCommandParser.parse('help', 'Alice').type, VoiceCommandType.help);
      expect(VoiceCommandParser.parse('open settings', 'Alice').type, VoiceCommandType.openSettings);
      expect(VoiceCommandParser.parse('be quiet', 'Alice').type, VoiceCommandType.stopSpeaking);
    });

    test('supports customized assistant name', () {
      final cmd = VoiceCommandParser.parse('Nova, start navigation', 'Nova');
      expect(cmd.type, VoiceCommandType.startNavigation);
    });

    test('parses take me to destination command', () {
      final cmd = VoiceCommandParser.parse('Hey Alice, take me to Central Station', 'Alice');
      expect(cmd.type, VoiceCommandType.takeMeTo);
      expect(cmd.argument, 'central station');
    });

    test('parses where am I location command', () {
      final cmd = VoiceCommandParser.parse('Where am I', 'Alice');
      expect(cmd.type, VoiceCommandType.whereAmI);
    });

    test('parses detect objects and recognize currency commands', () {
      expect(VoiceCommandParser.parse('detect objects', 'Alice').type, VoiceCommandType.detectObjects);
      expect(VoiceCommandParser.parse('recognize currency', 'Alice').type, VoiceCommandType.recognizeCurrency);
    });

    test('parses navigation and speech speed controls', () {
      expect(VoiceCommandParser.parse('go back', 'Alice').type, VoiceCommandType.goBack);
      expect(VoiceCommandParser.parse('increase speech speed', 'Alice').type, VoiceCommandType.increaseSpeechSpeed);
      expect(VoiceCommandParser.parse('decrease speech speed', 'Alice').type, VoiceCommandType.decreaseSpeechSpeed);
      expect(VoiceCommandParser.parse('stop listening', 'Alice').type, VoiceCommandType.stopListening);
      expect(VoiceCommandParser.parse('emergency', 'Alice').type, VoiceCommandType.emergency);
      expect(VoiceCommandParser.parse('toggle obstacle alerts', 'Alice').type, VoiceCommandType.toggleObstacleAlerts);
      expect(VoiceCommandParser.parse('pause alerts', 'Alice').type, VoiceCommandType.toggleObstacleAlerts);
    });

    test('parses around me, toggle torch, and battery status commands', () {
      final around1 = VoiceCommandParser.parse('around me', 'Alice');
      expect(around1.type, VoiceCommandType.aroundMe);

      final around2 = VoiceCommandParser.parse('what is around me', 'Alice');
      expect(around2.type, VoiceCommandType.aroundMe);

      final aroundKn = VoiceCommandParser.parse('ಏನಿದೆ ಸುತ್ತಮುತ್ತ', 'Alice');
      expect(aroundKn.type, VoiceCommandType.aroundMe);

      final torchOn = VoiceCommandParser.parse('turn on torch', 'Alice');
      expect(torchOn.type, VoiceCommandType.toggleTorch);
      expect(torchOn.argument, 'on');

      final torchOff = VoiceCommandParser.parse('turn off flashlight', 'Alice');
      expect(torchOff.type, VoiceCommandType.toggleTorch);
      expect(torchOff.argument, 'off');

      final torchToggle = VoiceCommandParser.parse('toggle torch', 'Alice');
      expect(torchToggle.type, VoiceCommandType.toggleTorch);

      final torchKn = VoiceCommandParser.parse('ಟಾರ್ಚ್ ಆನ್ ಮಾಡಿ', 'Alice');
      expect(torchKn.type, VoiceCommandType.toggleTorch);
      expect(torchKn.argument, 'on');

      final battery = VoiceCommandParser.parse('battery status', 'Alice');
      expect(battery.type, VoiceCommandType.batteryStatus);

      final batteryKn = VoiceCommandParser.parse('ಬ್ಯಾಟರಿ ಸ್ಥಿತಿ', 'Alice');
      expect(batteryKn.type, VoiceCommandType.batteryStatus);

      final busEn = VoiceCommandParser.parse('what bus is this', 'Alice');
      expect(busEn.type, VoiceCommandType.readBusRoute);

      final busBoardEn = VoiceCommandParser.parse('read bus board', 'Alice');
      expect(busBoardEn.type, VoiceCommandType.readBusRoute);

      final busKn = VoiceCommandParser.parse('ಬಸ್ ಸಂಖ್ಯೆ ಓದಿ', 'Alice');
      expect(busKn.type, VoiceCommandType.readBusRoute);

      final busKn2 = VoiceCommandParser.parse('ಯಾವ ಬಸ್', 'Alice');
      expect(busKn2.type, VoiceCommandType.readBusRoute);

      final busBoardKn = VoiceCommandParser.parse('ಬಸ್ ಬೋರ್ಡ್ ಓದಿ', 'Alice');
      expect(busBoardKn.type, VoiceCommandType.readBusRoute);

      final aroundKn2 = VoiceCommandParser.parse('ಸುತ್ತಲೂ ಏನಿದೆ', 'Alice');
      expect(aroundKn2.type, VoiceCommandType.aroundMe);

      final facingEn1 = VoiceCommandParser.parse('which way am I facing', 'Alice');
      expect(facingEn1.type, VoiceCommandType.facingDirection);

      final facingEn2 = VoiceCommandParser.parse('compass heading', 'Alice');
      expect(facingEn2.type, VoiceCommandType.facingDirection);

      final facingKn1 = VoiceCommandParser.parse('ಯಾವ ದಿಕ್ಕಿಗೆ ಮುಖ ಮಾಡಿದ್ದೇನೆ', 'Alice');
      expect(facingKn1.type, VoiceCommandType.facingDirection);

      final facingKn2 = VoiceCommandParser.parse('ದಿಕ್ಕು ಯಾವುದು', 'Alice');
      expect(facingKn2.type, VoiceCommandType.facingDirection);

      // Traffic light / Crossing check commands
      final trafficEn1 = VoiceCommandParser.parse('check traffic light', 'Alice');
      expect(trafficEn1.type, VoiceCommandType.checkTrafficLight);

      final trafficEn2 = VoiceCommandParser.parse('is it safe to cross', 'Alice');
      expect(trafficEn2.type, VoiceCommandType.checkTrafficLight);

      final trafficEn3 = VoiceCommandParser.parse('crossing signal', 'Alice');
      expect(trafficEn3.type, VoiceCommandType.checkTrafficLight);

      final trafficKn1 = VoiceCommandParser.parse('ಟ್ರ್ಯಾಫಿಕ್ ಲೈಟ್ ಚೆಕ್ ಮಾಡು', 'Alice');
      expect(trafficKn1.type, VoiceCommandType.checkTrafficLight);

      final trafficKn2 = VoiceCommandParser.parse('ರಸ್ತೆ ದಾಟಲು ಸುರಕ್ಷಿತವೇ', 'Alice');
      expect(trafficKn2.type, VoiceCommandType.checkTrafficLight);

      // Save favorite places commands
      final favHome = VoiceCommandParser.parse('save as home', 'Alice');
      expect(favHome.type, VoiceCommandType.saveFavoritePlace);
      expect(favHome.argument, 'home');

      final favWork = VoiceCommandParser.parse('save current location as work', 'Alice');
      expect(favWork.type, VoiceCommandType.saveFavoritePlace);
      expect(favWork.argument, 'work');

      final favHomeKn = VoiceCommandParser.parse('ಮನೆಯಾಗಿ ಉಳಿಸು', 'Alice');
      expect(favHomeKn.type, VoiceCommandType.saveFavoritePlace);
      expect(favHomeKn.argument, 'home');

      final favWorkKn = VoiceCommandParser.parse('ಕಚೇರಿಯಾಗಿ ಉಳಿಸು', 'Alice');
      expect(favWorkKn.type, VoiceCommandType.saveFavoritePlace);
      expect(favWorkKn.argument, 'work');
    });
  });

  group('StorageService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to Alice for assistant name', () async {
      final storage = await StorageService.initialize();
      expect(storage.assistantName, 'Alice');
    });

    test('persists custom assistant name', () async {
      final storage = await StorageService.initialize();
      await storage.setAssistantName('Companion');
      expect(storage.assistantName, 'Companion');
    });

    test('persists speech rate and resets to defaults', () async {
      final storage = await StorageService.initialize();
      await storage.setSpeechRate(0.8);
      expect(storage.speechRate, 0.8);

      await storage.resetToDefaults();
      expect(storage.assistantName, 'Alice');
      expect(storage.speechRate, 0.5);
    });

    test('persists emergency contact and saved items', () async {
      final storage = await StorageService.initialize();
      expect(storage.emergencyContact, '112');

      await storage.setEmergencyContact('+1234567890');
      expect(storage.emergencyContact, '+1234567890');

      await storage.addSavedItem('White Cane', notes: 'Near the front door');
      expect(storage.savedItems.length, 1);
      expect(storage.savedItems.first['name'], 'White Cane');

      await storage.removeSavedItem('White Cane');
      expect(storage.savedItems.isEmpty, true);

      await storage.resetToDefaults();
      expect(storage.emergencyContact, '112');
      expect(storage.savedItems.isEmpty, true);
    });

    test('persists sonar cues and auto-torch preferences', () async {
      final storage = await StorageService.initialize();
      expect(storage.sonarCuesEnabled, true);
      expect(storage.autoTorchEnabled, true);

      await storage.setSonarCuesEnabled(false);
      await storage.setAutoTorchEnabled(false);
      expect(storage.sonarCuesEnabled, false);
      expect(storage.autoTorchEnabled, false);

      await storage.resetToDefaults();
      expect(storage.sonarCuesEnabled, true);
      expect(storage.autoTorchEnabled, true);
    });

    test('persists directional turn haptics and favorite places', () async {
      final storage = await StorageService.initialize();
      expect(storage.directionalHapticsEnabled, true);

      await storage.setDirectionalHapticsEnabled(false);
      expect(storage.directionalHapticsEnabled, false);

      expect(storage.favoritePlaces.isEmpty, true);
      await storage.saveFavoritePlace(
        'home',
        lat: 12.9716,
        lon: 77.5946,
        name: 'Home',
        address: 'MG Road, Bangalore',
      );

      expect(storage.favoritePlaces.containsKey('home'), true);
      final homeData = storage.getFavoritePlace('home');
      expect(homeData?['lat'], 12.9716);
      expect(homeData?['lon'], 77.5946);
      expect(homeData?['name'], 'Home');

      await storage.removeFavoritePlace('home');
      expect(storage.getFavoritePlace('home'), isNull);

      await storage.saveFavoritePlace(
        'work',
        lat: 12.9352,
        lon: 77.6245,
        name: 'Work',
      );
      expect(storage.favoritePlaces.length, 1);
      await storage.clearFavoritePlaces();
      expect(storage.favoritePlaces.isEmpty, true);

      await storage.resetToDefaults();
      expect(storage.directionalHapticsEnabled, true);
    });
  });

  group('Pedestrian Navigation Unit Tests', () {
    test('spokenInstruction generates correct turn descriptions', () {
      const step = PedestrianStep(
        instruction: 'Continue onto Oak Street',
        streetName: 'Oak Street',
        maneuverType: 'turn',
        maneuverModifier: 'left',
        distanceMeters: 45.0,
        durationSeconds: 30.0,
        waypointLat: 12.9716,
        waypointLng: 77.5946,
      );

      expect(step.spokenInstruction(remainingMeters: 45), 'In 45 meters, turn left onto Oak Street.');
      expect(step.spokenInstruction(remainingMeters: 5), 'turn left onto Oak Street now.');
    });

    test('spokenInstruction generates bilingual Kannada and clock direction guidance', () {
      const step = PedestrianStep(
        instruction: 'Continue onto Oak Street',
        streetName: 'Oak Street',
        maneuverType: 'turn',
        maneuverModifier: 'left',
        distanceMeters: 45.0,
        durationSeconds: 30.0,
        waypointLat: 12.9716,
        waypointLng: 77.5946,
      );

      expect(
        step.spokenInstruction(remainingMeters: 45, isKannada: true),
        '45 ಮೀಟರ್‌ಗಳಲ್ಲಿ, Oak Street ಕಡೆಗೆ ಎಡಕ್ಕೆ ತಿರುಗಿ.',
      );
      expect(
        step.spokenInstruction(remainingMeters: 5, isKannada: true),
        'ಈಗ Oak Street ಕಡೆಗೆ ಎಡಕ್ಕೆ ತಿರುಗಿ.',
      );

      // Relative clock direction (90 degrees = to your right, 3 o'clock)
      expect(
        step.spokenInstruction(remainingMeters: 45, relativeBearingDegrees: 90),
        'In 45 meters, turn left onto Oak Street (to your right, 3 o\'clock).',
      );
      expect(
        step.spokenInstruction(remainingMeters: 5, isKannada: true, relativeBearingDegrees: 90),
        'ಈಗ Oak Street ಕಡೆಗೆ ಎಡಕ್ಕೆ ತಿರುಗಿ (ಬಲಕ್ಕೆ, 3 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ).',
      );
    });

    test('spokenInstruction announces arrival correctly', () {
      const step = PedestrianStep(
        instruction: 'Arrive at destination',
        streetName: '',
        maneuverType: 'arrive',
        maneuverModifier: '',
        distanceMeters: 10.0,
        durationSeconds: 8.0,
        waypointLat: 12.9716,
        waypointLng: 77.5946,
      );

      expect(step.spokenInstruction(remainingMeters: 5), 'You have arrived at your destination.');
      expect(step.spokenInstruction(remainingMeters: 5, isKannada: true), 'ನೀವು ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪಿದ್ದೀರಿ.');
    });
  });

  group('Kannada Voice Command Tests', () {
    test('parses Kannada start navigation', () {
      final cmd = VoiceCommandParser.parse('ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ', 'Alice');
      expect(cmd.type, VoiceCommandType.startNavigation);
    });

    test('parses Kannada describe surroundings', () {
      final cmd = VoiceCommandParser.parse('ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ', 'Alice');
      expect(cmd.type, VoiceCommandType.describeSurroundings);
    });

    test('parses Kannada emergency', () {
      final cmd = VoiceCommandParser.parse('ತುರ್ತು ಸಹಾಯ', 'Alice');
      expect(cmd.type, VoiceCommandType.emergency);
    });

    test('parses Kannada language switch', () {
      final cmd = VoiceCommandParser.parse('ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಿ', 'Alice');
      expect(cmd.type, VoiceCommandType.switchLanguage);
      expect(cmd.argument, 'kn');
    });

    test('parses Kannada save item and find item', () {
      final saveCmd = VoiceCommandParser.parse('ವಸ್ತು ಉಳಿಸಿ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್', 'Alice');
      expect(saveCmd.type, VoiceCommandType.saveItem);
      expect(saveCmd.argument, 'ವಾಕಿಂಗ್ ಸ್ಟಿಕ್');

      final findCmd = VoiceCommandParser.parse('ಹುಡುಕಿ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್', 'Alice');
      expect(findCmd.type, VoiceCommandType.findItem);
      expect(findCmd.argument, 'ವಾಕಿಂಗ್ ಸ್ಟಿಕ್');
    });

    test('parses natural Kannada SOV navigation and item search syntax', () {
      final navCmd = VoiceCommandParser.parse('ಮೆಜೆಸ್ಟಿಕ್ ಗೆ ದಾರಿ ತೋರಿಸಿ', 'Alice');
      expect(navCmd.type, VoiceCommandType.takeMeTo);
      expect(navCmd.argument, 'ಮೆಜೆಸ್ಟಿಕ್');

      final itemCmd = VoiceCommandParser.parse('ಕೀ ಹುಡುಕಿ', 'Alice');
      expect(itemCmd.type, VoiceCommandType.findItem);
      expect(itemCmd.argument, 'ಕೀ');

      final saveSovCmd = VoiceCommandParser.parse('ಕೀ ನೆನಪಿಡಿ', 'Alice');
      expect(saveSovCmd.type, VoiceCommandType.saveItem);
      expect(saveSovCmd.argument, 'ಕೀ');

      final saveSovCmd2 = VoiceCommandParser.parse('ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಉಳಿಸಿ', 'Alice');
      expect(saveSovCmd2.type, VoiceCommandType.saveItem);
      expect(saveSovCmd2.argument, 'ವಾಕಿಂಗ್ ಸ್ಟಿಕ್');
    });
  });

  group('HomeScreen Widget Smoke Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Smart Navigation home screen and controls', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();

      await tester.pumpWidget(BlindNavigationApp(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tts.stop();
      await tester.pump();

      // Verify branding and assistant centered identity (Rule 3)
      expect(find.text('Smart Navigation'), findsOneWidget);
      expect(find.textContaining('Assistant: Alice'), findsOneWidget);
      expect(find.text('Your AI Navigation Companion'), findsOneWidget);

      // Verify Rule 3 large central touch area and minimal status indicator
      expect(find.text('Tap to Talk to Alice'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      // Verify accessible secondary controls
      expect(find.text('Start Navigation (Camera)'), findsOneWidget);
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.text('Emergency Assistance'), findsOneWidget);

      // Verify quick tactile vision action chips
      expect(find.text('Describe'), findsOneWidget);
      expect(find.text('Read Text'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Find Item'), findsOneWidget);
    });
  });

  group('VoiceSessionCoordinator Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('dispatches commands to registered delegate', () async {
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();
      final navKey = GlobalKey<NavigatorState>();

      final coordinator = VoiceSessionCoordinator(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        navigatorKey: navKey,
      );

      final delegate = _MockDelegate();
      coordinator.registerDelegate(delegate);

      await coordinator.processRecognizedText('start navigation');
      expect(delegate.handledCommand?.type, VoiceCommandType.startNavigation);

      coordinator.unregisterDelegate(delegate);
      delegate.handledCommand = null;

      await coordinator.processRecognizedText('repeat');
      expect(delegate.handledCommand, isNull);
    });

    test('save item and find item persist and query correctly', () async {
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();
      final navKey = GlobalKey<NavigatorState>();

      final coordinator = VoiceSessionCoordinator(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        navigatorKey: navKey,
      );

      await coordinator.processRecognizedText('save my backpack');
      expect(storage.savedItems.length, 1);
      expect(storage.savedItems.first['name'], 'my backpack');

      // Now query the saved item
      await coordinator.processRecognizedText('find my backpack');
      expect(storage.savedItems.any((e) => e['name'] == 'my backpack'), isTrue);
    });

    test('handles unknown command without crashing', () async {
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();
      final navKey = GlobalKey<NavigatorState>();

      final coordinator = VoiceSessionCoordinator(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        navigatorKey: navKey,
      );

      await coordinator.processRecognizedText('blabla random gibberish phrase');
      expect(coordinator.statusText.contains('blabla random gibberish phrase'), isTrue);
    });
  });

  group('FeatureDetailScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Emergency Assistance with emergency contact and GPS button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = await StorageService.initialize();
      final tts = TtsService();

      await tester.pumpWidget(MaterialApp(
        home: FeatureDetailScreen(
          title: 'Emergency Assistance',
          status: 'Active',
          explanation: 'Immediate emergency services guidance.',
          technicalNotes: 'GPS and contact ready.',
          icon: Icons.emergency,
          ttsService: tts,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Emergency Assistance'), findsNWidgets(2));
      expect(find.textContaining('Primary Number: 112'), findsOneWidget);
      expect(find.text('Announce Emergency GPS Location'), findsOneWidget);
      expect(find.text('Repeat Spoken Details'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
    });

    testWidgets('renders interactive Try Feature Now action button for bus route reader', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = await StorageService.initialize();
      final tts = TtsService();

      await tester.pumpWidget(MaterialApp(
        home: FeatureDetailScreen(
          title: 'Bus Route Reader',
          status: 'Available',
          explanation: 'Reads oncoming city bus numbers and destination boards aloud.',
          technicalNotes: 'Real-time transit regex matching.',
          icon: Icons.directions_bus,
          ttsService: tts,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bus Route Reader'), findsNWidgets(2));
      expect(find.text('Scan Bus Route & Numbers Now'), findsOneWidget);
      expect(find.text('Repeat Spoken Details'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
    });

    testWidgets('renders interactive Try Feature Now action button for currency recognition', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = await StorageService.initialize();
      final tts = TtsService();

      await tester.pumpWidget(MaterialApp(
        home: FeatureDetailScreen(
          title: 'Currency Recognition',
          status: 'Available',
          explanation: 'Identify banknote values using camera.',
          technicalNotes: 'Color profiling and text recognition.',
          icon: Icons.payments,
          ttsService: tts,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Currency Recognition'), findsNWidgets(2));
      expect(find.text('Scan Banknotes Now'), findsOneWidget);
      expect(find.text('Repeat Spoken Details'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
    });
  });

  group('SettingsScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders language choices and switches to Kannada', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = await StorageService.initialize();
      final tts = TtsService();

      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          storageService: storage,
          ttsService: tts,
          onSettingsUpdated: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('ಕನ್ನಡ'), findsOneWidget);
      expect(find.text('Alice'), findsNWidgets(2));

      // Tap Kannada button
      await tester.tap(find.widgetWithText(ElevatedButton, 'ಕನ್ನಡ'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(storage.appLanguage, 'kn');
    });
  });

  group('Rule 5 Natural English Command Variations', () {
    const assistant = 'Alice';

    test('parses what can you see and describe surroundings variations', () {
      expect(VoiceCommandParser.parse('Alice, what can you see?', assistant).type, VoiceCommandType.describeSurroundings);
      expect(VoiceCommandParser.parse("What's around me?", assistant).type, VoiceCommandType.describeSurroundings);
      expect(VoiceCommandParser.parse('Describe my surroundings.', assistant).type, VoiceCommandType.describeSurroundings);
      expect(VoiceCommandParser.parse('Tell me what you see', assistant).type, VoiceCommandType.describeSurroundings);
      expect(VoiceCommandParser.parse('Look around', assistant).type, VoiceCommandType.describeSurroundings);
    });

    test('parses read text and sign variations', () {
      expect(VoiceCommandParser.parse('Read the sign in front of me.', assistant).type, VoiceCommandType.readText);
      expect(VoiceCommandParser.parse('Read the sign', assistant).type, VoiceCommandType.readText);
      expect(VoiceCommandParser.parse('What does the sign say?', assistant).type, VoiceCommandType.readText);
      expect(VoiceCommandParser.parse('Read document', assistant).type, VoiceCommandType.readText);
    });

    test('parses find item and live search queries', () {
      final cmd1 = VoiceCommandParser.parse('Can you find a bottle?', assistant);
      expect(cmd1.type, VoiceCommandType.findItem);
      expect(cmd1.argument, 'bottle');

      final cmd2 = VoiceCommandParser.parse('Where did I leave my keys?', assistant);
      expect(cmd2.type, VoiceCommandType.findItem);
      expect(cmd2.argument, 'my keys');

      final cmd3 = VoiceCommandParser.parse('Look for a cup', assistant);
      expect(cmd3.type, VoiceCommandType.findItem);
      expect(cmd3.argument, 'a cup');
    });

    test('parses destination and pedestrian routing variations', () {
      final cmd1 = VoiceCommandParser.parse('I want to go to the nearest pharmacy.', assistant);
      expect(cmd1.type, VoiceCommandType.takeMeTo);
      expect(cmd1.argument, 'the nearest pharmacy');

      final cmd2 = VoiceCommandParser.parse('Take me to the railway station.', assistant);
      expect(cmd2.type, VoiceCommandType.takeMeTo);
      expect(cmd2.argument, 'the railway station');

      final cmd3 = VoiceCommandParser.parse('How do I get to the hospital?', assistant);
      expect(cmd3.type, VoiceCommandType.takeMeTo);
      expect(cmd3.argument, 'the hospital');
    });

    test('parses location, repeat, speech speed, and navigation controls', () {
      expect(VoiceCommandParser.parse('Where am I?', assistant).type, VoiceCommandType.whereAmI);
      expect(VoiceCommandParser.parse('Repeat that, please.', assistant).type, VoiceCommandType.repeat);
      expect(VoiceCommandParser.parse('Speak a little slower.', assistant).type, VoiceCommandType.decreaseSpeechSpeed);
      expect(VoiceCommandParser.parse('Speak a little faster.', assistant).type, VoiceCommandType.increaseSpeechSpeed);
      expect(VoiceCommandParser.parse('Go back.', assistant).type, VoiceCommandType.goBack);
      expect(VoiceCommandParser.parse('Stop navigation.', assistant).type, VoiceCommandType.stopNavigation);
      expect(VoiceCommandParser.parse('Cancel navigation', assistant).type, VoiceCommandType.stopNavigation);
      expect(VoiceCommandParser.parse('What can you help me with?', assistant).type, VoiceCommandType.help);
    });
  });

  group('Rule 9 Live Search vs Saved Item Inventory', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('distinguishes live search for unsaved item vs saved items in StorageService', () async {
      final storage = await StorageService.initialize();

      // Item not saved yet
      expect(storage.savedItems.any((i) => i['name'] == 'water bottle'), isFalse);

      // Save an item explicitly
      await storage.addSavedItem('water bottle', notes: 'Kitchen counter');
      expect(storage.savedItems.length, 1);
      expect(storage.savedItems.first['name'], 'water bottle');
      expect(storage.savedItems.first['notes'], 'Kitchen counter');

      // Remove the item
      await storage.removeSavedItem('water bottle');
      expect(storage.savedItems.isEmpty, isTrue);
    });
  });

  group('Vision Service Data Model and Spatial Positioning', () {
    test('DetectedVisionItem correctly stores position and formatting', () {
      const leftItem = DetectedVisionItem(
        label: 'chair',
        confidence: 0.92,
        boundingBox: Rect.fromLTWH(50, 100, 100, 150),
        position: 'left',
      );
      expect(leftItem.position, 'left');
      expect(leftItem.label, 'chair');
      expect(leftItem.toString(), contains('chair (left, 92%)'));

      const centerItem = DetectedVisionItem(
        label: 'door',
        confidence: 0.85,
        boundingBox: Rect.fromLTWH(300, 100, 120, 200),
        position: 'center',
      );
      expect(centerItem.position, 'center');
      expect(centerItem.label, 'door');
    });
  });

  group('Phase 1 - Enhanced Voice Commands and Smarter OCR Options', () {
    test('parses read everything and read all text as full reading mode', () {
      final cmd1 = VoiceCommandParser.parse('Alice read everything', 'Alice');
      expect(cmd1.type, VoiceCommandType.readText);
      expect(cmd1.argument, 'all');

      final cmd2 = VoiceCommandParser.parse('read all text', 'Alice');
      expect(cmd2.type, VoiceCommandType.readText);
      expect(cmd2.argument, 'all');

      final cmd3 = VoiceCommandParser.parse('continue reading', 'Alice');
      expect(cmd3.type, VoiceCommandType.readText);
      expect(cmd3.argument, 'continue');
    });

    test('parses prominent sign reading variations', () {
      final cmd = VoiceCommandParser.parse('read the sign in front of me', 'Alice');
      expect(cmd.type, VoiceCommandType.readText);
      expect(cmd.argument, 'smart');
    });

    test('parses live object search queries for everyday items', () {
      final cmd1 = VoiceCommandParser.parse('Can you find a bottle?', 'Alice');
      expect(cmd1.type, VoiceCommandType.findItem);
      expect(cmd1.argument, 'bottle');

      final cmd2 = VoiceCommandParser.parse('Where is the chair?', 'Alice');
      expect(cmd2.type, VoiceCommandType.findItem);
      expect(cmd2.argument, 'the chair');

      final cmd3 = VoiceCommandParser.parse('Can you see a laptop?', 'Alice');
      expect(cmd3.type, VoiceCommandType.findItem);
      expect(cmd3.argument, 'laptop');
    });
  });

  group('Phase 1 - Object Detector and Live Search Logic', () {
    test('VisionService searchForObject locates live object and direction', () async {
      final detector = ObjectDetectorService();
      detector.testMockDetections = [
        const DetectedVisionItem(
          label: 'bottle',
          confidence: 0.88,
          boundingBox: Rect.fromLTWH(100, 100, 150, 300),
          position: 'left',
          proximity: 'near',
        ),
        const DetectedVisionItem(
          label: 'chair',
          confidence: 0.75,
          boundingBox: Rect.fromLTWH(300, 100, 200, 400),
          position: 'center',
          proximity: 'close',
        ),
      ];

      final visionService = VisionService(objectDetectorService: detector);

      // Search for bottle
      final resultBottle = await visionService.searchForObject('dummy.jpg', 'bottle');
      expect(resultBottle, contains('Found bottle on your left'));

      // Search for chair
      final resultChair = await visionService.searchForObject('dummy.jpg', 'chair');
      expect(resultChair, contains('Found chair directly ahead of you close by'));

      // Search for item not in current view
      final resultPhone = await visionService.searchForObject('dummy.jpg', 'cell phone');
      expect(resultPhone, contains('Could not see cell phone in this view'));
      expect(resultPhone, contains('Visible nearby: bottle, chair'));
    });

    test('VisionService scene description uses verified detections and proximity', () async {
      final detector = ObjectDetectorService();
      detector.testMockDetections = [
        const DetectedVisionItem(
          label: 'person',
          confidence: 0.90,
          boundingBox: Rect.fromLTWH(350, 50, 100, 300),
          position: 'center',
          proximity: 'close',
        ),
        const DetectedVisionItem(
          label: 'laptop',
          confidence: 0.85,
          boundingBox: Rect.fromLTWH(550, 200, 120, 100),
          position: 'right',
          proximity: 'near',
        ),
      ];

      final visionService = VisionService(objectDetectorService: detector);
      final desc = await visionService.describeSceneFromPath('dummy.jpg');
      expect(desc, contains('Ahead of you: person close by'));
      expect(desc, contains('To your right: laptop'));
    });
  });

  group('Natural Voice Interaction & Wake-Word Intent Tests', () {
    test('parses natural phrasing requested in usability review', () {
      final cmd1 = VoiceCommandParser.parse('Alice, what am I looking at?', 'Alice');
      expect(cmd1.type, VoiceCommandType.describeSurroundings);

      final cmd2 = VoiceCommandParser.parse('Alice, find my bottle.', 'Alice');
      expect(cmd2.type, VoiceCommandType.findItem);
      expect(cmd2.argument, contains('bottle'));

      final cmd3 = VoiceCommandParser.parse('Alice, where is my phone?', 'Alice');
      expect(cmd3.type, VoiceCommandType.findItem);
      expect(cmd3.argument, contains('phone'));

      final cmd4 = VoiceCommandParser.parse('Alice, read this.', 'Alice');
      expect(cmd4.type, VoiceCommandType.readText);
      expect(cmd4.argument, 'smart');

      final cmd5 = VoiceCommandParser.parse("Alice, describe what's around me.", 'Alice');
      expect(cmd5.type, VoiceCommandType.describeSurroundings);

      final cmd6 = VoiceCommandParser.parse('Alice, can you help me find the bus stop?', 'Alice');
      expect(cmd6.type, VoiceCommandType.takeMeTo);
      expect(cmd6.argument, 'bus stop');
    });

    test('treats empty speech or silence as VoiceCommandType.none', () {
      final cmdEmpty = VoiceCommandParser.parse('', 'Alice');
      expect(cmdEmpty.type, VoiceCommandType.none);

      final cmdSpaces = VoiceCommandParser.parse('   ', 'Alice');
      expect(cmdSpaces.type, VoiceCommandType.none);
    });

    test('VisionService matches natural queries with possessive my and synonyms', () async {
      final detector = ObjectDetectorService();
      detector.testMockDetections = [
        const DetectedVisionItem(
          label: 'cell phone',
          confidence: 0.88,
          boundingBox: Rect.fromLTWH(100, 100, 150, 300),
          position: 'left',
          proximity: 'near',
        ),
      ];

      final visionService = VisionService(objectDetectorService: detector);
      // Search for "my phone"
      final res = await visionService.searchForObject('dummy.jpg', 'my phone');
      expect(res, contains('Found cell phone on your left'));
    });

    test('TtsService tracks currentLocale and isKannada status', () async {
      final tts = TtsService();
      await tts.initialize(language: 'en-US');
      expect(tts.currentLocale, 'en-US');
      expect(tts.isKannada, false);

      await tts.setLanguage('kn-IN');
      expect(tts.currentLocale, 'kn-IN');
      expect(tts.isKannada, true);
    });

    testWidgets('FeatureDetailScreen renders Emergency SOS live card and actions', (tester) async {
      SharedPreferences.setMockInitialValues({'emergency_contact': '9876543210'});
      final storage = await StorageService.initialize();
      final tts = TtsService();

      await tester.pumpWidget(
        MaterialApp(
          home: FeatureDetailScreen(
            title: 'Emergency SOS',
            status: 'Available',
            explanation: 'Emergency assistance active.',
            technicalNotes: 'GPS and calling ready.',
            icon: Icons.emergency,
            ttsService: tts,
            storageService: storage,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Live Emergency Location'), findsOneWidget);
      expect(find.textContaining('9876543210'), findsOneWidget);
      expect(find.text('Announce Emergency GPS Location'), findsOneWidget);
    });

    testWidgets('SettingsScreen renders emergency contact section and preset buttons', (tester) async {
      SharedPreferences.setMockInitialValues({'emergency_contact': '112'});
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            storageService: storage,
            ttsService: tts,
            speechService: speech,
            onSettingsUpdated: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Emergency Contact Number'), findsOneWidget);
      expect(find.text('Save Contact'), findsOneWidget);
      expect(find.text('112'), findsWidgets);
      expect(find.text('108'), findsOneWidget);
    });
  });

  group('Bilingual Kannada Vision & Guidance Tests', () {
    test('VisionService translates COCO labels to natural Kannada words', () {
      expect(VisionService.translateLabelToKannada('person'), 'ವ್ಯಕ್ತಿ');
      expect(VisionService.translateLabelToKannada('chair'), 'ಕುರ್ಚಿ');
      expect(VisionService.translateLabelToKannada('bottle'), 'ಬಾಟಲ್');
      expect(VisionService.translateLabelToKannada('car'), 'ಕಾರು');
      expect(VisionService.translateLabelToKannada('laptop'), 'ಲ್ಯಾಪ್‌ಟಾಪ್');
      expect(VisionService.translateLabelToKannada('unknown_item'), 'unknown_item');
    });

    test('VisionService describeScene produces natural Kannada SOV description', () async {
      final detector = ObjectDetectorService();
      detector.testMockDetections = [
        const DetectedVisionItem(
          label: 'person',
          confidence: 0.90,
          boundingBox: Rect.fromLTWH(350, 50, 100, 300),
          position: 'center',
          proximity: 'close',
        ),
        const DetectedVisionItem(
          label: 'chair',
          confidence: 0.85,
          boundingBox: Rect.fromLTWH(100, 200, 120, 100),
          position: 'left',
          proximity: 'near',
        ),
      ];

      final visionService = VisionService(objectDetectorService: detector);
      final descKn = await visionService.describeSceneFromPath('dummy.jpg', isKannada: true);
      expect(descKn, contains('ಮುಂದೆ: ವ್ಯಕ್ತಿ ಸಮೀಪದಲ್ಲಿದೆ'));
      expect(descKn, contains('ನಿಮ್ಮ ಎಡಕ್ಕೆ: ಕುರ್ಚಿ'));
    });

    test('VisionService searchForObject matches native Kannada queries against COCO detector', () async {
      final detector = ObjectDetectorService();
      detector.testMockDetections = [
        const DetectedVisionItem(
          label: 'chair',
          confidence: 0.88,
          boundingBox: Rect.fromLTWH(350, 100, 150, 300),
          position: 'center',
          proximity: 'close',
        ),
      ];

      final visionService = VisionService(objectDetectorService: detector);
      // Native Kannada query for chair ("ಕುರ್ಚಿ")
      final res = await visionService.searchForObject('dummy.jpg', 'ಕುರ್ಚಿ', isKannada: true);
      expect(res, contains('ನಿಮ್ಮ ನೇರವಾಗಿ ಮುಂದೆ ಕುರ್ಚಿ ಸಮೀಪದಲ್ಲಿದೆ'));
    });

    test('StorageService destination cache stores and retrieves geocoded coordinates', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();

      expect(storage.recentDestinations, isEmpty);
      expect(storage.getCachedDestination('MG Road'), isNull);

      await storage.cacheGeocodedDestination(
        query: 'MG Road',
        lat: 12.9756,
        lng: 77.6066,
        displayName: 'Mahatma Gandhi Road, Bengaluru',
      );

      final cached = storage.getCachedDestination('mg road');
      expect(cached, isNotNull);
      expect(cached!['lat'], 12.9756);
      expect(cached['lon'], 77.6066);
      expect(cached['display_name'], 'Mahatma Gandhi Road, Bengaluru');
      expect(storage.recentDestinations.length, 1);

      await storage.clearDestinationCache();
      expect(storage.recentDestinations, isEmpty);
    });

    test('PedestrianRoute supports direct compass failover mode and spatial bearing formatting', () {
      const step = PedestrianStep(
        instruction: 'Head towards Central Park',
        streetName: 'Central Park',
        maneuverType: 'depart',
        maneuverModifier: 'straight',
        distanceMeters: 450,
        durationSeconds: 400,
        waypointLat: 12.97,
        waypointLng: 77.59,
      );

      const route = PedestrianRoute(
        destinationName: 'Central Park',
        destinationLat: 12.97,
        destinationLng: 77.59,
        totalDistanceMeters: 450,
        totalDurationSeconds: 400,
        isDirectCompassMode: true,
        steps: [step],
        polylineCoordinates: [
          [12.96, 77.58],
          [12.97, 77.59],
        ],
      );

      expect(route.isDirectCompassMode, isTrue);
      expect(route.destinationName, 'Central Park');

      // Test clock direction formatting for compass bearing
      expect(PedestrianStep.formatClockDirection(0), contains('straight ahead'));
      expect(PedestrianStep.formatClockDirection(30), contains('around 1 o\'clock'));
      expect(PedestrianStep.formatClockDirection(60), contains('at 2 o\'clock'));
      expect(PedestrianStep.formatClockDirection(90), contains('3 o\'clock'));

      // Test Kannada clock direction formatting
      expect(PedestrianStep.formatClockDirection(0, isKannada: true), contains('ನೇರವಾಗಿ ಮುಂದೆ'));
      expect(PedestrianStep.formatClockDirection(60, isKannada: true), contains('2 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ'));
    });

    testWidgets('SettingsScreen displays cached destination places and handles clear', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      await storage.cacheGeocodedDestination(
        query: 'Brigade Road',
        lat: 12.973,
        lng: 77.608,
        displayName: 'Brigade Road, Bengaluru',
      );

      final tts = TtsService();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            storageService: storage,
            ttsService: tts,
            onSettingsUpdated: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cached Destinations & Offline Places'), findsOneWidget);
      expect(find.text('Brigade Road'), findsOneWidget);
      expect(find.text('Read Saved Places Aloud'), findsOneWidget);
      expect(find.text('Clear Destination Cache'), findsOneWidget);

      await tester.tap(find.text('Clear Destination Cache'));
      await tester.pumpAndSettle();

      expect(storage.recentDestinations, isEmpty);
      expect(find.text('No destination cache yet. Searched locations are automatically saved here.'), findsOneWidget);
    });

    test('BanknoteColorProfile creates valid authentic profiles', () {
      const profile = BanknoteColorProfile(
        denomination: '500',
        colorNameEn: 'stone grey',
        colorNameKn: 'ಬೂದು ಬಣ್ಣ',
      );
      expect(profile.denomination, '500');
      expect(profile.colorNameEn, 'stone grey');
      expect(profile.colorNameKn, 'ಬೂದು ಬಣ್ಣ');
    });

    test('VoiceSessionCoordinator delegates new commands to active delegate', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();
      final navKey = GlobalKey<NavigatorState>();
      final coordinator = VoiceSessionCoordinator(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        navigatorKey: navKey,
      );

      final mockDelegate = _MockDelegate();
      coordinator.registerDelegate(mockDelegate);

      final torchCmd = VoiceCommandParser.parse('turn on flashlight', 'Alice');
      coordinator.executeCommand(torchCmd);
      expect(mockDelegate.handledCommand?.type, VoiceCommandType.toggleTorch);

      final aroundCmd = VoiceCommandParser.parse('around me', 'Alice');
      coordinator.executeCommand(aroundCmd);
      expect(mockDelegate.handledCommand?.type, VoiceCommandType.aroundMe);

      final busCmd = VoiceCommandParser.parse('read bus number', 'Alice');
      coordinator.executeCommand(busCmd);
      expect(mockDelegate.handledCommand?.type, VoiceCommandType.readBusRoute);

      final trafficCmd = VoiceCommandParser.parse('check traffic light', 'Alice');
      coordinator.executeCommand(trafficCmd);
      expect(mockDelegate.handledCommand?.type, VoiceCommandType.checkTrafficLight);

      final favCmd = VoiceCommandParser.parse('save as home', 'Alice');
      coordinator.executeCommand(favCmd);
      expect(mockDelegate.handledCommand?.type, VoiceCommandType.saveFavoritePlace);
      expect(mockDelegate.handledCommand?.argument, 'home');
    });

    test('TrafficSignalAnalysis provides safe actionable guidance', () {
      final redSignal = TrafficSignalAnalysis(
        state: TrafficSignalState.red,
        confidence: 0.92,
        stopSignDetected: false,
        pedestrianInstruction: 'Red light detected. Please wait.',
      );
      expect(redSignal.state, TrafficSignalState.red);
      expect(redSignal.isSafeToCross, false);

      final greenSignal = TrafficSignalAnalysis(
        state: TrafficSignalState.green,
        confidence: 0.88,
        stopSignDetected: false,
        pedestrianInstruction: 'Green light detected. Safe to proceed.',
      );
      expect(greenSignal.state, TrafficSignalState.green);
      expect(greenSignal.isSafeToCross, true);

      final uncertain = TrafficSignalAnalysis(
        state: TrafficSignalState.uncertain,
        confidence: 0.40,
        stopSignDetected: false,
        pedestrianInstruction: 'Signal unclear. Wait and listen.',
      );
      expect(uncertain.isSafeToCross, false);
    });

    test('PedestrianStep estimatedSteps and formattedInstructionWithSteps calculates step counts', () {
      const step = PedestrianStep(
        instruction: 'Turn left onto MG Road',
        streetName: 'MG Road',
        maneuverType: 'turn',
        maneuverModifier: 'left',
        distanceMeters: 45.0,
        durationSeconds: 36.0,
        waypointLat: 12.9716,
        waypointLng: 77.5946,
      );

      expect(step.estimatedSteps, 60); // 45 / 0.75 = 60 steps
      expect(step.formattedInstructionWithSteps(), 'Turn left onto MG Road (approx 60 steps)');
      expect(step.formattedInstructionWithSteps(isKannada: true), 'Turn left onto MG Road (ಸುಮಾರು 60 ಹೆಜ್ಜೆಗಳು)');
    });

    testWidgets('SettingsScreen displays Directional Turn Haptics and Favorite Places', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      final tts = TtsService();

      await storage.saveFavoritePlace(
        'home',
        lat: 12.9716,
        lon: 77.5946,
        name: 'Home',
        address: '123 Main Street',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            storageService: storage,
            ttsService: tts,
            onSettingsUpdated: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Directional Turn Haptics'), findsOneWidget);
      expect(find.text('Favorite Places (Home & Work)'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('123 Main Street'), findsOneWidget);
      expect(find.text('Read Favorite Places Aloud'), findsOneWidget);
    });
  });
}

class _MockDelegate implements VoiceCommandDelegate {
  VoiceCommand? handledCommand;

  @override
  String get screenName => 'MockScreen';

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    handledCommand = command;
    return true;
  }
}
