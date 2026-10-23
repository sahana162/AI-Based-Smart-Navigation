import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart' as mlkit_obj;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'object_detector_service.dart';

export 'object_detector_service.dart' show DetectedVisionItem;

enum OcrReadingMode {
  smart,
  all,
  continueReading,
}

enum TrafficSignalState {
  red,
  green,
  yellow,
  stopSign,
  none,
  uncertain,
}

/// Structured traffic light and pedestrian crossing signal result.
class TrafficSignalAnalysis {
  final TrafficSignalState state;
  final String descriptionEn;
  final String descriptionKn;
  final double confidence;

  const TrafficSignalAnalysis({
    required this.state,
    required this.descriptionEn,
    required this.descriptionKn,
    required this.confidence,
  });
}

/// Authentic color characteristics for Mahatma Gandhi New Series Indian banknotes.
class BanknoteColorProfile {
  final String denomination;
  final String colorNameEn;
  final String colorNameKn;

  const BanknoteColorProfile({
    required this.denomination,
    required this.colorNameEn,
    required this.colorNameKn,
  });
}

/// On-device computer vision service utilizing genuine pretrained models.
///
/// Features:
/// - Fine-grained COCO 90-class object detection using MobileNet SSD / TFLite.
/// - Smarter OCR with block-level relevance filtering, reading order, and prominent text prioritization.
/// - Live object search for physical everyday objects independent of saved memory.
/// - Grounded scene description powered by verified detections and smart OCR.
class VisionService {
  final ObjectDetectorService _objectDetectorService;
  TextRecognizer? _textRecognizer;
  mlkit_obj.ObjectDetector? _mlkitFallbackDetector;
  bool _isDisposed = false;

  String _lastRecognizedText = '';
  List<String> _cachedRemainingBlocks = [];

  VisionService({ObjectDetectorService? objectDetectorService})
      : _objectDetectorService = objectDetectorService ?? ObjectDetectorService();

  ObjectDetectorService get objectDetectorService => _objectDetectorService;
  String get lastRecognizedText => _lastRecognizedText;

