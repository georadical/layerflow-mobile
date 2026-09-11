import 'package:flutter/material.dart';

import 'ui/screens/route_selector_screen.dart';
import 'ui/theme.dart';

class LayerFlowCaptureApp extends StatelessWidget {
  const LayerFlowCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerFlow — Captura',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // The worker lands on their assigned routes: the day starts by picking
      // one, not by typing a UUID.
      home: const RouteSelectorScreen(),
    );
  }
}
