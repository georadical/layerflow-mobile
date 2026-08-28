import 'dart:convert';

/// Utilities to read a JWT's claims without verifying the signature.
///
/// Sole use: show/warn about the expiry of the `field_token` pasted in
/// Settings. It does NOT validate the token (the backend does that); it only
/// reads `exp` for UX.
class JwtInfo {
  const JwtInfo({this.expiresAt, this.isMalformed = false});

  /// Expiry instant (`exp` claim), or null if it is not present.
  final DateTime? expiresAt;

  /// The string does not have the shape of a decodable JWT.
  final bool isMalformed;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Days remaining (rounded down), or null if there is no `exp`.
  int? get daysLeft {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  /// Expires soon (within [thresholdDays]) and has not expired yet.
  bool expiresSoon({int thresholdDays = 3}) {
    if (expiresAt == null || isExpired) return false;
    return expiresAt!.difference(DateTime.now()).inDays < thresholdDays;
  }

  static const empty = JwtInfo();
}

/// Decodes a JWT's public claims to read `exp`. Error tolerant: returns
/// [JwtInfo.empty] if the string is empty, or a JwtInfo with
/// `isMalformed=true` if it looks like a token but cannot be decoded.
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
    // Valid JWT without exp: not malformed, it just has no known expiry.
    return JwtInfo.empty;
  } catch (_) {
    return const JwtInfo(isMalformed: true);
  }
}

String _decodeSegment(String segment) {
  final normalized = base64Url.normalize(segment);
  return utf8.decode(base64Url.decode(normalized));
}
