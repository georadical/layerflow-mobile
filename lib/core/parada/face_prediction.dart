/// Local expected-placa prediction (Spec 10, specs/parada-capture-app.md
/// Decision 2) — a CLIENT MIRROR of the backend's pinned algorithm
/// (parada-scoped-capture.md PS5–PS7). Pure domain: no network, no Flutter.
///
/// Why local: the prediction must be near-instant and work offline, so the
/// app must not wait on `expected-placa`. The server endpoint stays the
/// authority; this mirrors its rule, the way `address_normalizer` mirrors the
/// normalization. Any change to the pinned algorithm is a contract change this
/// file must follow, never lead.
///
/// The rule, in one breath: within a manzana, a **face** is the set of R1
/// addresses that share `(via, num_via, num_cruce, parity)` — parity
/// (`placa mod 2`) is what separates the two aceras of the same vía+cruce.
/// Order the face by placa NUMERICALLY; the next expected placa is simply the
/// next entry from the anchor in the inferred direction (min→ascending,
/// max→descending, middle→"no inicia la cara"). Never arithmetic: irregular
/// gaps (04→08→16) are just the next in the ordered list.
library;

/// Direction of the sweep along a face.
enum FaceDirection {
  ascendente('ascendente'),
  descendente('descendente'),

  /// The anchor is not an endpoint yet — direction cannot be resolved.
  indeterminada('indeterminada');

  const FaceDirection(this.wire);

  final String wire;

  static FaceDirection? fromWire(String? w) {
    for (final d in values) {
      if (d.wire == w) return d;
    }
    return null;
  }
}

/// The face components parsed out of a normalized address
/// "VIA numVia # numCruce-placa" (the format `address_normalizer` produces).
class FaceAddress {
  const FaceAddress({
    required this.direccionNorm,
    required this.via,
    required this.numVia,
    required this.numCruce,
    required this.placa,
    required this.placaNum,
  });

  final String direccionNorm;
  final String via;
  final String numVia;
  final String numCruce;

  /// The placa as text (e.g. "06").
  final String placa;

  /// The placa's leading integer, for ordering and parity.
  final int placaNum;

  int get parity => placaNum % 2;

  /// The face key WITHIN a manzana: same vía, same generadora (num_cruce),
  /// same acera (parity).
  String get faceKey => '$via|$numVia|$numCruce|$parity';

  /// Builds a face address from the server's PARSED R1 columns (Spec 10),
  /// which is the preferred path: [numVia] is used verbatim ("10AS"), never
  /// re-derived, so a suffix vía is never mis-grouped. Returns null when a
  /// component is missing/empty or the placa has no leading integer (then the
  /// row cannot be ordered and is skipped for prediction). The caller should
  /// pass only rows the server marked `parse_ok`.
  static FaceAddress? fromColumns({
    required String direccionNorm,
    required String? tipoVia,
    required String? numVia,
    required String? numCruce,
    required String? placa,
  }) {
    final via = tipoVia?.trim() ?? '';
    final nv = numVia?.trim() ?? '';
    final nc = numCruce?.trim() ?? '';
    final pl = placa?.trim() ?? '';
    if (via.isEmpty || nv.isEmpty || nc.isEmpty || pl.isEmpty) return null;
    final digits = RegExp(r'^\d+').firstMatch(pl)?.group(0);
    if (digits == null) return null;
    return FaceAddress(
      direccionNorm: direccionNorm,
      via: via,
      numVia: nv,
      numCruce: nc,
      placa: pl,
      placaNum: int.parse(digits),
    );
  }
}

/// Composes the full address the backend builds on read (Spec 10): the face's
/// terna + the typed/stored distance + the cardinal zone suffix in its place
/// ('via' after num_via, 'placa' at the end). Returns [distance] unchanged when
/// the terna is absent — a rural/classic capture's stored text IS the address
/// (a topónimo), with nothing to prepend. Pure: the app's display mirror of the
/// server composition, used by both the live preview and the resume list so
/// they never diverge.
String composeParadaAddress({
  required String? tipoVia,
  required String? numVia,
  required String? numCruce,
  String? cardinal,
  String? cardinalPosicion,
  required String distance,
}) {
  if (tipoVia == null || numVia == null || numCruce == null) return distance;
  final viaCardinal =
      cardinal != null && cardinalPosicion == 'via' ? ' $cardinal' : '';
  final placaCardinal =
      cardinal != null && cardinalPosicion == 'placa' ? ' $cardinal' : '';
  return '$tipoVia $numVia$viaCardinal # $numCruce-$distance$placaCardinal';
}

