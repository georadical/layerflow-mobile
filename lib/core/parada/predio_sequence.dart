import '../../data/db/database.dart' show Capture;

/// What to DISPLAY as a capture's per-parada number (Spec 11).
///
/// Three states, mirroring the backend contract:
/// - [definitive]: the server assigned `secuencia_parada` (authoritative, frozen).
/// - [provisional]: pre-sync local count — the capture's 1-based rank among its
///   parada's captures, in capture order. Marked in the UI; replaced by the
///   server value on sync (it ignores gaps, which it cannot know yet).
/// - [legacy]: no `stop_id` → there is no per-parada number ("predio —").
class PredioDisplay {
  const PredioDisplay.definitive(this.number)
      : provisional = false,
        legacy = false;
  const PredioDisplay.provisional(this.number)
      : provisional = true,
        legacy = false;
  const PredioDisplay.legacy()
      : number = 0,
        provisional = false,
        legacy = true;

  /// The per-parada ordinal (meaningless when [legacy]).
  final int number;

  /// Pre-sync local count (vs the server's frozen value).
  final bool provisional;

  /// No parada binding → no number at all.
  final bool legacy;
}

/// The [PredioDisplay] for [capture], given every capture of the route
/// ([routeCaptures]) so a pre-sync rank can be computed within the parada.
///
/// Spec 11, BR9/BR10: the provisional ordinal is derived, never stored — it is
/// the capture's position among its parada's captures ordered by `posicion`
/// (append-only capture order), restarting at 1 per parada. A capture that
/// already carries the server's `secuencia_parada` shows that verbatim.
PredioDisplay predioDisplayFor(Capture capture, List<Capture> routeCaptures) {
  final stopId = capture.stopId;
  if (stopId == null) return const PredioDisplay.legacy();

  final secuencia = capture.secuenciaParada;
  if (secuencia != null) return PredioDisplay.definitive(secuencia);

  // Provisional: 1-based rank among this parada's captures, in capture order.
  final onStop = routeCaptures.where((c) => c.stopId == stopId).toList()
    ..sort((a, b) => a.posicion.compareTo(b.posicion));
  final rank = onStop.indexWhere((c) => c.clientId == capture.clientId) + 1;
  return PredioDisplay.provisional(rank < 1 ? 1 : rank);
}

/// The plain-text label for a [PredioDisplay] — for titles and other places that
/// do not carry the colored [PredioDisplay] styling. [faceSequence] prefixes
/// "Parada N · " when known. The provisional tilde is kept (it is informative in
/// plain text too); the color/weight is not.
String predioPlainLabel(PredioDisplay display, {int? faceSequence}) {
  final prefix = faceSequence == null ? '' : 'Parada $faceSequence · ';
  if (display.legacy) return '${prefix}predio —';
  if (display.provisional) return '${prefix}predio ~${display.number}';
  return '${prefix}predio ${display.number}';
}
