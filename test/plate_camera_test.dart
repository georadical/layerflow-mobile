import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:layerflow_capture/core/camera/plate_camera.dart';

void main() {
  test('compressPlateJpeg fits the pinned contract: <=1600px and <=500KB', () {
    // A busy 3000x2000 synthetic shot (gradients compress worse than flat).
    final big = img.Image(width: 3000, height: 2000);
    for (var y = 0; y < big.height; y += 4) {
      for (var x = 0; x < big.width; x += 4) {
        big.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final raw = img.encodePng(big);

    final out = compressPlateJpeg(raw);

    expect(out, isNotNull);
    expect(out!.length, lessThanOrEqualTo(500 * 1024),
        reason: 'above the cap the server answers 413');
    final decoded = img.decodeImage(out)!;
    expect(decoded.width <= 1600 && decoded.height <= 1600, isTrue);
    // Aspect ratio survives the resize.
    expect((decoded.width / decoded.height - 1.5).abs(), lessThan(0.01));
  });

  test('undecodable bytes yield null, never a crash (sin foto)', () {
    expect(compressPlateJpeg(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
