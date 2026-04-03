import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Parsed fields extracted from a KTP (Indonesian national ID card) image.
class KtpOcrResult {
  const KtpOcrResult({
    this.nik = '',
    this.name = '',
    this.address = '',
    this.birthDate = '',
    this.rawText = '',
  });

  /// 16-digit Nomor Induk Kependudukan.
  final String nik;

  /// Full name as printed on the KTP.
  final String name;

  /// Combined address: Alamat + RT/RW + Kel/Desa + Kecamatan.
  final String address;

  /// Birth date in DD-MM-YYYY format.
  final String birthDate;

  /// Raw OCR text (useful for debugging or manual review).
  final String rawText;

  bool get hasNik  => nik.isNotEmpty;
  bool get hasName => name.isNotEmpty;
  bool get hasData => hasNik || hasName || address.isNotEmpty || birthDate.isNotEmpty;
}

/// On-device OCR service for Indonesian KTP cards using Google ML Kit.
///
/// Handles common OCR noise:
///  - Spaces inside digit groups ("3317 0656 …" → "3317065605980001")
///  - Letter/digit substitutions in NIK context (O→0, I→1, S→5, B→8, etc.)
///  - Label on one line, value on the next (or same line separated by spaces)
///  - "Tempat/Tgl Lahir" as the full birth-date label
class KtpOcrService {
  KtpOcrService._();

  /// Run OCR on [image] and return a [KtpOcrResult].
  /// Fields that cannot be extracted are left empty — never throws for a parse
  /// failure, only for I/O errors from ML Kit itself.
  static Future<KtpOcrResult> processImage(XFile image) async {
    final inputImage = InputImage.fromFilePath(image.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised = await recognizer.processImage(inputImage);
      return _parse(recognised.text);
    } finally {
      await recognizer.close();
    }
  }

  // ── Parser entry point ────────────────────────────────────────────────────

  static KtpOcrResult _parse(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String nik       = '';
    String name      = '';
    String birthDate = '';
    String address   = '';

    // Track consumed line indices so address continuation doesn't re-use them.
    final consumed = <int>{};

    for (int i = 0; i < lines.length; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];

      // ── NIK ──────────────────────────────────────────────────────────────
      if (nik.isEmpty && _startsWithLabel(line, r'nik')) {
        final inline = _valueAfter(line, r'nik');
        final src    = inline.isNotEmpty ? inline
            : (i + 1 < lines.length ? lines[i + 1] : '');
        nik = _parseNik(src);
        if (nik.isNotEmpty && inline.isEmpty) consumed.add(i + 1);
        continue;
      }

      // ── Nama ─────────────────────────────────────────────────────────────
      // OCR sometimes misreads 'm' as 'rn' → allow "Na(m|rn)a" as the label.
      if (name.isEmpty && _startsWithLabel(line, r'na(?:m|rn)a')) {
        final inline = _valueAfter(line, r'na(?:m|rn)a');
        final src    = inline.isNotEmpty ? inline
            : (i + 1 < lines.length ? lines[i + 1] : '');
        name = _parseName(src);
        if (name.isNotEmpty && inline.isEmpty) consumed.add(i + 1);
        continue;
      }

      // ── Tempat/Tgl Lahir ─────────────────────────────────────────────────
      // Full label: "Tempat/Tgl Lahir" — but OCR may drop "Tempat/" part.
      if (birthDate.isEmpty &&
          RegExp(r'(?:tempat|tgl|tanggal)', caseSensitive: false).hasMatch(line) &&
          line.toLowerCase().contains('lahir')) {
        final inline = _valueAfter(
            line, r'(?:tempat\s*[/\s]\s*)?(?:tgl\.?\s*|tanggal\s*)lahir');
        final src = inline.isNotEmpty ? inline
            : (i + 1 < lines.length ? lines[i + 1] : '');
        birthDate = _parseBirthDate(src);
        if (birthDate.isNotEmpty && inline.isEmpty) consumed.add(i + 1);
        continue;
      }

      // ── Alamat ────────────────────────────────────────────────────────────
      if (address.isEmpty && _startsWithLabel(line, r'alamat')) {
        final inline = _valueAfter(line, r'alamat');
        var   addr   = inline;
        int   next   = i + 1;

        // Value may be on the next line
        if (addr.isEmpty && next < lines.length && !_isKnownLabel(lines[next])) {
          addr = lines[next];
          consumed.add(next);
          next++;
        }

        // Append RT/RW, Kel/Desa, Kecamatan for a fuller address.
        for (int j = next; j < lines.length && j <= i + 6; j++) {
          if (consumed.contains(j)) continue;
          final jl = lines[j];

          if (_startsWithLabel(jl, r'rt(?:[/\-]rw)?')) {
            final v = _valueAfter(jl, r'rt(?:[/\-]rw)?');
            if (v.isNotEmpty) { addr += ', RT/RW $v'; consumed.add(j); }
          } else if (_startsWithLabel(jl, r'kel(?:[/\-]desa?)?')) {
            final v = _valueAfter(jl, r'kel(?:[/\-]desa?)?');
            if (v.isNotEmpty) { addr += ', $v'; consumed.add(j); }
          } else if (_startsWithLabel(jl, r'kecamatan')) {
            final v = _valueAfter(jl, r'kecamatan');
            if (v.isNotEmpty) { addr += ', Kec. $v'; consumed.add(j); break; }
          } else if (_isKnownLabel(jl)) {
            break;
          }
        }

        // Clean up: remove trailing dot/comma, collapse whitespace.
        address = addr
            .trim()
            .replaceAll(RegExp(r'[.,]\s*,'), ',')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
        continue;
      }
    }

