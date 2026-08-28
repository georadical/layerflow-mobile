import 'package:flutter/material.dart';

import 'ui/theme.dart';
import 'ui/wireframes/resume_route_wireframe.dart';

/// Wireframe gallery — separate entry point, does not touch the real app.
///
///   flutter run -t lib/wireframes_main.dart
///
/// Each wireframe renders with dummy data so the layout can be reviewed
/// (and approved) before any styling or backend wiring happens.
void main() => runApp(const WireframeApp());

class WireframeApp extends StatelessWidget {
  const WireframeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerFlow — Wireframes',
      debugShowCheckedModeBanner: false,
      // Same theme as the real app, so the design pass reviews what ships.
      theme: buildAppTheme(),
      home: const WireframeGallery(),
    );
  }
}

class WireframeGallery extends StatefulWidget {
  const WireframeGallery({super.key});

  @override
  State<WireframeGallery> createState() => _WireframeGalleryState();
}

class _WireframeGalleryState extends State<WireframeGallery> {
  ResumeState _state = ResumeState.list;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // State switcher, so every UI state the spec requires is reviewable.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final s in ResumeState.values)
                  TextButton(
                    onPressed: () => setState(() => _state = s),
                    child: Text(
                      s.name,
                      style: TextStyle(
                        decoration:
                            _state == s ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ResumeRouteWireframe(
            state: _state,
            units: wireframeDummyUnits,
          ),
        ),
      ],
    );
  }
}
