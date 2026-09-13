import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Camera-per-capture for the plate photo (Spec 7, CL-R3): the capture
/// screen opens it while the form is alive and grabs one frame on save —
/// no extra gesture, no permanent viewfinder across the walk.
///
/// DEGRADES, NEVER BLOCKS: a denied permission, a broken camera or a failed
/// shot only means "sin foto" — capture always proceeds (offline-first law).
class PlateCamera {
  CameraController? _controller;

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Initializes the back camera. Returns true when a preview is available;
  /// false on denial/no camera/any failure (the screen shows "sin foto").
  Future<bool> start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // 1280x720: already at the contract's scale; keeps shots fast and
        // compression cheap on low-end field phones.
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      return true;
    } catch (_) {
      _controller = null;
      return false;
    }
  }

  /// Grabs one frame, compresses it to the contract limits (JPEG, longest
  /// side <=1600px, <=500KB) and stores it under the app's documents dir as
  /// evidence/<clientId>.jpg. Returns the file path, or null on any failure.
  Future<String?> captureFor(String clientId) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final shot = await controller.takePicture();
      final raw = await File(shot.path).readAsBytes();
      // Compression is CPU-bound (~1s): run it off the UI thread.
      final jpeg = await Isolate.run(() => compressPlateJpeg(raw));
      if (jpeg == null) return null;

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/evidence');
      await dir.create(recursive: true);
      final out = File('${dir.path}/$clientId.jpg');
      await out.writeAsBytes(jpeg, flush: true);
      // The camera's temp shot is no longer needed.
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return out.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
  }
}

/// Pure function (isolate-friendly): decode → cap longest side at 1600px →
/// re-encode JPEG, stepping quality down until it fits the 500KB cap
/// (server answers 413 above it). Null when the bytes cannot be decoded.
Uint8List? compressPlateJpeg(Uint8List raw, {int maxBytes = 500 * 1024}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    // The decoder throws on some malformed inputs instead of returning
    // null; either way the answer is "sin foto", never a crash.
    return null;
  }
  if (decoded == null) return null;

  var image = decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > 1600) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1600)
        : img.copyResize(image, height: 1600);
  }

  for (final quality in [70, 60, 50, 40, 30]) {
    final out = img.encodeJpg(image, quality: quality);
    if (out.length <= maxBytes) return out;
  }
  // Still too big at q30 (pathological): shrink once more and finish.
  final smaller = img.copyResize(image, width: image.width ~/ 2);
  final out = img.encodeJpg(smaller, quality: 50);
  return out.length <= maxBytes ? out : null;
}
