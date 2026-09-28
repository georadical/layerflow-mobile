import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/manzana_label.dart';

void main() {
  group('manzanaLabel (LADM_COL, backend-pinned PC.6)', () {
    test('zona 00 shows Urbana by name (worker preference)', () {
      // Real Ruta 10 code: 41359 · 00 · 00 · 0000 · 0050
      expect(manzanaLabel('41359000000000050'), 'Zona: Urbana · Mz 50');
    });

    test('zona 01 shows Rural by name', () {
      // Real Ruta 10 code: 41359 · 01 · 00 · 0000 · 0088 (a vía-addressed
      // predio in a rural zona near the casco).
      expect(manzanaLabel('41359010000000088'), 'Zona: Rural · Mz 88');
    });

    test('non-zero barrio is kept (uniqueness in a big city)', () {
      // 41359 · 00 · 00 · 0101 · 0132 (Valle-style)
      expect(manzanaLabel('41359000001010132'), 'Zona: Urbana · B101 · Mz 132');
    });

    test('a two-digit sector is not assumed single-width (10/11 are real)', () {
      // sector [7:9] = 10 → S10; manzana 0007 → Mz 7
      expect(manzanaLabel('41359001000000007'), 'Zona: Urbana · S10 · Mz 7');
    });

    test('all sub-fields stack in order Zona · S · B · Mz', () {
      // zona 01, sector 03, barrio 0045, manzana 0132
      expect(
        manzanaLabel('41359010300450132'),
        'Zona: Rural · S3 · B45 · Mz 132',
      );
    });

    test('an unknown zona code falls back to "Zona NN", never mislabelled', () {
      // zona 02 is not in the confirmed map → keep the code, do not guess.
      expect(manzanaLabel('41359020000000015'), 'Zona 02 · Mz 15');
    });

    test('a manzana of all zeros still shows Mz 0', () {
      expect(manzanaLabel('41359000000000000'), 'Zona: Urbana · Mz 0');
    });

    test('anything not a clean 17-digit code is returned verbatim', () {
      expect(manzanaLabel('M1'), 'M1');
      expect(manzanaLabel('4135900000000005'), '4135900000000005'); // 16 digits
      expect(manzanaLabel('41359ABCD00000050'), '41359ABCD00000050');
    });
  });
}
