import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/location/location_source.dart';

void main() {
  group('NullLocationSource (MVP coordinate-free)', () {
    test('nunca está disponible', () {
      expect(const NullLocationSource().isAvailable, isFalse);
    });

    test('currentFix siempre devuelve null', () async {
      expect(await const NullLocationSource().currentFix(), isNull);
    });
  });
}