  TextRecognizer get textRecognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  mlkit_obj.ObjectDetector get mlkitFallbackDetector {
    _mlkitFallbackDetector ??= mlkit_obj.ObjectDetector(
      options: mlkit_obj.ObjectDetectorOptions(
        mode: mlkit_obj.DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
    return _mlkitFallbackDetector!;
  }

  // ── 1. Smarter Text Recognition (OCR) ──────────────────────────────────────

  /// Extracts and filters printed text from an image file on device.
  ///
  /// Supports [OcrReadingMode.smart] (prominent signs, labels, headings),
  /// [OcrReadingMode.all] (all detected text blocks in reading order),
  /// and [OcrReadingMode.continueReading] (next portion of lengthy text).
  Future<String> recognizeTextFromPath(
    String imagePath, {
    OcrReadingMode mode = OcrReadingMode.smart,
    bool isKannada = false,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return isKannada ? 'ಚಿತ್ರದ ಫೈಲ್ ಕಂಡುಬಂದಿಲ್ಲ.' : 'Image file not found.';
    }

    if (mode == OcrReadingMode.continueReading && _cachedRemainingBlocks.isNotEmpty) {
      final nextChunk = _cachedRemainingBlocks.take(3).join('. ');
      _cachedRemainingBlocks = _cachedRemainingBlocks.skip(3).toList();
      if (nextChunk.isNotEmpty) {
        _lastRecognizedText = nextChunk;
        return nextChunk;
      }
      return isKannada ? 'ಪಠ್ಯ ಮುಕ್ತಾಯವಾಗಿದೆ.' : 'End of text.';
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      final blocks = recognizedText.blocks;
      if (blocks.isEmpty) {
        _lastRecognizedText = isKannada ? 'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಪಠ್ಯ ಕಂಡುಬಂದಿಲ್ಲ.' : 'No readable text found in view.';
        _cachedRemainingBlocks = [];
        return _lastRecognizedText;
      }

      // Sort blocks by natural reading order (top to bottom, left to right)
      final sortedBlocks = List<TextBlock>.from(blocks)
        ..sort((a, b) {
          final topDiff = (a.boundingBox.top - b.boundingBox.top).abs();
          // If blocks are roughly on the same vertical line (within 25px), sort by left X
          if (topDiff < 25) {
            return a.boundingBox.left.compareTo(b.boundingBox.left);
          }
          return a.boundingBox.top.compareTo(b.boundingBox.top);
        });

      if (mode == OcrReadingMode.all) {
        final lines = sortedBlocks
            .map((b) => _cleanOcrBlock(b.text))
            .where((t) => t.isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          return isKannada ? 'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಪಠ್ಯ ಗುರುತಿಸಲಾಗಿಲ್ಲ.' : 'No clear text recognized.';
        }
        _lastRecognizedText = lines.join('. ');
        return _lastRecognizedText;
      }

      // Smart Mode: Filter noise, prioritize prominent signs and critical short text
      final List<String> prominentSignText = [];
      final List<String> bodyText = [];

      // Calculate max block height to identify prominent headers/signs
      double maxHeight = 0.0;
      for (final b in sortedBlocks) {
        if (b.boundingBox.height > maxHeight) {
          maxHeight = b.boundingBox.height;
        }
      }

      final Set<String> seenLines = {};

      for (final block in sortedBlocks) {
        final cleaned = _cleanOcrBlock(block.text);
        if (cleaned.isEmpty) continue;

        // Filter duplicate fragments
        final lower = cleaned.toLowerCase();
        if (seenLines.contains(lower)) continue;
        seenLines.add(lower);

        // Check if prominent sign or heading (height > 60% of max height)
        final isProminent = block.boundingBox.height >= (maxHeight * 0.60);
        final isCriticalWord = _isCriticalShortTerm(cleaned);

        if (isProminent || isCriticalWord) {
          prominentSignText.add(cleaned);
        } else {
          bodyText.add(cleaned);
        }
      }

      final List<String> resultParts = [];
      if (prominentSignText.isNotEmpty) {
        final prefix = isKannada ? 'ಫಲಕದ ಪಠ್ಯ:' : 'Sign reads:';
        resultParts.add('$prefix ${prominentSignText.join('. ')}');
      }

      if (bodyText.isNotEmpty) {
        if (prominentSignText.isEmpty) {
          // If no prominent sign, read top body text
          final topBody = bodyText.take(4).join('. ');
          resultParts.add(topBody);
          _cachedRemainingBlocks = bodyText.skip(4).toList();
        } else {
          // Keep additional body text available for "continue reading"
          _cachedRemainingBlocks = bodyText;
        }
      } else {
        _cachedRemainingBlocks = [];
      }

      if (resultParts.isEmpty) {
        _lastRecognizedText = isKannada
            ? 'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಫಲಕಗಳು ಅಥವಾ ಪಠ್ಯ ಕಂಡುಬಂದಿಲ್ಲ.'
            : 'No distinct signs or readable text found.';
      } else {
        _lastRecognizedText = resultParts.join('. ');
      }

      return _lastRecognizedText;
    } catch (e) {
      debugPrint('[VisionService] OCR error: $e');
      return 'Unable to read text from this image.';
    }
  }

  // ── 2. Fine-Grained Object Detection ──────────────────────────────────────

  /// Detects physical objects with COCO-trained fine-grained labels and spatial localization.
  Future<List<DetectedVisionItem>> detectObjectsFromPath(
    String imagePath, {
    double imageWidth = 720.0,
    double imageHeight = 1280.0,
    double confidenceThreshold = 0.40,
  }) async {
    try {
      // 1. Try genuine fine-grained COCO detector first (handles mock and real file)
      final tfliteItems = await _objectDetectorService.detectObjectsFromPath(
        imagePath,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        confidenceThreshold: confidenceThreshold,
      );

      if (tfliteItems.isNotEmpty) {
        return tfliteItems;
      }

      final file = File(imagePath);
      if (!file.existsSync()) {
        return [];
      }

      // If TFLite is unavailable (or returned 0 confident objects), fallback to ML Kit base detector
      debugPrint('[VisionService] Running ML Kit fallback detector...');
      final inputImage = InputImage.fromFilePath(imagePath);
      final List<mlkit_obj.DetectedObject> detected =
          await mlkitFallbackDetector.processImage(inputImage);

      final List<DetectedVisionItem> results = [];

      for (final obj in detected) {
        final box = obj.boundingBox;
        final centerX = box.center.dx;

        final String position;
        if (centerX < imageWidth * 0.35) {
          position = 'left';
        } else if (centerX > imageWidth * 0.65) {
          position = 'right';
        } else {
          position = 'center';
        }

        String label = 'object';
        double confidence = 0.50;

        if (obj.labels.isNotEmpty) {
          final topLabel = obj.labels.first;
          label = _mapMlKitLabel(topLabel.text);
          confidence = topLabel.confidence;
        }

        final double boxHeight = box.height;
        final double estimatedDist = (150.0 / boxHeight.clamp(20.0, 500.0)).clamp(0.5, 8.0);
        final bool isOverhead = box.top < 200 && box.bottom < 450 && position == 'center';

        results.add(DetectedVisionItem(
          label: label,
          confidence: confidence,
          boundingBox: box,
          position: position,
          proximity: (box.height > 250) ? 'close' : 'near',
          isOverheadHazard: isOverhead,
          estimatedDistanceMeters: double.parse(estimatedDist.toStringAsFixed(1)),
        ));
      }

      return results;
    } catch (e) {
      debugPrint('[VisionService] Object detection error: $e');
      return [];
    }
  }

  /// Runs real-time in-memory obstacle detection directly on streaming [CameraImage] frames.
  Future<List<DetectedVisionItem>> detectObjectsFromCameraImage(
    CameraImage image, {
    int sensorOrientation = 90,
  }) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation90deg;

      final InputImageFormat inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final List<mlkit_obj.DetectedObject> detected =
          await mlkitFallbackDetector.processImage(inputImage);

      final List<DetectedVisionItem> results = [];
      final double width = image.width.toDouble();
      final double height = image.height.toDouble();

      for (final obj in detected) {
        final box = obj.boundingBox;
        final centerX = box.center.dx;

        final String position;
        if (centerX < width * 0.35) {
          position = 'left';
        } else if (centerX > width * 0.65) {
          position = 'right';
        } else {
          position = 'center';
        }

        String label = 'obstacle';
        double confidence = 0.50;

        if (obj.labels.isNotEmpty) {
          final topLabel = obj.labels.first;
          label = _mapMlKitLabel(topLabel.text);
          confidence = topLabel.confidence;
        }

        final double boxHeight = box.height;
        final String proximity = (boxHeight > height * 0.40)
            ? 'close'
            : (boxHeight > height * 0.20 ? 'near' : 'far');

        final double boxHeightRatio = boxHeight / height;
        final double estimatedDist = (0.65 / boxHeightRatio.clamp(0.05, 1.0)).clamp(0.5, 8.0);

        final bool isOverhead = box.top < height * 0.28 && box.bottom < height * 0.65 && position == 'center';
        final String guidance = isOverhead
            ? 'Head-level obstacle ahead: low clearance for $label.'
            : (position == 'center'
                ? '$label directly ahead of you.'
                : '$label on your $position.');

        results.add(DetectedVisionItem(
          label: label,
          confidence: confidence,
          boundingBox: box,
          position: position,
          proximity: proximity,
          cameraGuidance: guidance,
          isHighConfidence: confidence >= 0.50,
          isOverheadHazard: isOverhead,
          estimatedDistanceMeters: double.parse(estimatedDist.toStringAsFixed(1)),
        ));
      }

      return results;
    } catch (e) {
      debugPrint('[VisionService] CameraImage streaming detection error: $e');
      return [];
    }
  }

  // ── 3. Grounded Scene Description ─────────────────────────────────────────