    // Fallback: find any 16-digit NIK anywhere in the raw text.
    if (nik.isEmpty) nik = _findNikAnywhere(raw);

    return KtpOcrResult(
      nik:       nik,
      name:      name,
      address:   address,
      birthDate: birthDate,
      rawText:   raw,
    );
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  /// True if [line] starts with [labelPattern] (case-insensitive).
  static bool _startsWithLabel(String line, String labelPattern) =>
      RegExp('^(?:$labelPattern)', caseSensitive: false).hasMatch(line);

  /// True if [line] starts with any standard KTP field label.
  static bool _isKnownLabel(String line) {
    const patterns = [
      r'nik', r'na(?:m|rn)a', r'tempat', r'tgl', r'tanggal', r'jenis',
      r'gol', r'alamat', r'rt', r'kel', r'kecamatan', r'agama',
      r'status', r'pekerjaan', r'kewarganegaraan', r'berlaku',
    ];
    return patterns.any(
        (p) => RegExp('^$p', caseSensitive: false).hasMatch(line));
  }

  /// Extract the value portion of a "Label : Value" or "Label   Value" line.
  static String _valueAfter(String line, String labelPattern) {
    // Match the label, then an optional separator (colon, hyphen, slash),
    // then leading whitespace — the rest is the value.
    final re = RegExp(
      r'^(?:' + labelPattern + r')\s*[:\-]?\s*',
      caseSensitive: false,
    );
    final m = re.firstMatch(line);
    if (m == null) return '';
    return line.substring(m.end).trim();
  }

  // ── Field parsers ─────────────────────────────────────────────────────────

  /// Parse a 16-digit NIK from a raw candidate string.
  ///
  /// Applies OCR corrections for characters that are commonly misread as
  /// digits (O→0, I/l→1, S→5, B→8, G→6, Z→2) before extracting.
  static String _parseNik(String candidate) {
    if (candidate.isEmpty) return '';

    // Correct letters that look like digits (in NIK, everything must be a digit).
    final corrected = candidate
        .replaceAll('O', '0').replaceAll('o', '0')
        .replaceAll('I', '1').replaceAll('l', '1')
        .replaceAll('S', '5')
        .replaceAll('B', '8')
        .replaceAll('G', '6')
        .replaceAll('Z', '2')
        .replaceAll('T', '7');

    // Remove all non-digit characters (spaces, colons, hyphens, etc.).
    final digitsOnly = corrected.replaceAll(RegExp(r'[^\d]'), '');

    // Take the first 16 digits.
    if (digitsOnly.length >= 16) return digitsOnly.substring(0, 16);

    return '';
  }

  /// Search anywhere in [raw] for a 16-digit NIK sequence.
  static String _findNikAnywhere(String raw) {
    // Try compact 16 consecutive digits.
    final compact = RegExp(r'\b\d{16}\b').firstMatch(raw);
    if (compact != null) return compact.group(0)!;

    // Try four groups of 4 digits separated by single spaces.
    final spaced = RegExp(r'\b\d{4} \d{4} \d{4} \d{4}\b').firstMatch(raw);
    if (spaced != null) return spaced.group(0)!.replaceAll(' ', '');

    return '';
  }

  /// Extract the name from a candidate string (value after "Nama" label).
  static String _parseName(String candidate) {
    if (candidate.isEmpty) return '';

    // Stop at the next known field label appearing inline.
    final stopRe = RegExp(
      r'(?:tempat|tgl|jenis|gol|alamat|rt[/\-]|kel|kecamatan|agama|status|pekerjaan)',
      caseSensitive: false,
    );
    final stop  = stopRe.firstMatch(candidate);
    final part  = stop != null ? candidate.substring(0, stop.start) : candidate;

    // Keep only alphabetic characters, spaces, hyphens, apostrophes.
    final cleaned = part
        .replaceAll(RegExp(r"[^a-zA-Z\s\-\'\.]"), '')
        .trim()
        .replaceAll(RegExp(r'\s{2,}'), ' ');

    if (cleaned.length < 2) return '';

    return _toTitleCase(cleaned);
  }

  /// Extract a DD-MM-YYYY date from the birth-date candidate string.
  /// The KTP format is "CITY, DD-MM-YYYY".
  static String _parseBirthDate(String candidate) {
    if (candidate.isEmpty) return '';

    // Prefer hyphen-separated date.
    final m1 = RegExp(r'\b(\d{2}-\d{2}-\d{4})\b').firstMatch(candidate);
    if (m1 != null) return m1.group(1)!;

    // Also accept slash or dot separators and normalise to hyphen.
    final m2 = RegExp(r'\b(\d{2}[/\.]\d{2}[/\.]\d{4})\b').firstMatch(candidate);
    if (m2 != null) return m2.group(1)!.replaceAll(RegExp(r'[/\.]'), '-');

    return '';
  }

  static String _toTitleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
