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
  test('empty token → empty, not malformed', () {
    final info = parseJwt('');
    expect(info.isMalformed, isFalse);
    expect(info.expiresAt, isNull);
    expect(info.isExpired, isFalse);
  });

  test('string without 3 segments → malformed', () {
    expect(parseJwt('no-es-un-jwt').isMalformed, isTrue);
  });

  test('exp in the future → not expired', () {
    final info =
        parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: 10))}));
    expect(info.isMalformed, isFalse);
    expect(info.isExpired, isFalse);
    expect(info.expiresAt, isNotNull);
    expect(info.daysLeft, greaterThanOrEqualTo(9));
  });

  test('exp in the past → expired', () {
    final info =
        parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: -1))}));
    expect(info.isExpired, isTrue);
  });

  test('exp within 1 day → expiresSoon', () {
    final info = parseJwt(_fakeJwt({'exp': _epochIn(const Duration(days: 1))}));
    expect(info.isExpired, isFalse);
    expect(info.expiresSoon(), isTrue);
  });

  test('JWT without exp claim → no date, not malformed', () {
    final info = parseJwt(_fakeJwt({'sub': 'worker-1'}));
    expect(info.isMalformed, isFalse);
    expect(info.expiresAt, isNull);
  });
}
