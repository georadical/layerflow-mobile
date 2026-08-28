import 'package:flutter/material.dart';

/// The app theme, shared by the real app and the wireframe gallery so the
/// design phase reviews exactly what ships.
ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
