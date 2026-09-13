import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../address/address_normalizer.dart';

/// On-device OCR soft-check (Spec 7, CL-R2).
///
/// It ASSISTS, never decides: only a mismatch surfaces a "¿confirmas?"
/// prompt; when the OCR reads nothing plausible there is total silence.
/// No OCR text ever reaches the backend, and no photo needs to be stored
/// for the check — it reads the same frame the evidence photo reuses.
class PlateOcr {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Best plate-like line read from [imagePath], or null when nothing
  /// plausible was found (→ silence). Plausible = after the pinned clean,
  /// it carries at least one digit and three characters.
  Future<String?> readPlate(String imagePath) async {
    try {
      final result =
          await _recognizer.processImage(InputImage.fromFilePath(imagePath));
      String? best;
      var bestDigits = 0;
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final cleaned = cleanAddress(line.text);
          final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '').length;
          if (cleaned.length >= 3 && digits > bestDigits) {
            best = line.text;
            bestDigits = digits;
          }
        }
      }
      return best;
    } catch (_) {
      return null; // any OCR failure = silence, never a nag
    }
  }

  Future<void> dispose() => _recognizer.close();
}

/// Whether the OCR reading disagrees with what the worker typed/selected —
/// pure logic, unit-tested apart from ML Kit.
///
/// Two signals, either one prompts:
/// - overall similarity below [threshold] (edit distance over the two
///   CLEANED strings, the pinned mechanism);
/// - the DIGIT sequences differ. Plates differ by digits far more than by
///   letters ("2-08" vs "2-06" is exactly the transcription error this
///   check exists for), while OCR noise usually lands on letters — so
///   digits are compared exactly and letters tolerantly.
///
/// Empty or implausible input on either side → false (silence, CL-R2).
bool plateMismatch(
  String ocrText,
  String reference, {
  double threshold = 0.7,
}) {
  final a = cleanAddress(ocrText);
  final b = cleanAddress(reference);
  if (a.isEmpty || b.isEmpty) return false;

  final digitsA = a.replaceAll(RegExp(r'[^0-9]'), '');
  final digitsB = b.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsA.isNotEmpty && digitsB.isNotEmpty && digitsA != digitsB) {
    return true;
  }

  final maxLen = a.length > b.length ? a.length : b.length;
  final similarity = 1 - editDistance(a, b) / maxLen;
  return similarity < threshold;
}
