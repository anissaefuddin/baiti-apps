import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Result from a KTP (Indonesian national ID card) scan.
class KtpScanResult {
  const KtpScanResult({this.nik, this.name});

  /// 16-digit NIK extracted from the card, or null if not found.
  final String? nik;

  /// Full name extracted from the card, or null if not found.
  final String? name;

  bool get hasData => nik != null || name != null;
}

/// Picks a KTP image and extracts NIK and name using on-device ML Kit OCR.
///
/// All processing is done locally — no data is sent to any server.
class KtpScanner {
  KtpScanner._();

  static final _picker = ImagePicker();

  /// Pick an image from [source] and scan it for KTP data.
  ///
  /// Returns null if the user cancels the picker.
  /// Throws if ML Kit fails to process the image.
  static Future<KtpScanResult?> pickAndScan(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 100,   // no compression — OCR needs full detail
      maxWidth: 1920,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return scan(image);
  }

  /// Scan an already-picked [imageFile] for KTP data.
  static Future<KtpScanResult> scan(XFile imageFile) async {
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(inputImage);
      return _parse(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  static KtpScanResult _parse(String rawText) {
    return KtpScanResult(
      nik:  _extractNik(rawText),
      name: _extractName(rawText),
    );
  }

  /// Find the first 16-digit NIK sequence.
  /// Handles both compact ("3374061212900001") and spaced ("3374 0612 1290 0001") formats.
  static String? _extractNik(String text) {
    // Compact 16-digit run
    final compact = RegExp(r'\b\d{16}\b').firstMatch(text);
    if (compact != null) return compact.group(0);

    // Spaced: groups of 4 digits separated by spaces or dashes
    final spaced = RegExp(r'\b\d{4}[\s\-]\d{4}[\s\-]\d{4}[\s\-]\d{4}\b')
        .firstMatch(text);
    if (spaced != null) {
      return spaced.group(0)!.replaceAll(RegExp(r'[\s\-]'), '');
    }

    return null;
  }

  /// Find the name after the "Nama" label.
  /// KTP layout has "Nama : JOHN DOE" on one line, or "Nama" then the name
  /// on the next line.
  static String? _extractName(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (int i = 0; i < lines.length; i++) {
      // Match "Nama", "NAMA", "Nama :", etc. — allow OCR artifacts like "Narna"
      if (!RegExp(r'(?i)na?ma').hasMatch(lines[i])) continue;

      // Value on the same line after the label ("Nama : JOHN DOE")
      final inlineName = lines[i]
          .replaceFirst(RegExp(r'(?i)na?ma\s*:?\s*'), '')
          .trim();
      if (inlineName.isNotEmpty) return _cleanName(inlineName);

      // Value on the next line
      if (i + 1 < lines.length) return _cleanName(lines[i + 1]);
    }

    return null;
  }

  /// Strip OCR noise — keep only letters, spaces, hyphens, apostrophes.
  static String _cleanName(String raw) {
    return raw
        .replaceAll(RegExp(r"[^a-zA-Z\s\-\'\.]"), '')
        .trim()
        .toUpperCase();
  }
}
