import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

class LayerFlowCaptureApp extends StatelessWidget {
  const LayerFlowCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerFlow — Captura',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
