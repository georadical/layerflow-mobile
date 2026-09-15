import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/r1_directory_repository.dart';
import 'package:layerflow_capture/data/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mem_secure.dart';
import 'support/sqlite3.dart';

class _FakeR1Api implements ApiClient {
  _FakeR1Api(this.responses);

  /// Served in order; each call consumes one.
  final List<R1DirectoryResponse> responses;
  final List<String?> versionsAsked = [];

  @override
  Future<R1DirectoryResponse> getR1Directory({String? knownVersion}) async {
    versionsAsked.add(knownVersion);
    return responses.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

R1DirectoryItem _item(String npn, String norm, {String? manzana}) =>
    R1DirectoryItem(
        npn: npn,
        direccion: norm.replaceAll(' # ', ' '),
        direccionNorm: norm,
        manzana: manzana);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppDatabase?> tryDb() async {
    useSystemSqlite3();
    try {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      return db;
    } catch (_) {
      return null;
    }
  }

  test('refresh stores the slice and the version; unchanged skips rewrite',
      () async {
    final db = await tryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeR1Api([
      R1DirectoryResponse(version: 'v1', items: [
        _item('npn-1', 'CALLE 5 # 2-06'),
        _item('npn-2', 'CALLE 5 # 2-10'),
      ]),
      const R1DirectoryResponse(version: 'v1', unchanged: true),
    ]);
    final repo = R1DirectoryRepository(db, api, store);

    final first = await repo.refresh(3);
    expect(first.unchanged, isFalse);
    expect(first.count, 2);
    expect(await store.getR1Version(3), 'v1');

    final second = await repo.refresh(3);
    expect(second.unchanged, isTrue);
    expect(second.count, 2, reason: 'local copy intact');
    expect(api.versionsAsked, [null, 'v1'],
        reason: 'the known version travels on the second call (CL-R4)');
  });

  test('a new version REPLACES the slice wholesale (rows can disappear)',
      () async {
    final db = await tryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeR1Api([
      R1DirectoryResponse(
          version: 'v1', items: [_item('npn-1', 'CALLE 5 # 2-06')]),
      R1DirectoryResponse(
          version: 'v2', items: [_item('npn-9', 'CARRERA 2 # 4A-09')]),
    ]);
    final repo = R1DirectoryRepository(db, api, store);

    await repo.refresh(3);
    await repo.refresh(3);

    final hits = await repo.search(3, 'C 5 2');
    expect(hits, isEmpty, reason: 'the removed row must not linger');
    expect((await repo.search(3, 'K 2 4')).single.npn, 'npn-9');
  });

  test('tenant slices never mix (Spec 6 isolation applies here too)', () async {
    final db = await tryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeR1Api([
      R1DirectoryResponse(
          version: 'a', items: [_item('npn-1', 'CALLE 5 # 2-06')]),
      R1DirectoryResponse(
          version: 'b', items: [_item('npn-1', 'CALLE 9 # 1-11')]),
    ]);
    final repo = R1DirectoryRepository(db, api, store);

    await repo.refresh(2);
    await repo.refresh(3);

    expect((await repo.search(2, 'C 5 2')).single.tenantId, 2);
    expect(await repo.search(3, 'C 5 2'), isEmpty);
    // Same NPN can exist in both tenants without colliding (composite PK).
    expect((await repo.search(3, 'C 9 1')).single.npn, 'npn-1');
  });

  test('search matches progressively from raw typing', () async {
    final db = await tryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeR1Api([
      R1DirectoryResponse(version: 'v1', items: [
        _item('npn-1', 'CALLE 5 # 2-06'),
        _item('npn-2', 'CALLE 5 # 2-10'),
        _item('npn-3', 'CARRERA 2 # 4A-09'),
      ]),
    ]);
    final repo = R1DirectoryRepository(db, api, store);
    await repo.refresh(3);

    expect((await repo.search(3, 'C 5 2')).length, 2);
    expect((await repo.search(3, 'C 5 2 0')).single.npn, 'npn-1');
    expect((await repo.search(3, 'K 2 4')).single.npn, 'npn-3');
    expect(await repo.search(3, 'SAMARIA'), isEmpty,
        reason: 'rural text yields no suggestions, by doctrine');
    expect(await repo.search(3, 'C 5'), isEmpty,
        reason: 'below the specificity gate nothing is suggested (v1.1)');
  });

  test('placa mode: part search, scoped by manzana suffix (v1.2)', () async {
    final db = await tryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeR1Api([
      R1DirectoryResponse(version: 'v1', items: [
        _item('npn-1', 'CALLE 13 # 3A-08', manzana: '41359010000000107'),
        _item('npn-2', 'CARRERA 9 # 3A-08', manzana: '41359010000000212'),
        _item('npn-3', 'CALLE 13 # 3A-04', manzana: '41359010000000107'),
      ]),
    ]);
    final repo = R1DirectoryRepository(db, api, store);
    await repo.refresh(3);

    // Without manzana: both 3A-08 across the tenant (ambiguous but capped).
    expect((await repo.search(3, '3A 08')).length, 2);
    // With the short block code: suffix match narrows to one (caso feliz).
    expect((await repo.search(3, '3A 08', manzana: '107')).single.npn, 'npn-1');
    expect((await repo.search(3, '3A 08', manzana: '212')).single.npn, 'npn-2');
    // Progressive within the block.
    expect((await repo.search(3, '3A 0', manzana: '107')).length, 2);
    // Below the placa-mode gate: nothing.
    expect(await repo.search(3, '3', manzana: '107'), isEmpty);
  });
}
