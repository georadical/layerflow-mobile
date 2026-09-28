/// Human-readable label for a 17-digit LADM_COL manzana catastral código
/// (Spec 10, PC.6). The full código is unambiguous but unwieldy; the bare tail
/// ("50", "88") collides across the thousands of manzanas a large city has.
///
/// Algorithm pinned by the backend against 6.8M national rows — one fixed-width
/// cut, no per-department cases:
///   [0:5]  ESP prefix (depto+municipio) — constant per token, omitted
///   [5:7]  zona     → "Zona: Urbana" / "Zona: Rural" (semantic, always shown)
///   [7:9]  sector   → "S"
///   [9:13] barrio   → "B"
///   [13:17] manzana → "Mz" (always shown)
/// Each numeric sub-field is cut at its NOMINAL width THEN left-trimmed of zeros
/// (real sectors reach 10/11, so widths are not 1). The non-zero intermediate
/// fields are what give uniqueness where the manzana number alone would collide
/// — meaning, not decoration.
///
/// The zona is shown by NAME rather than its code (worker preference), mapping
/// pinned by the backend against 6.8M rows (Huila+Valle): `00` → Rural, `01` →
/// Urbana (cabecera), `02`+ → "Centro poblado NN" (numbered corregimientos /
/// centros poblados, up to 44 distinct in Bolívar). The zona is the CATASTRAL
/// class, not a guarantee of address style — a rural zona (00) can still carry
/// "CARRERA 2 # 3" addresses (e.g. Salto de Bordones, a rural corregimiento
/// with calles). The código does not carry the corregimiento's proper name
/// (that lives in the address suffix), so we show the number, never invent one.
///
/// Anything not a clean 17-digit código is returned verbatim (defensive: never
/// hide a value we do not understand).
library;

String _zonaLabel(String code) {
  switch (code) {
    case '00':
      return 'Zona: Rural';
    case '01':
      return 'Zona: Urbana';
    default:
      final n = code.replaceFirst(RegExp(r'^0+'), '');
      return 'Centro poblado ${n.isEmpty ? '0' : n}';
  }
}

String manzanaLabel(String codigo) {
  final c = codigo.trim();
  if (c.length != 17 || !RegExp(r'^\d{17}$').hasMatch(c)) return c;

  String field(int start, int end) =>
      c.substring(start, end).replaceFirst(RegExp(r'^0+'), '');

  final sector = field(7, 9);
  final barrio = field(9, 13);
  final manzana = field(13, 17);

  return [
    _zonaLabel(c.substring(5, 7)),
    if (sector.isNotEmpty) 'S$sector',
    if (barrio.isNotEmpty) 'B$barrio',
    'Mz ${manzana.isEmpty ? '0' : manzana}',
  ].join(' · ');
}
