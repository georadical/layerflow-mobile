import 'dart:convert';

/// Utilidades para leer, sin verificar la firma, los claims de un JWT.
///
/// Uso exclusivo: mostrar/avisar la expiración del `field_token` pegado en
/// Ajustes. NO valida el token (eso lo hace el backend); solo lee `exp` para UX.
class JwtInfo {
  const JwtInfo({this.expiresAt, this.isMalformed = false});

  /// Momento de expiración (claim `exp`), o null si no lo trae.
  final DateTime? expiresAt;

  /// El string no tiene forma de JWT decodificable.
  final bool isMalformed;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Días restantes (redondeados hacia abajo), o null si no hay `exp`.
  int? get daysLeft {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  /// Vence pronto (dentro de [thresholdDays]) y aún no ha vencido.
  bool expiresSoon({int thresholdDays = 3}) {
    if (expiresAt == null || isExpired) return false;
    return expiresAt!.difference(DateTime.now()).inDays < thresholdDays;
  }

  static const empty = JwtInfo();
}

/// Decodifica los claims públicos de un JWT para leer `exp`. Tolerante a
/// errores: devuelve [JwtInfo.empty] si el string está vacío, o un JwtInfo con
/// `isMalformed=true` si parece un token pero no se puede decodificar.
JwtInfo parseJwt(String? token) {
  if (token == null || token.trim().isEmpty) return JwtInfo.empty;
  final t = token.trim();
  final parts = t.split('.');
  if (parts.length != 3) return const JwtInfo(isMalformed: true);
  try {
    final payload = _decodeSegment(parts[1]);
    final map = jsonDecode(payload) as Map<String, dynamic>;
    final exp = map['exp'];
    if (exp is num) {
      return JwtInfo(
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000).toLocal(),
      );
    }
    // JWT válido pero sin exp: no es malformado, solo no expira "conocidamente".
    return JwtInfo.empty;
  } catch (_) {
    return const JwtInfo(isMalformed: true);
  }
}

String _decodeSegment(String segment) {
  final normalized = base64Url.normalize(segment);
  return utf8.decode(base64Url.decode(normalized));
}