  /// Generates a natural spoken scene description grounded in verified detections and text.
  Future<String> describeSceneFromPath(
    String imagePath, {
    double imageWidth = 720.0,
    bool isKannada = false,
  }) async {
    final objects = await detectObjectsFromPath(imagePath, imageWidth: imageWidth);
    final ocrText = await recognizeTextFromPath(imagePath, mode: OcrReadingMode.smart, isKannada: isKannada);

    if (objects.isEmpty &&
        (ocrText.isEmpty ||
            ocrText.startsWith('No readable') ||
            ocrText.startsWith('No distinct') ||
            ocrText.startsWith('Image file not found') ||
            ocrText.startsWith('Unable to read') ||
            ocrText.startsWith('ಚಿತ್ರದ ಫೈಲ್') ||
            ocrText.startsWith('ಯಾವುದೇ ಸ್ಪಷ್ಟ'))) {
      return isKannada
          ? 'ಕ್ಯಾಮೆರಾ ವೀಕ್ಷಣೆಯಲ್ಲಿ ಯಾವುದೇ ವಸ್ತುಗಳು ಅಥವಾ ಸ್ಪಷ್ಟ ಫಲಕಗಳು ಕಂಡುಬಂದಿಲ್ಲ. ನಿಮ್ಮ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಬಳಸಿ ಎಚ್ಚರಿಕೆಯಿಂದ ಮುನ್ನಡೆಯಿರಿ.'
          : 'No recognized objects or readable signs in current camera view. Please verify your path with your cane.';
    }

    final List<String> descriptions = [];

    // Group objects by position and proximity
    final centerObjects = objects.where((o) => o.position == 'center').toList();
    final leftObjects = objects.where((o) => o.position == 'left').toList();
    final rightObjects = objects.where((o) => o.position == 'right').toList();

    if (isKannada) {
      if (centerObjects.isNotEmpty) {
        final itemsSummary = centerObjects
            .map((o) => o.proximity == 'close'
                ? '${translateLabelToKannada(o.label)} ಸಮೀಪದಲ್ಲಿದೆ'
                : translateLabelToKannada(o.label))
            .toSet()
            .join(', ');
        descriptions.add('ಮುಂದೆ: $itemsSummary');
      }
      if (leftObjects.isNotEmpty) {
        final itemsSummary = leftObjects.map((o) => translateLabelToKannada(o.label)).toSet().join(', ');
        descriptions.add('ನಿಮ್ಮ ಎಡಕ್ಕೆ: $itemsSummary');
      }
      if (rightObjects.isNotEmpty) {
        final itemsSummary = rightObjects.map((o) => translateLabelToKannada(o.label)).toSet().join(', ');
        descriptions.add('ನಿಮ್ಮ ಬಲಕ್ಕೆ: $itemsSummary');
      }
    } else {
      if (centerObjects.isNotEmpty) {
        final itemsSummary = centerObjects.map((o) => o.proximity == 'close' ? '${o.label} close by' : o.label).toSet().join(', ');
        descriptions.add('Ahead of you: $itemsSummary');
      }
      if (leftObjects.isNotEmpty) {
        final itemsSummary = leftObjects.map((o) => o.label).toSet().join(', ');
        descriptions.add('To your left: $itemsSummary');
      }
      if (rightObjects.isNotEmpty) {
        final itemsSummary = rightObjects.map((o) => o.label).toSet().join(', ');
        descriptions.add('To your right: $itemsSummary');
      }
    }

    final trafficSignalObj = objects.firstWhere(
      (o) => o.label.contains('traffic light') || o.label.contains('stop sign'),
      orElse: () => const DetectedVisionItem(label: '', confidence: 0, boundingBox: Rect.zero, position: ''),
    );
    if (trafficSignalObj.label.isNotEmpty) {
      final signal = await analyzeTrafficSignal(imagePath, isKannada: isKannada);
      if (signal.state != TrafficSignalState.none && signal.state != TrafficSignalState.uncertain) {
        descriptions.add(isKannada ? signal.descriptionKn : signal.descriptionEn);
      }
    }

    if (ocrText.isNotEmpty &&
        !ocrText.startsWith('No readable') &&
        !ocrText.startsWith('No distinct') &&
        !ocrText.startsWith('Image file not found') &&
        !ocrText.startsWith('Unable to read') &&
        !ocrText.startsWith('ಚಿತ್ರದ ಫೈಲ್') &&
        !ocrText.startsWith('ಯಾವುದೇ ಸ್ಪಷ್ಟ') &&
        ocrText.length < 120) {
      descriptions.add(ocrText);
    }

    return descriptions.join('. ');
  }

  // ── 4. Live Object Search ─────────────────────────────────────────────────

  /// Searches for [targetItem] in the camera image independently of saved items.
  ///
  /// Matches fine-grained COCO classes, handles synonyms, and verifies spatial location.
  Future<String> searchForObject(
    String imagePath,
    String targetItem, {
    double imageWidth = 720.0,
    bool isSavedLookup = false,
    String? savedNotes,
    bool isKannada = false,
  }) async {
    final normalizedTarget = targetItem.toLowerCase().trim();
    final objects = await detectObjectsFromPath(imagePath, imageWidth: imageWidth);

    // 1. Direct and synonym matching with fine-grained detector
    for (final obj in objects) {
      if (_matchesTargetClass(obj.label, normalizedTarget)) {
        if (isKannada) {
          final posKn = obj.position == 'center'
              ? 'ನೇರವಾಗಿ ಮುಂದೆ'
              : (obj.position == 'left' ? 'ಎಡಕ್ಕೆ' : 'ಬಲಕ್ಕೆ');
          final proxKn = obj.proximity == 'close' ? ' ಸಮೀಪದಲ್ಲಿದೆ' : ' ಇದೆ';
          final labelKn = translateLabelToKannada(obj.label);
          return 'ನಿಮ್ಮ $posKn $labelKn$proxKn.';
        } else {
          final posDesc = obj.position == 'center'
              ? 'directly ahead of you'
              : 'on your ${obj.position}';
          final proxDesc = obj.proximity == 'close' ? ' close by' : '';
          return 'Found ${obj.label} $posDesc$proxDesc.';
        }
      }
    }

    // 2. Secondary check: see if item name or brand is visible in text
    final text = await recognizeTextFromPath(imagePath, mode: OcrReadingMode.all, isKannada: isKannada);
    if (text.toLowerCase().contains(normalizedTarget)) {
      return isKannada
          ? '"$targetItem" ಗಾಗಿ ಪಠ್ಯ ಲೇಬಲ್ ಕಂಡುಬಂದಿದೆ.'
          : 'Found text label for "$targetItem" in view.';
    }

    // 3. Honest reporting when not found in current frame
    if (objects.isNotEmpty) {
      if (isKannada) {
        final nearbyKn = objects.map((o) => translateLabelToKannada(o.label)).toSet().join(', ');
        final savedPrefix = isSavedLookup ? 'ನಿಮ್ಮ ಉಳಿಸಿದ $targetItem' : targetItem;
        final notesExtra = (isSavedLookup && savedNotes != null && savedNotes.isNotEmpty)
            ? ' (ಟಿಪ್ಪಣಿ: $savedNotes)'
            : '';
        return 'ಈ ವೀಕ್ಷಣೆಯಲ್ಲಿ $savedPrefix$notesExtra ಕಂಡುಬಂದಿಲ್ಲ. ಹತ್ತಿರದಲ್ಲಿ ಕಾಣಿಸುತ್ತಿರುವುದು: $nearbyKn. ಕ್ಯಾಮೆರಾವನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ಅಥವಾ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ.';
      } else {
        final nearby = objects.map((o) => o.label).toSet().join(', ');
        final savedPrefix = isSavedLookup ? 'Your saved $targetItem' : targetItem;
        final notesExtra = (isSavedLookup && savedNotes != null && savedNotes.isNotEmpty)
            ? ' (noted: $savedNotes)'
            : '';
        return 'Could not see $savedPrefix$notesExtra in this view. Visible nearby: $nearby. Scan slowly to the left or right.';
      }
    }

    if (isKannada) {
      final savedPrefix = isSavedLookup ? 'ನಿಮ್ಮ ಉಳಿಸಿದ $targetItem' : targetItem;
      return 'ಈ ವೀಕ್ಷಣೆಯಲ್ಲಿ $savedPrefix ಕಂಡುಬಂದಿಲ್ಲ. ದಯವಿಟ್ಟು ಕ್ಯಾಮೆರಾವನ್ನು ನಿಧಾನವಾಗಿ ತಿರುಗಿಸಿ.';
    } else {
      final savedPrefix = isSavedLookup ? 'your saved $targetItem' : targetItem;
      return 'Could not see $savedPrefix in view. Please pan the camera slowly across the area.';
    }
  }

