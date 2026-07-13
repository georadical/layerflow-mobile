import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/jwt.dart';

String _seg(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _fakeJwt(Map<String, dynamic> payload) =>
    '${_seg({'alg': 'HS256'})}.${_seg(payload)}.signature';

int _epochIn(Duration d) =>
    DateTime.now().add(d).millisecondsSinceEpoch ~/ 1000;

void main() {
  test('token vacío → empty, no malformado', () {
    final info = parseJwt('');
    expect(info.isMalformed, isFalse);
    expect(info.expiresAt, isNull);
    expect(info.isExpired, isFalse);
  });

  test('string sin 3 segmentos → malformado', () {
    expect(parseJwt('no-es-un-jwt').isMalformed, isTrue);
  });

  test('exp futuro → no vencido', () {
    final info = parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: 10))}));
    expect(info.isMalformed, isFalse);
    expect(info.isExpired, isFalse);
    expect(info.expiresAt, isNotNull);
    expect(info.daysLeft, greaterThanOrEqualTo(9));
  });

  test('exp pasado → vencido', () {
    final info = parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: -1))}));
    expect(info.isExpired, isTrue);
  });

  test('exp dentro de 1 día → expiresSoon', () {
    final info = parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: 1))}));
    expect(info.isExpired, isFalse);
    expect(info.expiresSoon(), isTrue);
  });

  test('JWT sin claim exp → sin fecha, no malformado', () {
    final info = parseJwt(_fakeJwt({'sub': 'worker-1'}));
    expect(info.isMalformed, isFalse);
    expect(info.expiresAt, isNull);
  });
}
