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