/// Parses a normalized address into its face components, or null when it is
/// not a structured "VIA n # c-p" address (rural / unparseable → no
/// prediction, the unassisted flow).
FaceAddress? parseFaceAddress(String direccionNorm) {
  final s = direccionNorm.trim();
  final hash = s.indexOf(' # ');
  if (hash < 0) return null;
  final left = s.substring(0, hash).trim(); // "CALLE 5"
  final right = s.substring(hash + 3).trim(); // "2-06"

  final lastSpace = left.lastIndexOf(' ');
  if (lastSpace < 0) return null;
  final via = left.substring(0, lastSpace).trim();
  final numVia = left.substring(lastSpace + 1).trim();
  if (via.isEmpty || numVia.isEmpty) return null;

  final dash = right.indexOf('-');
  if (dash < 0) return null;
  final numCruce = right.substring(0, dash).trim();
  final placa = right.substring(dash + 1).trim();
  if (numCruce.isEmpty || placa.isEmpty) return null;

  // Leading integer of the placa (handles "06", "8B"); none → not orderable.
  final digits = RegExp(r'^\d+').firstMatch(placa)?.group(0);
  if (digits == null) return null;

  return FaceAddress(
    direccionNorm: s,
    via: via,
    numVia: numVia,
    numCruce: numCruce,
    placa: placa,
    placaNum: int.parse(digits),
  );
}

/// The prediction result: the next expected R1 address (null = end of face),
/// the direction (resolved or not), and a warning when the anchor did not
/// start the face.
class FacePrediction {
  const FacePrediction({
    this.expectedDireccion,
    required this.direction,
    this.warning,
  });

  final String? expectedDireccion;
  final FaceDirection direction;
  final String? warning;

  bool get endOfFace =>
      expectedDireccion == null && direction != FaceDirection.indeterminada;
}

/// Predicts the next placa for the anchor's face (client mirror of PS5–PS7),
/// parsing the addresses out of `direccion_norm`. Prefer
/// [predictNextFromFaces] with the server-parsed columns — this string path is
/// the fallback for rows without parsed columns (and what the unit tests
/// exercise).
///
/// [anchorDireccionNorm] is the last captured/linked R1 address (normalized).
/// [manzanaR1] are the normalized R1 addresses of the parada's manzana.
/// [direction] is the direction stored from a previous call — pass it so the
/// sweep does not re-flip at the face end; omit it on the first prediction and
/// it is inferred.
FacePrediction predictNext({
  required String anchorDireccionNorm,
  required List<String> manzanaR1,
  FaceDirection? direction,
}) {
  final anchor = parseFaceAddress(anchorDireccionNorm);
  if (anchor == null) {
    // The anchor is not a structured address (rural / a free finding): the
    // sweep cannot be anchored — fall back to unassisted capture.
    return const FacePrediction(direction: FaceDirection.indeterminada);
  }
  final faces =
      manzanaR1.map(parseFaceAddress).whereType<FaceAddress>().toList();
  return predictNextFromFaces(
    anchor: anchor,
    manzanaFaces: faces,
    direction: direction,
  );
}

/// Predicts the next placa for the anchor's face from already-parsed
/// [FaceAddress]es — the production path, fed by [FaceAddress.fromColumns] over
/// the server-parsed R1 columns so a suffix vía ("10AS") is grouped as sent.
///
/// [manzanaFaces] are every R1 address of the parada's manzana (all faces —
/// this filters to the anchor's face by key). [direction], when carried from a
/// previous call, is respected so the sweep does not re-flip at the face end.
FacePrediction predictNextFromFaces({
  required FaceAddress anchor,
  required List<FaceAddress> manzanaFaces,
  FaceDirection? direction,
}) {
  // The face list: same face key, ordered by placa numerically, deduped by
  // placaNum (one door per number).
  final byPlaca = <int, FaceAddress>{};
  for (final fa in manzanaFaces) {
    if (fa.faceKey != anchor.faceKey) continue;
    byPlaca.putIfAbsent(fa.placaNum, () => fa);
  }
  byPlaca.putIfAbsent(anchor.placaNum, () => anchor); // the anchor belongs too
  final face = byPlaca.values.toList()
    ..sort((a, b) => a.placaNum.compareTo(b.placaNum));

  final idx = face.indexWhere((f) => f.placaNum == anchor.placaNum);

  // Resolve direction: keep the stored one, else infer from the anchor's
  // position (endpoint → asc/desc; middle → unresolved + warning).
  var dir = direction ?? FaceDirection.indeterminada;
  String? warning;
  if (direction == null || direction == FaceDirection.indeterminada) {
    if (face.length <= 1) {
      dir = FaceDirection.ascendente; // lone placa: nothing after it anyway
    } else if (idx == 0) {
      dir = FaceDirection.ascendente;
    } else if (idx == face.length - 1) {
      dir = FaceDirection.descendente;
    } else {
      dir = FaceDirection.indeterminada;
      warning = 'esta placa no inicia la cara';
    }
  }

  if (dir == FaceDirection.indeterminada) {
    return FacePrediction(direction: dir, warning: warning);
  }

  final nextIdx = dir == FaceDirection.ascendente ? idx + 1 : idx - 1;
  final next = (nextIdx >= 0 && nextIdx < face.length) ? face[nextIdx] : null;
  return FacePrediction(
    expectedDireccion: next?.direccionNorm,
    direction: dir,
  );
}
