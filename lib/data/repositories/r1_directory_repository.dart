import 'package:drift/drift.dart';

import '../../core/address/address_normalizer.dart';
import '../api/api_client.dart';
import '../db/database.dart';
import '../settings/settings_store.dart';

/// Outcome of a directory refresh, for the caller's messaging.
class R1RefreshResult {
  const R1RefreshResult({required this.unchanged, required this.count});

  final bool unchanged;

  /// Rows now held locally for the tenant.
  final int count;
}

/// The tenant's R1 slice on the device (Spec 7, T7.1).
///
/// Refresh runs at sync moments and NEVER blocks capture (CL-R4): a stale
/// or empty directory only means fewer suggestions. Full snapshot with a
/// `version` tag; per-tenant slices coexist without mixing.
class R1DirectoryRepository {
  R1DirectoryRepository(this._db, this._api, this._settings);

  final AppDatabase _db;
  final ApiClient _api;
  final SettingsStore _settings;

  /// Fetches the slice if it changed; replaces the tenant's copy atomically.
  Future<R1RefreshResult> refresh(int tenantId) async {
    final known = await _settings.getR1Version(tenantId);
    final res = await _api.getR1Directory(knownVersion: known);
    if (res.unchanged) {
      return R1RefreshResult(
        unchanged: true,
        count: await _db.r1CountForTenant(tenantId),
      );
    }
    await _db.replaceR1Slice(tenantId, [
      for (final item in res.items)
        R1DirectoryCompanion.insert(
          tenantId: tenantId,
          npn: item.npn,
          direccion: item.direccion,
          direccionNorm: item.direccionNorm,
          manzana: Value(item.manzana),
        ),
    ]);
    await _settings.setR1Version(tenantId, res.version);
    return R1RefreshResult(unchanged: false, count: res.items.length);
  }

  /// Typeahead: turns the RAW typed text into the pinned normal form and
  /// prefix-matches the directory. Progressive from "C 5 2" (CALLE 5 # 2)
  /// onward; "C 5 2 0" narrows to "CALLE 5 # 2-0". Text that does not
  /// start with a street type (rural) yields no suggestions — the
  /// typeahead never pretends to cover that population.
  Future<List<R1DirectoryData>> search(int tenantId, String rawTyped) async {
    final prefix = typeaheadPrefix(rawTyped);
    if (prefix == null) return const [];
    return _db.searchR1(tenantId, prefix);
  }

  /// Rows held locally for the tenant (0 = no directory yet: the capture
  /// screen shows no panel at all — classic capture).
  Future<int> countFor(int tenantId) => _db.r1CountForTenant(tenantId);

  /// Names an existing link: the address behind [npn], or null when the
  /// local slice does not carry it (linked elsewhere / directory reloaded).
  Future<R1DirectoryData?> byNpn(int tenantId, String npn) =>
      _db.r1ByNpn(tenantId, npn);

  /// Builds the progressive normalized prefix, or null when the text does
  /// not (yet) look like a street address. Exposed for tests.
  ///
  /// SPECIFICITY GATE (CL-R1 amendment): suggestions require at least
  /// via + street number + the start of the cruce ("C 1 3", never "C").
  /// Without it the typeahead rewards laziness — one letter, one tap, and
  /// the stored "observed placa" is the letter "c": garbage placas AND a
  /// divergence flood, because every lazy capture classifies as trigger 2.
  static String? typeaheadPrefix(String rawTyped) {
    final s = cleanAddress(rawTyped);
    if (s.isEmpty) return null;
    final tokens = s.split(' ');
    final via = viaFor(tokens.first);
    if (via == null) return null;
    final core = dropNumberMarkers(tokens.sublist(1));
    if (core.length < 2) return null; // the gate
    return core.length == 2
        ? '$via ${core[0]} # ${core[1]}'
        : '$via ${core[0]} # ${core[1]}-${core.sublist(2).join()}';
  }
}