  // ── 5. Currency Recognition (Multi-Modal: OCR + Color Tint) ───────────────

  /// Represents the authentic color characteristics of Mahatma Gandhi New Series Indian banknotes.
  Future<BanknoteColorProfile?> detectBanknoteColorTint(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Sample center 50% grid of pixels for robust banknote tint estimation
      final startX = (decoded.width * 0.25).toInt();
      final endX = (decoded.width * 0.75).toInt();
      final startY = (decoded.height * 0.25).toInt();
      final endY = (decoded.height * 0.75).toInt();

      double totalR = 0, totalG = 0, totalB = 0;
      int sampleCount = 0;
      final step = (decoded.width / 50).clamp(2, 10).toInt();

      for (int y = startY; y < endY; y += step) {
        for (int x = startX; x < endX; x += step) {
          final pixel = decoded.getPixel(x, y);
          totalR += pixel.r;
          totalG += pixel.g;
          totalB += pixel.b;
          sampleCount++;
        }
      }

      if (sampleCount == 0) return null;

      final avgR = (totalR / sampleCount) / 255.0;
      final avgG = (totalG / sampleCount) / 255.0;
      final avgB = (totalB / sampleCount) / 255.0;

      final maxVal = [avgR, avgG, avgB].reduce((a, b) => a > b ? a : b);
      final minVal = [avgR, avgG, avgB].reduce((a, b) => a < b ? a : b);
      final delta = maxVal - minVal;

      final saturation = maxVal == 0 ? 0.0 : delta / maxVal;
      final value = maxVal;

      double hue = 0.0;
      if (delta > 0.001) {
        if (maxVal == avgR) {
          hue = (60.0 * ((avgG - avgB) / delta) + 360.0) % 360.0;
        } else if (maxVal == avgG) {
          hue = (60.0 * ((avgB - avgR) / delta) + 120.0) % 360.0;
        } else {
          hue = (60.0 * ((avgR - avgG) / delta) + 240.0) % 360.0;
        }
      }

      // 1. Stone Grey (500 Rupees) - Low saturation, balanced RGB
      if (saturation < 0.18 && value > 0.25 && value < 0.85) {
        return const BanknoteColorProfile(
          denomination: '500',
          colorNameEn: 'stone grey',
          colorNameKn: 'ಬೂದು ಬಣ್ಣ',
        );
      }

      // 2. Magenta (2000 Rupees) - Pinkish/Purple
      if (hue >= 290 && hue <= 355 && saturation > 0.20 && value > 0.3) {
        return const BanknoteColorProfile(
          denomination: '2000',
          colorNameEn: 'magenta',
          colorNameKn: 'ಮೆಜೆಂಟಾ ಗುಲಾಬಿ',
        );
      }

      // 3. Bright Orange / Yellow-Orange (200 Rupees)
      if (hue >= 25 && hue <= 55 && saturation > 0.35 && value > 0.45) {
        return const BanknoteColorProfile(
          denomination: '200',
          colorNameEn: 'bright orange',
          colorNameKn: 'ಕಿತ್ತಳೆ ಬಣ್ಣ',
        );
      }

      // 4. Lavender / Violet (100 Rupees)
      if (hue >= 220 && hue <= 285 && saturation > 0.15) {
        return const BanknoteColorProfile(
          denomination: '100',
          colorNameEn: 'lavender',
          colorNameKn: 'ಲ್ಯಾವೆಂಡರ್ ನೇರಳೆ',
        );
      }

      // 5. Cyan / Fluorescent Blue (50 Rupees)
      if (hue >= 170 && hue < 220 && saturation > 0.20) {
        return const BanknoteColorProfile(
          denomination: '50',
          colorNameEn: 'fluorescent blue',
          colorNameKn: 'ನೀಲಿ ಬಣ್ಣ',
        );
      }

      // 6. Greenish Yellow (20 Rupees)
      if (hue >= 60 && hue <= 95 && saturation > 0.20) {
        return const BanknoteColorProfile(
          denomination: '20',
          colorNameEn: 'greenish yellow',
          colorNameKn: 'ಹಸಿರು-ಹಳದಿ ಬಣ್ಣ',
        );
      }

      // 7. Chocolate Brown (10 Rupees)
      if (hue >= 15 && hue <= 40 && saturation >= 0.20 && value < 0.50) {
        return const BanknoteColorProfile(
          denomination: '10',
          colorNameEn: 'chocolate brown',
          colorNameKn: 'ಕಂದು ಬಣ್ಣ',
        );
      }
    } catch (e) {
      debugPrint('Banknote color tint analysis exception: $e');
    }
    return null;
  }

  /// Inspects banknote text and markings combined with dominant color tint to determine Indian Rupee denomination.
  Future<String> recognizeBanknote(String imagePath, {bool isKannada = false}) async {
    final text = await recognizeTextFromPath(imagePath, mode: OcrReadingMode.all, isKannada: isKannada);
    final upper = text.toUpperCase();

    final hasRbiMarker = upper.contains('RESERVE BANK OF INDIA') ||
        upper.contains('BHARATIYA RESERVE') ||
        upper.contains('PROMISE TO PAY') ||
        upper.contains('RUPEES') ||
        upper.contains('RUPEE') ||
        upper.contains('₹') ||
        upper.contains('ಗ್ಯಾರಂಟಿ') ||
        upper.contains('ರೂಪಾಯಿ');

    final colorProfile = await detectBanknoteColorTint(imagePath);

    final denominations = [
      (RegExp(r'\b(2000)\b'), '2000 Rupees', '2000'),
      (RegExp(r'\b(500)\b'), '500 Rupees', '500'),
      (RegExp(r'\b(200)\b'), '200 Rupees', '200'),
      (RegExp(r'\b(100)\b'), '100 Rupees', '100'),
      (RegExp(r'\b(50)\b'), '50 Rupees', '50'),
      (RegExp(r'\b(20)\b'), '20 Rupees', '20'),
      (RegExp(r'\b(10)\b'), '10 Rupees', '10'),
    ];

    for (final (regex, denomEn, denomNum) in denominations) {
      if (regex.hasMatch(text)) {
        if (hasRbiMarker) {
          final colorConf = (colorProfile != null && colorProfile.denomination == denomNum)
              ? (isKannada ? ' (${colorProfile.colorNameKn}ದಿಂದ ದೃಢೀಕರಿಸಲಾಗಿದೆ)' : ' (confirmed by ${colorProfile.colorNameEn} color)')
              : '';
          return isKannada
              ? 'ಭಾರತೀಯ ಕರೆನ್ಸಿ ನೋಟು: $denomNum ರೂಪಾಯಿ$colorConf.'
              : 'Indian currency note: $denomEn$colorConf.';
        } else if (colorProfile != null && colorProfile.denomination == denomNum) {
          return isKannada
              ? 'ಭಾರತೀಯ ಕರೆನ್ಸಿ ನೋಟು: $denomNum ರೂಪಾಯಿ (${colorProfile.colorNameKn}ದಿಂದ ದೃಢೀಕರಿಸಲಾಗಿದೆ).'
              : 'Indian currency note: $denomEn (verified by ${colorProfile.colorNameEn} color tint).';
        } else {
          return isKannada
              ? 'ಪಠ್ಯದಲ್ಲಿ ಸಂಖ್ಯೆ $denomNum ಕಂಡುಬಂದಿದೆ, ಆದರೆ ಯಾವುದೇ ರಿಸರ್ವ್ ಬ್ಯಾಂಕ್ ಗುರುತುಗಳಿಲ್ಲ. ಇದು ನೋಟು ಅಲ್ಲ.'
              : 'Found number $denomEn on text, but no Reserve Bank or currency markings detected. This does not appear to be a banknote.';
        }
      }
    }

    if (hasRbiMarker) {
      if (colorProfile != null) {
        return isKannada
            ? 'ರಿಸರ್ವ್ ಬ್ಯಾಂಕ್ ಗುರುತು ಮತ್ತು ${colorProfile.colorNameKn} ಕಂಡುಬಂದಿದೆ. ಇದು ${colorProfile.denomination} ರೂಪಾಯಿ ನೋಟು ಆಗಿರಬಹುದು. ದೃಢೀಕರಿಸಲು ನೋಟನ್ನು ಸಮತಟ್ಟಾಗಿ ಹಿಡಿಯಿರಿ.'
            : 'Banknote markings detected. Appears to be a ${colorProfile.denomination} Rupee note based on ${colorProfile.colorNameEn} color. Hold flat to confirm denomination.';
      }
      return isKannada
          ? 'ನೋಟಿನ ಗುರುತುಗಳು ಪತ್ತೆಯಾಗಿವೆ, ಆದರೆ ಮೌಲ್ಯದ ಸಂಖ್ಯೆ ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ. ದಯವಿಟ್ಟು ನೋಟನ್ನು ಸಮತಟ್ಟಾಗಿ ಹಿಡಿದುಕೊಳ್ಳಿ.'
          : 'Banknote markings detected, but denomination number was not clear. Please hold the note flat and steady.';
    }

    // Folded or unreadable OCR fallback based on color profile
    if (colorProfile != null) {
      return isKannada
          ? '${colorProfile.colorNameKn}ದಿಂದ ಇದು ${colorProfile.denomination} ರೂಪಾಯಿ ನೋಟು ಎಂದು ತೋರುತ್ತದೆ. ಸಂಖ್ಯೆಯನ್ನು ಖಚಿತಪಡಿಸಿಕೊಳ್ಳಲು ನೋಟನ್ನು ತಿರುಗಿಸಿ ಅಥವಾ ಸಮತಟ್ಟಾಗಿ ಹಿಡಿಯಿರಿ.'
          : 'Appears to be a ${colorProfile.denomination} Rupee note based on its ${colorProfile.colorNameEn} tint. Please flatten the note or turn it over to verify the number.';
    }

    return isKannada
        ? 'ಯಾವುದೇ ನೋಟು ಗುರುತಿಸಲಾಗಿಲ್ಲ. ದಯವಿಟ್ಟು ನೋಟನ್ನು ಸಮತಟ್ಟಾಗಿ ಮತ್ತು ಬೆಳಕಿನಲ್ಲಿ ಹಿಡಿದುಕೊಳ್ಳಿ.'
        : 'No banknote recognized. Please ensure the note is well lit, flat, and facing the camera.';
  }

  // ── 6. Transit & Bus Route Recognition ─────────────────────────────────────

  /// Inspects images of oncoming transit vehicles to identify bus route numbers and destination boards.
  Future<String> recognizeBusRoute(String imagePath, {bool isKannada = false}) async {
    final text = await recognizeTextFromPath(imagePath, mode: OcrReadingMode.all, isKannada: isKannada);
    final upper = text.toUpperCase();

    // Prominent transit destination names (English and Kannada)
    final destinationKeywords = {
      'MAJESTIC': ('Majestic', 'ಮೆಜೆಸ್ಟಿಕ್'),
      'KEMPEGOWDA': ('Kempegowda Bus Station', 'ಕೆಂಪೇಗೌಡ ಬಸ್ ನಿಲ್ದಾಣ'),
      'WHITEFIELD': ('Whitefield', 'ವೈಟ್‌ಫೀಲ್ಡ್'),
      'ELECTRONIC CITY': ('Electronic City', 'ಎಲೆಕ್ಟ್ರಾನಿಕ್ ಸಿಟಿ'),
      'SILK BOARD': ('Central Silk Board', 'ಸಿಲ್ಕ್ ಬೋರ್ಡ್'),
      'SHIVAJINAGAR': ('Shivajinagar', 'ಶಿವಾಜಿನಗರ'),
      'KR MARKET': ('KR Market', 'ಕೆ.ಆರ್. ಮಾರ್ಕೆಟ್'),
      'BANASHANKARI': ('Banashankari', 'ಬನಶಂಕರಿ'),
      'HEBBAL': ('Hebbal', 'ಹೆಬ್ಬಾಳ'),
      'AIRPORT': ('Airport', 'ವಿಮಾನ ನಿಲ್ದಾಣ'),
      'RAILWAY STATION': ('Railway Station', 'ರೈಲ್ವೆ ನಿಲ್ದಾಣ'),
      'ಮೆಜೆಸ್ಟಿಕ್': ('Majestic', 'ಮೆಜೆಸ್ಟಿಕ್'),
      'ವೈಟ್‌ಫೀಲ್ಡ್': ('Whitefield', 'ವೈಟ್‌ಫೀಲ್ಡ್'),
      'ಎಲೆಕ್ಟ್ರಾನಿಕ್ ಸಿಟಿ': ('Electronic City', 'ಎಲೆಕ್ಟ್ರಾನಿಕ್ ಸಿಟಿ'),
      'ಶಿವಾಜಿನಗರ': ('Shivajinagar', 'ಶಿವಾಜಿನಗರ'),
    };

    String? detectedDestination;
    for (final entry in destinationKeywords.entries) {
      if (upper.contains(entry.key)) {
        detectedDestination = isKannada ? entry.value.$2 : entry.value.$1;
        break;
      }
    }

    // Bus Route Number Regex (matches patterns like 500-D, 335E, 201G, KBS-1, V-335E, 415H, MF-5, G-4, 365, etc.)
    final routeRegexes = [
      RegExp(r'\b([A-Z]{1,3}[- ]?\d{1,4}[A-Z]{0,2})\b'),
      RegExp(r'\b(\d{1,4}[- ]?[A-Z]{1,2})\b'),
      RegExp(r'\b(\d{3,4})\b'),
    ];

    String? detectedRoute;
    for (final regex in routeRegexes) {
      final matches = regex.allMatches(upper);
      for (final match in matches) {
        final candidate = match.group(1)?.replaceAll(' ', '-').trim();
        if (candidate != null &&
            candidate.length >= 2 &&
            !candidate.contains('RS') &&
            !candidate.contains('INR') &&
            !candidate.contains('AM') &&
            !candidate.contains('PM')) {
          detectedRoute = candidate;
          break;
        }
      }
      if (detectedRoute != null) break;
    }

    if (detectedRoute != null) {
      final destPart = detectedDestination != null
          ? (isKannada ? ', $detectedDestination ಕಡೆಗೆ' : ' towards $detectedDestination')
          : '';
      return isKannada
          ? 'ಆಗಮಿಸುತ್ತಿರುವ ಬಸ್: $detectedRoute$destPart.'
          : 'Approaching bus: Route $detectedRoute$destPart.';
    }

    if (detectedDestination != null) {
      return isKannada
          ? 'ಬೋರ್ಡ್ ಗುರುತಿಸಲಾಗಿದೆ: $detectedDestination ಕಡೆಗೆ ಹೋಗುವ ಬಸ್. ಬಸ್ ಸಂಖ್ಯೆ ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ.'
          : 'Destination board detected: Bus towards $detectedDestination. Route number is not yet visible.';
    }

    return isKannada
        ? 'ಯಾವುದೇ ಬಸ್ ಸಂಖ್ಯೆ ಕಂಡುಬಂದಿಲ್ಲ. ದಯವಿಟ್ಟು ಕ್ಯಾಮೆರಾವನ್ನು ಬಸ್ ಮುಂಭಾಗದ ಬೋರ್ಡ್ ಕಡೆಗೆ ಹಿಡಿಯಿರಿ.'
        : 'No bus route detected in frame. Please point the camera towards the bus windshield or destination display.';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static final Map<String, String> _cocoToKannada = {
    'person': 'ವ್ಯಕ್ತಿ',
    'car': 'ಕಾರು',
    'bicycle': 'ಸೈಕಲ್',
    'bike': 'ಬೈಕ್',
    'motorcycle': 'ಮೋಟಾರ್ ಸೈಕಲ್',
    'bus': 'ಬಸ್',
    'truck': 'ಟ್ರಕ್',
    'traffic light': 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್',
    'stop sign': 'ಸ್ಟಾಪ್ ಚಿಹ್ನೆ',
    'bench': 'ಬೆಂಚ್',
    'chair': 'ಕುರ್ಚಿ',
    'couch': 'ಸೋಫಾ',
    'potted plant': 'ಗಿಡ',
    'bed': 'ಹಾಸಿಗೆ',
    'dining table': 'ಊಟದ ಮೇಜು',
    'table': 'ಮೇಜು',
    'toilet': 'ಶೌಚಾಲಯ',
    'tv': 'ಟಿವಿ',
    'laptop': 'ಲ್ಯಾಪ್‌ಟಾಪ್',
    'mouse': 'ಮೌಸ್',
    'remote': 'ರಿಮೋಟ್',
    'keyboard': 'ಕೀಬೋರ್ಡ್',
    'cell phone': 'ಮೊಬೈಲ್ ಫೋನ್',
    'phone': 'ಫೋನ್',
    'microwave': 'ಮೈಕ್ರೋವೇವ್',
    'oven': 'ಓವನ್',
    'sink': 'ಸಿಂಕ್',
    'refrigerator': 'ರೆಫ್ರಿಜರೇಟರ್',
    'book': 'ಪುಸ್ತಕ',
    'clock': 'ಗಡಿಯಾರ',
    'vase': 'ಹೂದಾನಿ',
    'scissors': 'ಕತ್ತರಿ',
    'teddy bear': 'ಟೆಡ್ಡಿ ಬೇರ್',
    'hair drier': 'ಹೇರ್ ಡ್ರೈಯರ್',
    'toothbrush': 'ಟೂತ್‌ಬ್ರಷ್',
    'bottle': 'ಬಾಟಲ್',
    'water bottle': 'ನೀರಿನ ಬಾಟಲ್',
    'cup': 'ಕಪ್',
    'fork': 'ಫೋರ್ಕ್',
    'knife': 'ಚಾಕು',
    'spoon': 'ಚಮಚ',
    'bowl': 'ಬೌಲ್',
    'backpack': 'ಬ್ಯಾಗ್',
    'umbrella': 'ಛತ್ರಿ',
    'handbag': 'ಹ್ಯಾಂಡ್‌ಬ್ಯಾಗ್',
    'tie': 'ಟೈ',
    'suitcase': 'ಸೂಟ್‌ಕೇಸ್',
    'door': 'ಬಾಗಿಲು',
    'stairs': 'ಮೆಟ್ಟಿಲುಗಳು',
    'obstacle': 'ಅಡೆತಡೆ',
  };

  static final Map<String, String> _kannadaToCoco = {
    'ವ್ಯಕ್ತಿ': 'person',
    'ಜನ': 'person',
    'ಕಾರು': 'car',
    'ವಾಹನ': 'car',
    'ಸೈಕಲ್': 'bicycle',
    'ಬೈಕ್': 'motorcycle',
    'ಬಸ್': 'bus',
    'ಕುರ್ಚಿ': 'chair',
    'ಮೇಜು': 'dining table',
    'ಟೇಬಲ್': 'dining table',
    'ಸೋಫಾ': 'couch',
    'ಬಾಟಲ್': 'bottle',
    'ನೀರಿನ ಬಾಟಲ್': 'bottle',
    'ಕಪ್': 'cup',
    'ಗ್ಲಾಸ್': 'cup',
    'ಲ್ಯಾಪ್‌ಟಾಪ್': 'laptop',
    'ಲ್ಯಾಪ್ಟಾಪ್': 'laptop',
    'ಕಂಪ್ಯೂಟರ್': 'laptop',
    'ಮೊಬೈಲ್': 'cell phone',
    'ಮೊಬೈಲ್ ಫೋನ್': 'cell phone',
    'ಫೋನ್': 'cell phone',
    'ಪುಸ್ತಕ': 'book',
    'ಬ್ಯಾಗ್': 'backpack',
    'ಬಾಗಿಲು': 'door',
    'ಟಿವಿ': 'tv',
    'ಅಡೆತಡೆ': 'obstacle',
  };

  static String translateLabelToKannada(String label) {
    final lower = label.toLowerCase().trim();
    return _cocoToKannada[lower] ?? label;
  }

  bool _matchesTargetClass(String detectedLabel, String target) {
    final d = detectedLabel.toLowerCase().trim();
    String t = target.toLowerCase().trim();

    // Check if target is in Kannada and maps to a COCO class
    if (_kannadaToCoco.containsKey(t)) {
      t = _kannadaToCoco[t]!;
    }

    if (t.startsWith('my ')) {
      t = t.substring(3).trim();
    } else if (t.startsWith('the ')) {
      t = t.substring(4).trim();
    } else if (t.startsWith('a ')) {
      t = t.substring(2).trim();
    } else if (t.startsWith('an ')) {
      t = t.substring(3).trim();
    }

    if (d == t || d.contains(t) || t.contains(d)) return true;

    // Common synonyms
    final synonyms = {
      'bottle': ['water bottle', 'flask', 'beverage bottle', 'thermos'],
      'cup': ['mug', 'coffee cup', 'tea cup', 'glass'],
      'chair': ['seat', 'armchair', 'stool', 'bench'],
      'laptop': ['computer', 'notebook', 'pc', 'macbook'],
      'backpack': ['bag', 'schoolbag', 'knapsack', 'rucksack'],
      'cell phone': ['phone', 'mobile', 'smartphone', 'telephone', 'iphone'],
      'book': ['notebook', 'novel', 'textbook', 'journal', 'document'],
      'tv': ['television', 'screen', 'monitor', 'display'],
      'car': ['vehicle', 'automobile', 'sedan', 'suv', 'taxi'],
      'bicycle': ['bike', 'cycle'],
    };

    for (final entry in synonyms.entries) {
      if ((d == entry.key && entry.value.contains(t)) ||
          (t == entry.key && entry.value.contains(d))) {
        return true;
      }
    }

    return false;
  }

  bool _isCriticalShortTerm(String text) {
    final upper = text.toUpperCase().trim();
    const criticalWords = {
      'STOP', 'EXIT', 'ENTER', 'ENTRY', 'PUSH', 'PULL', 'OPEN', 'CLOSED',
      'MEN', 'WOMEN', 'RESTROOM', 'TOILET', 'LADIES', 'GENTS',
      'DANGER', 'CAUTION', 'WARNING', 'EMERGENCY', 'HOSPITAL', 'HELP',
      'IN', 'OUT', 'NO ENTRY', 'KEEP OUT', 'UP', 'DOWN', 'STAIRS', 'ELEVATOR',
    };
    return criticalWords.contains(upper) || RegExp(r'^(GATE|ROOM|PLATFORM|DOOR|NO\.)\s*\d+[A-Z]?$', caseSensitive: false).hasMatch(upper);
  }

  String _cleanOcrBlock(String raw) {
    final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Filter obvious single-character noise
    if (clean.length == 1 && RegExp(r'[^a-zA-Z0-9]').hasMatch(clean)) {
      return '';
    }
    return clean;
  }

  String _mapMlKitLabel(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('fashion') || lower.contains('clothing')) return 'clothing or bag';
    if (lower.contains('home') || lower.contains('furniture')) return 'furniture or obstacle';
    if (lower.contains('food')) return 'food item';
    if (lower.contains('plant')) return 'plant';
    if (lower.contains('electronic')) return 'electronic device';
    if (lower.contains('place') || lower.contains('building')) return 'doorway or structure';
    return raw.toLowerCase();
  }

  /// Analyzes oncoming traffic signals and pedestrian crossings for red, green, amber, or stop signs.
  Future<TrafficSignalAnalysis> analyzeTrafficSignal(
    String imagePath, {
    bool isKannada = false,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return const TrafficSignalAnalysis(
        state: TrafficSignalState.none,
        descriptionEn: 'Image file not found for traffic signal analysis.',
        descriptionKn: 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲನೆಗೆ ಚಿತ್ರ ಲಭ್ಯವಿಲ್ಲ.',
        confidence: 0.0,
      );
    }

    try {
      final objects = await _objectDetectorService.detectObjectsFromPath(
        imagePath,
        confidenceThreshold: 0.35,
      );

      // 1. Check for Stop Sign
      final stopSign = objects.firstWhere(
        (o) => o.label.contains('stop sign'),
        orElse: () => const DetectedVisionItem(
          label: '',
          confidence: 0,
          boundingBox: Rect.zero,
          position: '',
        ),
      );
      if (stopSign.label.isNotEmpty) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.stopSign,
          descriptionEn: 'Stop sign detected ahead. Ensure all traffic has stopped before crossing.',
          descriptionKn: 'ಮುಂದೆ ಸ್ಟಾಪ್ ಸೈನ್ ಕಂಡುಬಂದಿದೆ. ವಾಹನಗಳು ಸಂಪೂರ್ಣವಾಗಿ ನಿಲ್ಲುವವರೆಗೂ ರಸ್ತೆ ದಾಟಬೇಡಿ.',
          confidence: 0.85,
        );
      }

      // 2. Check for Traffic Light object
      final trafficLight = objects.firstWhere(
        (o) => o.label.contains('traffic light'),
        orElse: () => const DetectedVisionItem(
          label: '',
          confidence: 0,
          boundingBox: Rect.zero,
          position: '',
        ),
      );

      if (trafficLight.label.isEmpty) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.none,
          descriptionEn: 'No traffic lights or signals detected in camera view. Hold phone higher towards the intersection.',
          descriptionKn: 'ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಕಂಡುಬಂದಿಲ್ಲ. ಕ್ಯಾಮೆರಾವನ್ನು ರಸ್ತೆ ಜಂಕ್ಷನ್ ಕಡೆಗೆ ಸ್ವಲ್ಪ ಮೇಲಕ್ಕೆ ಹಿಡಿಯಿರಿ.',
          confidence: 0.0,
        );
      }

      // 3. Chrominance & Spatial Analysis on Traffic Light crop
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.uncertain,
          descriptionEn: 'Traffic light detected, but could not decode image.',
          descriptionKn: 'ಟ್ರಾಫಿಕ್ ಲೈಟ್ ಕಂಡುಬಂದಿದೆ, ಆದರೆ ಚಿತ್ರ ಸ್ಪಷ್ಟವಿಲ್ಲ.',
          confidence: 0.5,
        );
      }

      final box = trafficLight.boundingBox;
      final x1 = box.left.clamp(0, decoded.width - 1).toInt();
      final y1 = box.top.clamp(0, decoded.height - 1).toInt();
      final x2 = box.right.clamp(1, decoded.width).toInt();
      final y2 = box.bottom.clamp(1, decoded.height).toInt();
      final boxH = (y2 - y1).clamp(1, decoded.height);

      // Sample Upper Half (Red light location in vertical signals)
      final upperYEnd = y1 + (boxH * 0.45).toInt();
      double upperRed = 0, upperGreen = 0, upperBlue = 0;
      int upperCount = 0;

      for (int y = y1; y < upperYEnd; y += 2) {
        for (int x = x1; x < x2; x += 2) {
          final p = decoded.getPixel(x, y);
          upperRed += p.r;
          upperGreen += p.g;
          upperBlue += p.b;
          upperCount++;
        }
      }

      // Sample Lower Half (Green light location in vertical signals)
      final lowerYStart = y1 + (boxH * 0.55).toInt();
      double lowerRed = 0, lowerGreen = 0, lowerBlue = 0;
      int lowerCount = 0;

      for (int y = lowerYStart; y < y2; y += 2) {
        for (int x = x1; x < x2; x += 2) {
          final p = decoded.getPixel(x, y);
          lowerRed += p.r;
          lowerGreen += p.g;
          lowerBlue += p.b;
          lowerCount++;
        }
      }

      final avgUpperR = upperCount > 0 ? upperRed / upperCount : 0.0;
      final avgUpperG = upperCount > 0 ? upperGreen / upperCount : 0.0;
      final avgUpperB = upperCount > 0 ? upperBlue / upperCount : 0.0;

      final avgLowerR = lowerCount > 0 ? lowerRed / lowerCount : 0.0;
      final avgLowerG = lowerCount > 0 ? lowerGreen / lowerCount : 0.0;
      final avgLowerB = lowerCount > 0 ? lowerBlue / lowerCount : 0.0;

      final redDominance = (avgUpperR > 100 && avgUpperR > avgUpperG * 1.25 && avgUpperR > avgUpperB * 1.25)
          ? (avgUpperR - (avgUpperG + avgUpperB) / 2)
          : 0.0;

      final greenDominance = (avgLowerG > 90 && avgLowerG > avgLowerR * 1.15 && avgLowerG > avgLowerB * 0.85)
          ? (avgLowerG - (avgLowerR + avgLowerB) / 2)
          : 0.0;

      if (redDominance > 20 && redDominance > greenDominance) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.red,
          descriptionEn: 'Warning! Traffic signal appears RED. Do not cross. Wait for green signal.',
          descriptionKn: 'ಎಚ್ಚರಿಕೆ! ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಕೆಂಪು (ರೆಡ್) ಆಗಿದೆ. ರಸ್ತೆ ದಾಟಬೇಡಿ. ಹಸಿರು ಸಿಗ್ನಲ್‌ಗಾಗಿ ಕಾಯಿರಿ.',
          confidence: 0.80,
        );
      }

      if (greenDominance > 15 && greenDominance > redDominance) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.green,
          descriptionEn: 'Traffic signal appears GREEN. Pedestrian crossing may be permitted. Proceed with caution and always listen for vehicle movement.',
          descriptionKn: 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಹಸಿರು (ಗ್ರೀನ್) ಆಗಿದೆ. ಎಚ್ಚರಿಕೆಯಿಂದ ಮುನ್ನಡೆಯಿರಿ ಮತ್ತು ವಾಹನಗಳ ಸದ್ದನ್ನು ಗಮನಿಸಿ.',
          confidence: 0.80,
        );
      }

      // Middle Amber Check
      final midYStart = y1 + (boxH * 0.35).toInt();
      final midYEnd = y1 + (boxH * 0.65).toInt();
      double midR = 0, midG = 0, midB = 0;
      int midCount = 0;
      for (int y = midYStart; y < midYEnd; y += 2) {
        for (int x = x1; x < x2; x += 2) {
          final p = decoded.getPixel(x, y);
          midR += p.r;
          midG += p.g;
          midB += p.b;
          midCount++;
        }
      }
      final avgMidR = midCount > 0 ? midR / midCount : 0.0;
      final avgMidG = midCount > 0 ? midG / midCount : 0.0;
      final avgMidB = midCount > 0 ? midB / midCount : 0.0;

      if (avgMidR > 120 && avgMidG > 95 && avgMidB < 90 && avgMidR > avgMidB * 1.3) {
        return const TrafficSignalAnalysis(
          state: TrafficSignalState.yellow,
          descriptionEn: 'Caution: Traffic signal is AMBER or YELLOW. Prepare to wait.',
          descriptionKn: 'ಎಚ್ಚರಿಕೆ: ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಹಳದಿಯಾಗಿದೆ. ನಿಲ್ಲಲು ಸಿದ್ಧರಾಗಿ.',
          confidence: 0.75,
        );
      }

      return const TrafficSignalAnalysis(
        state: TrafficSignalState.uncertain,
        descriptionEn: 'Traffic light detected, but illuminated color cannot be determined with certainty. Please wait and listen carefully before crossing.',
        descriptionKn: 'ಟ್ರಾಫಿಕ್ ಲೈಟ್ ಕಂಡುಬಂದಿದೆ, ಆದರೆ ಬಣ್ಣ ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ. ರಸ್ತೆ ದಾಟುವ ಮುನ್ನ ವಾಹನಗಳ ಸದ್ದನ್ನು ಎಚ್ಚರಿಕೆಯಿಂದ ಆಲಿಸಿ.',
        confidence: 0.50,
      );
    } catch (e) {
      debugPrint('Error analyzing traffic signal: $e');
      return const TrafficSignalAnalysis(
        state: TrafficSignalState.uncertain,
        descriptionEn: 'Traffic light detected. Listen for traffic before crossing.',
        descriptionKn: 'ಟ್ರಾಫಿಕ್ ಲೈಟ್ ಕಂಡುಬಂದಿದೆ. ರಸ್ತೆ ದಾಟುವ ಮುನ್ನ ವಾಹನಗಳ ಸದ್ದನ್ನು ಆಲಿಸಿ.',
        confidence: 0.40,
      );
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _objectDetectorService.dispose();
    _textRecognizer?.close();
    _mlkitFallbackDetector?.close();
  }
}
