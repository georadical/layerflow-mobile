import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';

class LayerFlowCaptureApp extends StatelessWidget {
  const LayerFlowCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerFlow — Captura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
