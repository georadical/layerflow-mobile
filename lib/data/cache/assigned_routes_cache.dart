import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/dtos.dart';

/// Last successful `GET /field/routes`, kept so the selector still works with
/// no signal (BR9) — one copy PER TENANT (Spec 6, BR3): the offline fallback
/// must never serve ESP A's list while ESP B is active. `tenantId` null is
/// the paste flow's single implicit slot.
///
/// Stored as JSON in SharedPreferences rather than in drift on purpose: this
/// list is derived, disposable presentation data that is replaced wholesale on
/// every successful request. Widening the `Routes` table for it would mean a
/// schema migration to carry something the server owns and can re-send.
/// Captures — the data that would actually be lost — do live in drift.
class AssignedRoutesCache {
  static const _base = 'assigned_routes_cache';

  static String _key(int? tenantId) =>
      tenantId == null ? _base : '${_base}_t$tenantId';

  Future<void> save(AssignedRoutes routes, {int? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(tenantId), jsonEncode(routes.toJson()));
  }

  /// Returns null when there is nothing cached FOR THIS TENANT or the stored
  /// copy is unreadable — a corrupt cache must never break the screen, and a
  /// missing per-tenant copy must never fall back to another tenant's.
  Future<AssignedRoutes?> load({int? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(tenantId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return AssignedRoutes.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear({int? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(tenantId));
  }
}
