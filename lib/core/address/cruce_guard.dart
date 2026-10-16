/// App-only UX heuristic (Spec 12 amendment BR-C4) — NOT part of the pinned
/// normalization, which lives in `address_normalizer.dart` and mirrors the
/// backend. Never feeds a request, a stored field or a prediction: it only
/// decides whether to ask "¿Te falta CON?" before saving a lot.
library;

import 'address_normalizer.dart';

/// Whether [raw] looks like a street corner written WITHOUT the `CON`
/// sentinel (`CALLE 13 CARRERA 3`). The pinned normalizer reads that form as
/// a door address on a fake face, which corrupts the parada's sweep.
///
/// Two or more street WORDS and no `CON`. Single-letter via abbreviations
/// (`A`, `C`, `D`, `K`, `T`) are ignored: a standalone letter is usually a
/// placa/via suffix (`CALLE 13 A 3 20`), and the guard must not cry wolf there.
bool looksLikeCruceMissingCon(String raw) {
  final tokens = cleanAddress(raw).split(' ');
  if (tokens.contains('CON')) return false;
  final streetWords =
      tokens.where((t) => t.length > 1 && viaFor(t) != null).length;
  return streetWords >= 2;
}
