import 'package:flutter/material.dart';

/// Spec 11 — the per-parada sequence number, once CONFIRMED by the backend
/// (`secuencia_parada`), reads in bold + this green. Material Green 800: ~4.9:1
/// contrast on the light surface (AA for normal text; the app is light-only),
/// and darker still against the bold weight. A PROVISIONAL (pre-sync) number
/// instead uses `colorScheme.onSurfaceVariant` (medium gray) + a tilde + a
/// pending glyph — never this green.
const Color kPredioDefinitivo = Color(0xFF2E7D32);

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
