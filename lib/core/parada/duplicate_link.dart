import '../../data/db/database.dart' show Capture;
import 'predio_sequence.dart';

/// R1-assisted capture amendment (2026-10-22), DR1: another capture of the route
/// holding the SAME R1 link — the same [npn], or, for a placa-level link (npn
/// null, Spec 15 v4), the same [direccionNorm] with npn null. The capture being
/// edited ([excludeClientId]) never counts. Null when there is none (or no link).
///
/// Local only (DR6): [routeCaptures] is what the phone holds for the route,
/// pending or synced; other routes/devices are the office's alert.
Capture? duplicateLinkOf({
  required List<Capture> routeCaptures,
  String? npn,
  String? direccionNorm,
  String? excludeClientId,
}) {
  if (npn == null && direccionNorm == null) return null;
  for (final c in routeCaptures) {
    if (c.clientId == excludeClientId) continue;
    final same = npn != null
        ? c.npn == npn
        : c.npn == null && c.direccionNorm == direccionNorm;
    if (same) return c;
  }
  return null;
}

/// DR2: the located warning for a duplicate held by [other] — "la parada N ·
/// predio M" (the predio number as the lists show it, provisional tilde
/// included), or "otro predio de esta ruta" when [other] has no parada.
/// [faceSequence] is [other]'s parada number, when known.
String duplicateLinkMessage(
  Capture other,
  List<Capture> routeCaptures, {
  int? faceSequence,
}) {
  final display = predioDisplayFor(other, routeCaptures);
  final where = (faceSequence == null || display.legacy)
      ? 'otro predio de esta ruta'
      : 'la parada $faceSequence · ${predioPlainLabel(display)}';
  return 'Esa placa de R1 ya está enlazada en $where. '
      'Revisa que sea otra puerta.';
}
