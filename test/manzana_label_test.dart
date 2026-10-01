import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/manzana_label.dart';

void main() {
  group('manzanaLabel (LADM_COL, backend-pinned PC.6)', () {
    test('zona 00 is Rural (backend: 00=Rural, e.g. Salto de Bordones)', () {
      // Real Ruta 10 code: 41359 · 00 · 00 · 0000 · 0050 — a rural corregimiento
      // that still has calles, hence a "CARRERA 2 # 3" address.
      expect(manzanaLabel('41359000000000050'), 'Zona: Rural · Mz 50');
    });

    test('zona 01 is Urbana (cabecera)', () {
      // Real Ruta 10 code: 41359 · 01 · 00 · 0000 · 0088
      expect(manzanaLabel('41359010000000088'), 'Zona: Urbana · Mz 88');
    });

    test('zona 02+ is a numbered Centro poblado (no invented name)', () {
      expect(manzanaLabel('41359020000000015'), 'Centro poblado 2 · Mz 15');
      expect(manzanaLabel('41359440000000009'), 'Centro poblado 44 · Mz 9');
    });

    test('non-zero barrio is kept (uniqueness in a big city)', () {
      // 41359 · 01 · 00 · 0101 · 0132 (Valle-style, urban)
      expect(manzanaLabel('41359010001010132'), 'Zona: Urbana · B101 · Mz 132');
    });

    test('a two-digit sector is not assumed single-width (10/11 are real)', () {
      // sector [7:9] = 10 → S10; manzana 0007 → Mz 7
      expect(manzanaLabel('41359011000000007'), 'Zona: Urbana · S10 · Mz 7');
    });

    test('all sub-fields stack in order Zona · S · B · Mz', () {
      // zona 01, sector 03, barrio 0045, manzana 0132
      expect(
        manzanaLabel('41359010300450132'),
        'Zona: Urbana · S3 · B45 · Mz 132',
      );
    });

    test('a manzana of all zeros still shows Mz 0', () {
      expect(manzanaLabel('41359010000000000'), 'Zona: Urbana · Mz 0');
    });

    test('anything not a clean 17-digit code is returned verbatim', () {
      expect(manzanaLabel('M1'), 'M1');
      expect(manzanaLabel('4135900000000005'), '4135900000000005'); // 16 digits
      expect(manzanaLabel('41359ABCD00000050'), '41359ABCD00000050');
    });
  });
}
