import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/camera/plate_camera.dart';

/// Deliberate, aimed plate shot (CL-R3 v1.1): full-screen preview,
/// pinch-to-zoom (rejas: the plate may be out of reach behind a fence),
/// one shutter tap. Pops the taken [XFile], or null if the worker backs
/// out — the caller decides what backing out means (a required shot
/// aborts the save; an optional CTA just returns).
class PlateShotScreen extends StatefulWidget {
  const PlateShotScreen({
    super.key,
    required this.camera,
    this.required = false,
  });

  /// The already-started camera of the capture form (shared instance —
  /// one controller, no re-initialization cost).
  final PlateCamera camera;

  /// Required shots explain themselves in the header.
  final bool required;

  @override
  State<PlateShotScreen> createState() => _PlateShotScreenState();
}

class _PlateShotScreenState extends State<PlateShotScreen> {
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _zoomAtScaleStart = 1;
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    final controller = widget.camera.controller;
    if (controller != null) {
      Future.wait([
        controller.getMinZoomLevel(),
        controller.getMaxZoomLevel(),
      ]).then((limits) {
        if (mounted) {
          setState(() {
            _minZoom = limits[0];
            _maxZoom = limits[1];
          });
        }
      }).catchError((_) {});
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = widget.camera.controller;
    if (controller == null) return;
    final clamped = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = clamped);
    try {
      await controller.setZoomLevel(clamped);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    if (_shooting) return;
    setState(() => _shooting = true);
    var shot = await widget.camera.takeShot();
    if (shot == null) {
      // Opening this screen re-configures the capture session; a shot
      // fired right after can lose that race. One breath, one retry.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      shot = await widget.camera.takeShot();
    }
    if (!mounted) return;
    // Still null = a real hardware hiccup: report it and let the caller's
    // valve rules decide — never trap the worker here.
    Navigator.of(context).pop(shot);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.camera.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.required
            ? 'Foto de la placa (requerida)'
            : 'Foto de la placa'),
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(
              child: Text('Cámara no disponible',
                  style: TextStyle(color: Colors.white)),
            )
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onScaleStart: (_) => _zoomAtScaleStart = _zoom,
                    onScaleUpdate: (d) => _setZoom(_zoomAtScaleStart * d.scale),
                    child: Center(child: CameraPreview(controller)),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          _maxZoom > 1
                              ? 'Encuadra la placa · pellizca para acercar '
                                  '(${_zoom.toStringAsFixed(1)}x)'
                              : 'Encuadra la placa',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton.large(
                          onPressed: _shooting ? null : _shoot,
                          child: _shooting
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.photo_camera),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
