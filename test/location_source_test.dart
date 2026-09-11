import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/location/location_source.dart';

void main() {
  group('NullLocationSource (MVP coordinate-free)', () {
    test('is never available', () {
      expect(const NullLocationSource().isAvailable, isFalse);
    });

    test('currentFix always returns null', () async {
      expect(await const NullLocationSource().currentFix(), isNull);
    });
  });
}
