import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/cruce_guard.dart';

/// LX.3b — the missing-CON guard (Spec 12 amendment BR-C4, AC-C4).
void main() {
  group('looksLikeCruceMissingCon', () {
    test('two streets without CON → warn', () {
      expect(looksLikeCruceMissingCon('CALLE 13 CARRERA 3'), isTrue);
      expect(looksLikeCruceMissingCon('kr 3 cl 13'), isTrue);
      expect(looksLikeCruceMissingCon('Carrera 3 Calle 13'), isTrue);
    });

    test('with CON → no warning (it is a proper cruce)', () {
      expect(looksLikeCruceMissingCon('CALLE 13 CON CARRERA 3'), isFalse);
    });

    test('a normal door placa → no warning', () {
      expect(looksLikeCruceMissingCon('CALLE 13 # 3-20'), isFalse);
      expect(looksLikeCruceMissingCon('3-20'), isFalse);
    });

    test('single-letter suffixes do not count as streets', () {
      expect(looksLikeCruceMissingCon('CALLE 13 A 3 20'), isFalse);
      expect(looksLikeCruceMissingCon('K 2 4A 09'), isFalse);
    });

    test('blank / rural text → no warning', () {
      expect(looksLikeCruceMissingCon(''), isFalse);
      expect(looksLikeCruceMissingCon('Vacío en potrero'), isFalse);
    });
  });
}
