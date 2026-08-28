# LayerFlow — Capture app (Flutter)

Android mobile app for the **strict-order capture of placas**, *coordinate-free*,
feeding the LayerFlow backend capture API. Census MVP (Colombia).

- **Offline-first**: captures without network, local queue (SQLite/drift), syncs on reconnect.
- **Idempotent** by `client_id` (safe re-send; the backend updates, it does not duplicate).
- **Append-only orden** enforced by the app (1, 2, 3…). `loc = orden × 5` is set by the server.
- **No coordinates** anywhere in the payload or in storage.
- **GNSS seam** in place (`LocationSource` interface + `NullLocationSource`), not implemented.

---

## Requirements (Windows)

1. **Flutter SDK** (stable channel). Download it from flutter.dev, unzip it into e.g.
   `C:\src\flutter`, and add `C:\src\flutter\bin` to the **PATH**. Verify with:
   ```powershell
   flutter --version
   flutter doctor
   ```
2. **Android Studio** (for the Android SDK, the emulator and the drivers). Accept the
   licenses: `flutter doctor --android-licenses`.

> Right now `flutter` is **not** on this machine's PATH. Install it before continuing.

## Setup (one time only)

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

The script (idempotent) generates the native `android/` folder **without overwriting the
code**, enables cleartext HTTP for `http://…` backends in development, runs
`flutter pub get`, generates the **drift** code (`build_runner`) and runs `analyze` + `test`.

## Running

```powershell
flutter devices          # lists emulators/devices
flutter run              # installs and runs in debug mode
flutter build apk --release   # installable APK (build\app\outputs\flutter-apk\)
```

## Configuring the app (on the device)

1. Open **Ajustes** (⚙️ icon): set the **backend URL** (no trailing slash, e.g.
   `http://192.168.1.10:8000`) and the **field_token** (JWT issued by the operator).

   The operator obtains the `field_token` **outside the app** (the `operator_token`
   never touches the field device):
   ```
   POST /field-workers/{worker_id}/field-token?tenant_id=<ESP>
     Authorization: Bearer <operator_token>
   → { "token": "<field_token>", "expires_in_days": 30 }
   ```
   Paste that `<field_token>` into Ajustes. The app decodes the JWT `exp` claim
   (without verifying the signature) and **warns** when the token is about to expire or
   has expired, both in Ajustes and with a banner on Home/Capture.
2. In **Abrir ruta**, paste the `route_id` (UUID) of the frozen route and tap
   **Abrir y reanudar** (when online it fetches the frame and restores what was captured).
3. Capture household by household: **placa** + optional access type/observation →
   **Guardar y siguiente**. The top card shows the **last placa** so it can be checked
   against the door.

> Backend on `localhost`: an Android emulator sees the host as `10.0.2.2`
> (use `http://10.0.2.2:8000`); a physical phone uses the PC's LAN IP, or
> `adb reverse tcp:8000 tcp:8000` and `http://127.0.0.1:8000`.

## Data flow (contract)

- `GET /field/capture/route/{route_id}` → frame to **resume**.
- `POST /field/capture/placas` → **batch upsert**, idempotent by `client_id`.

See the full contract in [field-capture-api.md](field-capture-api.md) and the
operational decisions in [census-field-operations.md](census-field-operations.md).

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Summary of the layers:

```
lib/
  core/location/location_source.dart   # GNSS seam (NULL in the MVP)
  core/config/app_config.dart          # constants / API paths
  data/db/database.dart                # drift: Routes, Captures tables + queries
  data/api/dtos.dart                    # contract DTOs (coordinate-free)
  data/api/api_client.dart             # dio: baseUrl + Bearer token
  data/settings/settings_store.dart    # URL (prefs) + token (secure storage)
  data/repositories/capture_repository.dart  # invariants: append-only, idempotency
  data/sync/sync_service.dart          # pull frame (resume) + push queue
  ui/…                                 # Riverpod + screens (Home, Capture, List, Settings)
```

## Invariants (do not violate)

- **Coordinate-free**: the payload carries no lat/lon (an automated test verifies it).
- **Append-only orden**: assigned by the repository (`max(orden)+1`); the UI never reorders.
- **Idempotency** by `client_id`; re-sending updates.
- The app does **not** assign PH/PV (they stay 00; that is a later milestone).

## Out of MVP scope

Extended survey (PH/PV, household, meter), map, real coordinate capture,
route design/validation, NPN matching (backend). *Insert/absent/skip* mid-route is
**v2**; the MVP is **strict append**.

## Maintenance notes

- Generated code (`*.g.dart`) is in `.gitignore`; regenerate it with
  `dart run build_runner build --delete-conflicting-outputs`.
- `pubspec.lock` is ignored initially; **uncomment it from `.gitignore` and
  commit it** after the first stable build to pin versions.
- Tests: `flutter test`. The DB tests use native sqlite3; if the host does not
  have it, they **skip** themselves (they do not fail).
