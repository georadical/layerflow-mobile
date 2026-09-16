import 'package:flutter/material.dart';

import 'ui/theme.dart';
import 'ui/wireframes/assisted_capture_wireframe.dart';
import 'ui/wireframes/login_wireframe.dart';
import 'ui/wireframes/resume_route_wireframe.dart';
import 'ui/wireframes/route_selector_wireframe.dart';
import 'ui/wireframes/survey_rail_wireframe.dart';

/// Wireframe gallery — separate entry point, does not touch the real app.
///
///   flutter run -t lib/wireframes_main.dart
///
/// Each screen renders with dummy data and a state switcher, so every UI state
/// the spec demands can be reviewed (and approved) before it is wired up.
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
      home: const WireframeIndex(),
    );
  }
}

class WireframeIndex extends StatelessWidget {
  const WireframeIndex({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wireframes')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Selector de ruta'),
            subtitle: const Text('Spec 1 · T1.1'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SelectorHost()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Vista de reanudar'),
            subtitle: const Text('Spec 1 · T1.3'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _ResumeHost()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Login de encuestador'),
            subtitle: const Text('Spec 5 · T5.2'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _LoginHost()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Captura asistida (R1)'),
            subtitle: const Text('Spec 7 · T7.2'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AssistHost()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Encuesta extendida (rail)'),
            subtitle: const Text('Spec 8 · T8.2'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SurveyHost()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurveyHost extends StatefulWidget {
  const _SurveyHost();

  @override
  State<_SurveyHost> createState() => _SurveyHostState();
}

class _SurveyHostState extends State<_SurveyHost> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StateSwitcher(
          labels: [for (final s in SurveyState.values) s.name],
          selected: _i,
          onSelect: (i) => setState(() => _i = i),
        ),
        const Divider(height: 1),
        Expanded(child: SurveyRailWireframe(state: SurveyState.values[_i])),
      ],
    );
  }
}

class _AssistHost extends StatefulWidget {
  const _AssistHost();

  @override
  State<_AssistHost> createState() => _AssistHostState();
}

class _AssistHostState extends State<_AssistHost> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StateSwitcher(
          labels: [for (final s in AssistState.values) s.name],
          selected: _i,
          onSelect: (i) => setState(() => _i = i),
        ),
        const Divider(height: 1),
        Expanded(
          child: AssistedCaptureWireframe(state: AssistState.values[_i]),
        ),
      ],
    );
  }
}

class _LoginHost extends StatefulWidget {
  const _LoginHost();

  @override
  State<_LoginHost> createState() => _LoginHostState();
}

class _LoginHostState extends State<_LoginHost> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StateSwitcher(
          labels: [for (final s in LoginState.values) s.name],
          selected: _i,
          onSelect: (i) => setState(() => _i = i),
        ),
        const Divider(height: 1),
        Expanded(child: LoginWireframe(state: LoginState.values[_i])),
      ],
    );
  }
}

/// Row of buttons that swaps the state of the wireframe below it.
class _StateSwitcher extends StatelessWidget {
  const _StateSwitcher({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              TextButton(
                onPressed: () => onSelect(i),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    decoration: selected == i ? TextDecoration.underline : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectorHost extends StatefulWidget {
  const _SelectorHost();

  @override
  State<_SelectorHost> createState() => _SelectorHostState();
}

class _SelectorHostState extends State<_SelectorHost> {
  int _i = 1; // start on the populated list

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StateSwitcher(
          labels: [for (final s in SelectorState.values) s.name],
          selected: _i,
          onSelect: (i) => setState(() => _i = i),
        ),
        const Divider(height: 1),
        Expanded(
          child: RouteSelectorWireframe(
            state: SelectorState.values[_i],
            routes: wireframeDummyRoutes,
          ),
        ),
      ],
    );
  }
}

class _ResumeHost extends StatefulWidget {
  const _ResumeHost();

  @override
  State<_ResumeHost> createState() => _ResumeHostState();
}

class _ResumeHostState extends State<_ResumeHost> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StateSwitcher(
          labels: [for (final s in ResumeState.values) s.name],
          selected: _i,
          onSelect: (i) => setState(() => _i = i),
        ),
        const Divider(height: 1),
        Expanded(
          child: ResumeRouteWireframe(
            state: ResumeState.values[_i],
            units: wireframeDummyUnits,
          ),
        ),
      ],
    );
  }
}
