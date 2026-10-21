import '../../data/db/database.dart';
import '../address/address_normalizer.dart';
import 'face_prediction.dart';

/// Spec 19: the face terna a bare distance is composed with — the parada's own
/// terna, or the anchor's face in force when the capture was made (BR3; resolved
/// by the caller). The cardinal is the face's zone suffix (address-profiles).
class AddressPrefix {
  const AddressPrefix({
    required this.tipoVia,
    required this.numVia,
    required this.numCruce,
    this.cardinal,
    this.cardinalPosicion,
  });

  final String tipoVia;
  final String numVia;
  final String numCruce;
  final String? cardinal;
  final String? cardinalPosicion;
}

/// Spec 19 BR1: the stored text's first word is a via type (the pinned
/// normalizer's list, which mirrors the backend's `address.py`) — so it is a full
/// address or a cruce, never a bare distance. Case- and accent-insensitive.
bool startsWithVia(String text) {
  final cleaned = cleanAddress(text);
  if (cleaned.isEmpty) return false;
  return viaFor(cleaned.split(' ').first) != null;
}

/// Spec 19: the text a list shows for a stored placa.
///
/// - A full address or a cruce (BR1/BR5) is shown as stored.
/// - A bare distance (BR2/BR10, `28`, `28A`, `28 BIS`) is composed with
///   [prefix] as «vía principal # vía generadora-distancia».
/// - No [prefix] (BR4/BR7) → shown as stored.
///
/// Null when nothing is stored: each screen keeps its own empty states
/// ("Sin placa a la vista", "Lote", "Sin dirección aún" — BR6). Display only:
/// the stored placa and the pushed payload never change (BR9).
String? displayPlaca(String? stored, {AddressPrefix? prefix}) {
  final s = stored?.trim();
  if (s == null || s.isEmpty) return null;
  if (prefix == null || startsWithVia(s)) return s;
  return composeParadaAddress(
    tipoVia: prefix.tipoVia,
    numVia: prefix.numVia,
    numCruce: prefix.numCruce,
    cardinal: prefix.cardinal,
    cardinalPosicion: prefix.cardinalPosicion,
    distance: s,
  );
}

/// Spec 19 BR3 (AD.3): the prefix each capture of ONE parada is shown with,
/// keyed by `clientId`. A capture with no entry has no prefix (BR4).
///
/// 1. The parada carries its terna → every capture uses it.
/// 2. Otherwise → the anchor's face IN FORCE when the capture was made, i.e.
///    what the live preview showed the surveyor (AM.8): among the captures
///    BEFORE it, the last R1-linked one (npn or direccion_norm), else the last
///    one; its face comes from its R1 row ([r1FaceOf]), else from parsing its
///    own placa (a hallazgo anchor). Mirrors `paradaCaptureContextProvider`.
///    The parada's first capture has no earlier anchor → no prefix (it is the
///    full-placa anchor itself).
///
/// [onStop] is the parada's captures in capture order. [r1FaceOf] resolves a
/// linked capture's R1 face (null when the row is not in the local directory);
/// pass null to skip the anchor path (no manzana / no tenant: nothing to
/// predict, so the surveyor never saw a composed preview).
Future<Map<String, AddressPrefix>> prefixesForParada({
  required List<Capture> onStop,
  String? tipoVia,
  String? numVia,
  String? numCruce,
  String? cardinal,
  String? cardinalPosicion,
  Future<FaceAddress?> Function(Capture linked)? r1FaceOf,
}) async {
  final out = <String, AddressPrefix>{};
  if (tipoVia != null && numVia != null && numCruce != null) {
    final p = AddressPrefix(
      tipoVia: tipoVia,
      numVia: numVia,
      numCruce: numCruce,
      cardinal: cardinal,
      cardinalPosicion: cardinalPosicion,
    );
    for (final c in onStop) {
      out[c.clientId] = p;
    }
    return out;
  }
  if (r1FaceOf == null) return out;

  bool linked(Capture c) => c.npn != null || c.direccionNorm != null;
  final faceCache = <String, FaceAddress?>{};
  Future<FaceAddress?> faceOf(Capture anchor) async {
    if (faceCache.containsKey(anchor.clientId)) {
      return faceCache[anchor.clientId];
    }
    FaceAddress? face = linked(anchor) ? await r1FaceOf(anchor) : null;
    final placa = anchor.placa;
    if (face == null && placa != null) {
      final norm = normalizeAddress(placa).direccionNorm;
      face = norm == null ? null : parseFaceAddress(norm);
    }
    return faceCache[anchor.clientId] = face;
  }

  for (var i = 1; i < onStop.length; i++) {
    final prior = onStop.sublist(0, i);
    final anchor = prior.lastWhere(linked, orElse: () => prior.last);
    final face = await faceOf(anchor);
    if (face == null) continue;
    out[onStop[i].clientId] = AddressPrefix(
      tipoVia: face.via,
      numVia: face.numVia,
      numCruce: face.numCruce,
      cardinal: cardinal,
      cardinalPosicion: cardinalPosicion,
    );
  }
  return out;
}
