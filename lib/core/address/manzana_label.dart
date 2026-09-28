/// Human-readable label for a 17-digit LADM_COL manzana catastral código
/// (Spec 10, PC.6). The full código is unambiguous but unwieldy; the bare tail
/// ("50", "88") collides across the thousands of manzanas a large city has.
///
/// Algorithm pinned by the backend against 6.8M national rows — one fixed-width
/// cut, no per-department cases:
///   [0:5]  ESP prefix (depto+municipio) — constant per token, omitted
///   [5:7]  zona     → "Z"
///   [7:9]  sector   → "S"
///   [9:13] barrio   → "B"
///   [13:17] manzana → "Mz" (always shown)
/// Each sub-field is cut at its NOMINAL width THEN left-trimmed of zeros (real
/// sectors reach 10/11, so widths are not 1). The non-zero intermediate fields
/// are what give uniqueness where the manzana number alone would collide — they
/// are meaning, not decoration. In a small municipality this usually collapses
/// to just "Mz N".
///
/// Anything not a clean 17-digit código is returned verbatim (defensive: never
/// hide a value we do not understand).
library;

String manzanaLabel(String codigo) {
  final c = codigo.trim();
  if (c.length != 17 || !RegExp(r'^\d{17}$').hasMatch(c)) return c;

  String field(int start, int end) =>
      c.substring(start, end).replaceFirst(RegExp(r'^0+'), '');

  final zona = field(5, 7);
  final sector = field(7, 9);
  final barrio = field(9, 13);
  final manzana = field(13, 17);

  return [
    if (zona.isNotEmpty) 'Z$zona',
    if (sector.isNotEmpty) 'S$sector',
    if (barrio.isNotEmpty) 'B$barrio',
    'Mz${manzana.isEmpty ? '0' : manzana}',
  ].join('·');
}
