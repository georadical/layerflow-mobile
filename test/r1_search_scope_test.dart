import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/db/database.dart';

import 'support/sqlite3.dart';

/// Spec 13 (AM.6): the R1 typeahead must scope to the parada's manzana in BOTH
/// modes — the prefix (full-address) search AND the placa-part search. The
/// cross-manzana bug (a "CALLE 13 # 3A-02" from manzana 327 linked on a manzana
/// 005 parada) came from the prefix search ignoring the manzana filter.

Future<AppDatabase?> _memoryDb() async {
  useSystemSqlite3();
  try {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    return db;
  } catch (_) {
    return null;
  }
}

R1DirectoryCompanion _r1(int tenant, String npn, String manzana, String norm) =>
    R1DirectoryCompanion.insert(
      tenantId: tenant,
      npn: npn,
      direccion: norm,
      direccionNorm: norm,
      manzana: Value(manzana),
      parseOk: const Value(true),
    );

void main() {
  const tenant = 1;
  const mz327 = '41551010100000327';
  const mz005 = '41551010100000005';

  // Same street "CALLE 13" lives in TWO manzanas — the scope must separate them.
  Future<void> seed(AppDatabase db) => db.replaceR1Slice(tenant, [
        _r1(tenant, 'n1', mz327, 'CALLE 13 # 3A-02'),
        _r1(tenant, 'n2', mz327, 'CALLE 13 # 3A-08'),
        _r1(tenant, 'n3', mz005, 'CALLE 13 # 9-10'), // CALLE 13 in ANOTHER manzana
        _r1(tenant, 'n4', mz005, 'CALLE 14 # 2-104'),
      ]);

  test('prefix (full-address) search scopes to the manzana', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    await seed(db);

    // Scoped to 327: only the two 327 rows, never the 005 "CALLE 13 # 9-10".
    final scoped = await db.searchR1(tenant, 'CALLE 13', manzana: mz327);
    expect(
      scoped.map((r) => r.direccionNorm).toSet(),
      {'CALLE 13 # 3A-02', 'CALLE 13 # 3A-08'},
    );

    // Null manzana = the legacy GLOBAL search (what the bug exploited): the
    // other manzana's CALLE 13 leaks in. Documents why the scope is required.
    final global = await db.searchR1(tenant, 'CALLE 13', manzana: null);
    expect(global.any((r) => r.direccionNorm == 'CALLE 13 # 9-10'), isTrue);
  });

  test('placa-part search scopes to the manzana', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    await seed(db);

    // "# 3A-02" exists only in 327 → scoping to 005 returns nothing (so a 005
    // parada can never link the 327 door).
    final in005 = await db.searchR1Part(tenant, '# 3A-02', manzana: mz005);
    expect(in005, isEmpty);

    final in327 = await db.searchR1Part(tenant, '# 3A-02', manzana: mz327);
    expect(in327.map((r) => r.direccionNorm), contains('CALLE 13 # 3A-02'));
  });
}
