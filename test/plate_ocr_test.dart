import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/ocr/plate_ocr.dart';

void main() {
  group('plateMismatch (CL-R2 — assist, never decide)', () {
    test('identical readings are silent', () {
      expect(plateMismatch('C 5 2-06', 'C 5 2 06'), isFalse,
          reason: 'symbols and spacing wash out in the pinned clean');
    });

    test('a single digit difference PROMPTS — the very error this exists for',
        () {
      expect(plateMismatch('C 5 2-08', 'C 5 2 06'), isTrue);
    });

    test('letter noise with equal digits stays silent (OCR blur)', () {
      expect(plateMismatch('CAILE 5 2-06', 'CALLE 5 2-06'), isFalse);
    });

    test('a completely different reading prompts', () {
      expect(plateMismatch('TIENDA DONDE PEPE', 'C 5 2 06'), isTrue);
    });

    test('empty either side is silence, never a nag', () {
      expect(plateMismatch('', 'C 5 2 06'), isFalse);
      expect(plateMismatch('C 5 2 06', '   '), isFalse);
    });

    test('digit-free readings fall back to overall similarity', () {
      expect(plateMismatch('SAMARIA', 'SAMARIA'), isFalse);
      expect(plateMismatch('SAMARIA', 'LA PRADERA'), isTrue);
    });
  });
}
