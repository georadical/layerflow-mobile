import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/manzana_label.dart';

void main() {
  group('manzanaLabel (LADM_COL, backend-pinned PC.6)', () {
    test('all intermediate fields zero → just the manzana', () {
      // Real Ruta 10 code: 41359 · 00 · 00 · 0000 · 0050
      expect(manzanaLabel('41359000000000050'), 'Mz50');
    });

    test('non-zero zona is kept (uniqueness, not decoration)', () {
      // Real Ruta 10 code: 41359 · 01 · 00 · 0000 · 0088
      expect(manzanaLabel('41359010000000088'), 'Z1·Mz88');
    });

    test('non-zero barrio is kept (backend example)', () {
      // 41359 · 00 · 00 · 0101 · 0132 (Valle-style)
      expect(manzanaLabel('41359000001010132'), 'B101·Mz132');
    });

    test('a two-digit sector is not assumed single-width (10/11 are real)', () {
      // sector [7:9] = 10 → S10; manzana 0007 → Mz7
      expect(manzanaLabel('41359001000000007'), 'S10·Mz7');
    });

    test('all sub-fields non-zero stack in order Z·S·B·Mz', () {
      // zona 02, sector 03, barrio 0045, manzana 0132
      expect(manzanaLabel('41359020300450132'), 'Z2·S3·B45·Mz132');
    });

    test('a manzana of all zeros still shows Mz0', () {
      expect(manzanaLabel('41359000000000000'), 'Mz0');
    });

    test('anything not a clean 17-digit code is returned verbatim', () {
      expect(manzanaLabel('M1'), 'M1');
      expect(manzanaLabel('4135900000000005'), '4135900000000005'); // 16 digits
      expect(manzanaLabel('41359ABCD00000050'), '41359ABCD00000050');
    });
  });
}
