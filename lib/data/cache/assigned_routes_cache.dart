import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/dtos.dart';

/// Last successful `GET /field/routes`, kept so the selector still works with
/// no signal (BR9).
///
/// Stored as JSON in SharedPreferences rather than in drift on purpose: this
/// list is derived, disposable presentation data that is replaced wholesale on
/// every successful request. Widening the `Routes` table for it would mean a
/// schema migration to carry something the server owns and can re-send.
/// Captures — the data that would actually be lost — do live in drift.
class AssignedRoutesCache {
  static const _key = 'assigned_routes_cache';

  Future<void> save(AssignedRoutes routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(routes.toJson()));
  }

  /// Returns null when there is nothing cached or the stored copy is
  /// unreadable — a corrupt cache must never break the screen.
  Future<AssignedRoutes?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AssignedRoutes.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
