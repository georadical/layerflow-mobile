/// Client mirror of the PINNED normalization algorithm (Spec 7,
/// specs/r1-assisted-capture.md §Normalization; canonical source:
/// backend/reconciliation/address.py). Used for typeahead filtering and the
/// OCR soft-check comparison. Any change to the pinned algorithm is a
/// contract change — this file must follow it, never lead it.
library;

/// First-token street-type map (pinned).
const _viaMap = <String, String>{
  'C': 'CALLE',
  'CL': 'CALLE',
  'CLL': 'CALLE',
  'CALLE': 'CALLE',
  'K': 'CARRERA',
  'KR': 'CARRERA',
  'CR': 'CARRERA',
  'CRA': 'CARRERA',
  'CARRERA': 'CARRERA',
  'A': 'AVENIDA',
  'AV': 'AVENIDA',
  'AVE': 'AVENIDA',
  'AVENIDA': 'AVENIDA',
  'D': 'DIAGONAL',
  'DG': 'DIAGONAL',
  'DIAG': 'DIAGONAL',
  'DIAGONAL': 'DIAGONAL',
  'T': 'TRANSVERSAL',
  'TV': 'TRANSVERSAL',
  'TRANS': 'TRANSVERSAL',
  'TRANSVERSAL': 'TRANSVERSAL',
};

/// Spanish diacritics → ASCII, standing in for NFKD → drop non-ASCII.
/// `º`/`ª` decompose to O/A under NFKD, so they map here too (this is what
/// makes the spec's own example `CL 5 Nº 2-06` come out right).
const _ascii = <String, String>{
  'Á': 'A',
  'É': 'E',
  'Í': 'I',
  'Ó': 'O',
  'Ú': 'U',
  'Ü': 'U',
  'Ñ': 'N',
  'á': 'A',
  'é': 'E',
  'í': 'I',
  'ó': 'O',
  'ú': 'U',
  'ü': 'U',
  'ñ': 'N',
  'º': 'O',
  'ª': 'A',
};

/// The canonical street type for a first token, or null if it is not one.
String? viaFor(String token) => _viaMap[token];

/// Number-marker rule (pinned v1.1, backend 8b0502d):
/// - NO | NRO | NUM → dropped ALWAYS ("Nº" folds to NO under NFKD).
/// - bare N → dropped ONLY when the next token starts with a digit: "N°"
///   (degree sign, dropped as non-ASCII) leaves a bare N to catch, but a
///   FINAL N is the cardinal suffix ("CALLE 5 N" = norte) and dropping it
///   unconditionally would merge distinct streets.
List<String> dropNumberMarkers(List<String> tokens) {
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'NO' || t == 'NRO' || t == 'NUM') continue;
    if (t == 'N' &&
        i + 1 < tokens.length &&
        tokens[i + 1].codeUnitAt(0) >= 0x30 &&
        tokens[i + 1].codeUnitAt(0) <= 0x39) {
      continue;
    }
    out.add(t);
  }
  return out;
}

/// Pinned step 1–3: NFKD→ASCII, UPPERCASE, `# - . , ; :` → space, collapse.
String cleanAddress(String raw) {
  final sb = StringBuffer();
  for (final rune in raw.runes) {
    var ch = String.fromCharCode(rune);
    ch = _ascii[ch] ?? ch;
    final code = ch.codeUnitAt(0);
    if (code > 127) continue; // NFKD → drop non-ASCII
    sb.write(ch.toUpperCase());
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[#\-.,;:]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Result of the pinned `normalize`. [direccionNorm] is null when the text
/// is not a street address (rural name) — exactly the population the
/// typeahead must NOT pretend to cover.
class NormalizedAddress {
  const NormalizedAddress({
    this.direccionNorm,
    this.barrio,
    this.interior = false,
    this.lote,
    this.mz,
  });

  final String? direccionNorm;
  final String? barrio;
  final bool interior;
  final String? lote;
  final String? mz;
}

/// Pinned `normalize(raw)`.
NormalizedAddress normalizeAddress(String raw) {
  final s = cleanAddress(raw);
  if (s.isEmpty) return const NormalizedAddress();
  final tokens = s.split(' ');

  final via = _viaMap[tokens.first];
  if (via == null) return const NormalizedAddress(); // rural name

  // a. Structural suffixes, extractable from any position.
  var interior = false;
  String? lote;
  String? mz;
  final rest = <String>[];
  for (var i = 1; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'IN' || t == 'INT' || t == 'INTERIOR') {
      interior = true;
    } else if ((t == 'LO' || t == 'LOTE' || t == 'LT') &&
        i + 1 < tokens.length) {
      lote = tokens[++i];
    } else if ((t == 'MZ' || t == 'MZA' || t == 'MANZANA') &&
        i + 1 < tokens.length) {
      mz = tokens[++i];
    } else {
      rest.add(t);
    }
  }

  // b. Trailing pure-alpha tokens → barrio (in reading order).
  final barrioTokens = <String>[];
  while (rest.isNotEmpty && RegExp(r'^[A-Z]+$').hasMatch(rest.last)) {
    barrioTokens.insert(0, rest.removeLast());
  }
  final barrio = barrioTokens.isEmpty ? null : barrioTokens.join(' ');

  // c. Positional core, ignoring number markers (pinned v1.1 rule).
  final core = dropNumberMarkers(rest);

  String? direccionNorm;
  if (core.length >= 3) {
    direccionNorm = '$via ${core[0]} # ${core[1]}-${core[2]}';
  }
  return NormalizedAddress(
    direccionNorm: direccionNorm,
    barrio: barrio,
    interior: interior,
    lote: lote,
    mz: mz,
  );
}

/// Pinned v1.2 (CL-R1, backend a52883d): whether the RAW typed text
/// matches the linked normalized address — fully, or by its cruce-placa
/// part. Colombian door plates usually show ONLY that part ("3A-08"), so
/// typing it is literally what the door says: coincidente, rutina, no
/// confirmation dialog.
bool typedMatchesLinked(String typed, String linkedNorm) {
  final full = normalizeAddress(typed).direccionNorm;
  if (full != null && full == linkedNorm) return true;
  final hash = linkedNorm.indexOf('# ');
  if (hash < 0) return false;
  final part = linkedNorm.substring(hash + 2); // "3A-08"
  final cleanedTyped = cleanAddress(typed);
  return cleanedTyped.isNotEmpty && cleanedTyped == cleanAddress(part);
}

/// Levenshtein distance for the OCR soft-check (CL-R2): edit distance over
/// the two CLEANED strings; similarity below the caller's threshold →
/// "¿confirmas?".
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = [
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = List.of(curr);
  }
  return prev[b.length];
}
