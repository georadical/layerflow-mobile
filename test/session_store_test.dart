import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/settings/settings_store.dart';

/// In-memory stand-in for the platform secure storage. Implemented through
/// noSuchMethod so it survives signature changes in the package.
class _MemSecure implements FlutterSecureStorage {
  final Map<String, String?> data = {};

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #read:
        return Future<String?>.value(data[inv.namedArguments[#key]]);
      case #write:
        data[inv.namedArguments[#key] as String] =
            inv.namedArguments[#value] as String?;
        return Future<void>.value();
      case #delete:
        data.remove(inv.namedArguments[#key]);
        return Future<void>.value();
    }
    return super.noSuchMethod(inv);
  }
}

FieldSession _twoEspSession({int? active}) => FieldSession(
      email: 'campo1@layerflow.co',
      workerNombre: 'Ana',
      esps: const [
        LoginEsp(
          tenantId: 2,
          espNombre: 'ESP Elías',
          fieldWorkerId: 'fw-2',
          rutasAsignadas: 1,
          fieldToken: 'token-elias',
        ),
        LoginEsp(
          tenantId: 3,
          espNombre: 'ESP Isnos (muestra)',
          fieldWorkerId: 'fw-3',
          rutasAsignadas: 1,
          fieldToken: 'token-isnos',
        ),
      ],
      activeTenantId: active,
    );

void main() {
  test('saveSession mirrors the ACTIVE token into the legacy slot', () async {
    final store = SettingsStore(secure: _MemSecure());

    await store.saveSession(_twoEspSession(active: 3));

    final session = await store.getSession();
    expect(session!.activeEsp!.espNombre, 'ESP Isnos (muestra)');
    // The mirror is what keeps the API client and every existing flow
    // working untouched (Spec 5 acceptance).
    expect(await store.getToken(), 'token-isnos');
  });

  test('no active ESP chosen yet → the token slot is left alone', () async {
    final store = SettingsStore(secure: _MemSecure());
    await store.setToken('pasted-by-hand'); // CL1 path

    await store.saveSession(_twoEspSession(active: null));

    expect(await store.getToken(), 'pasted-by-hand',
        reason: 'a session without a choice must not clobber the slot');
  });

  test('setActiveEsp switches the mirrored token (CL5)', () async {
    final store = SettingsStore(secure: _MemSecure());
    await store.saveSession(_twoEspSession(active: 3));

    final updated = await store.setActiveEsp(2);

    expect(updated!.activeEsp!.espNombre, 'ESP Elías');
    expect(await store.getToken(), 'token-elias');
    // The choice is persisted, not just returned.
    expect((await store.getSession())!.activeTenantId, 2);
  });

  test('clearSession wipes session and mirrored token', () async {
    final store = SettingsStore(secure: _MemSecure());
    await store.saveSession(_twoEspSession(active: 3));

    await store.clearSession();

    expect(await store.getSession(), isNull);
    expect(await store.getToken(), isNull);
  });

  test('a corrupt stored session reads as logged-out, never crashes', () async {
    final secure = _MemSecure();
    secure.data['field_session'] = '{not json';
    final store = SettingsStore(secure: secure);

    expect(await store.getSession(), isNull);
  });

  test('withEspToken replaces one token and nothing else (refresh, T5.3)', () {
    final session = _twoEspSession(active: 3);

    final updated = session.withEspToken(3, 'token-isnos-fresh');

    expect(updated.activeEsp!.fieldToken, 'token-isnos-fresh');
    expect(updated.esps.first.fieldToken, 'token-elias');
    expect(updated.email, session.email);
    expect(updated.activeTenantId, 3);
  });
}
