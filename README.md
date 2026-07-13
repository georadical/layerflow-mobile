# LayerFlow — App de captura (Flutter)

App móvil Android para la **captura de placas en orden estricto**, *coordinate-free*,
que alimenta la API de captura del backend LayerFlow. MVP del censo (Colombia).

- **Offline-first**: captura sin red, cola local (SQLite/drift), sincroniza al reconectar.
- **Idempotente** por `client_id` (re-envío seguro; el backend actualiza, no duplica).
- **Orden append-only** impuesto por la app (1, 2, 3…). `loc = orden × 5` lo pone el server.
- **Sin coordenadas** en ninguna parte del payload ni del almacenamiento.
- **Costura GNSS** lista (interfaz `LocationSource` + `NullLocationSource`), sin implementar.

---

## Requisitos (Windows)

1. **Flutter SDK** (canal stable). Descárgalo de flutter.dev, descomprime en p. ej.
   `C:\src\flutter`, y agrega `C:\src\flutter\bin` al **PATH**. Verifica:
   ```powershell
   flutter --version
   flutter doctor
   ```
2. **Android Studio** (para el SDK de Android, el emulador y los drivers). Acepta las
   licencias: `flutter doctor --android-licenses`.

> Hoy `flutter` **no está** en el PATH de esta máquina. Instálalo antes de continuar.

## Puesta en marcha (una sola vez)

Desde la raíz del proyecto:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

El script (idempotente): genera la carpeta nativa `android/` **sin pisar el código**,
habilita cleartext HTTP para backends `http://…` en desarrollo, corre `flutter pub get`,
genera el código de **drift** (`build_runner`) y ejecuta `analyze` + `test`.

## Correr

```powershell
flutter devices          # lista emuladores/dispositivos
flutter run              # instala y ejecuta en modo debug
flutter build apk --release   # APK instalable (build\app\outputs\flutter-apk\)
```

## Configurar la app (en el dispositivo)

1. Abre **Ajustes** (ícono ⚙️): pon la **URL del backend** (sin barra final, p. ej.
   `http://192.168.1.10:8000`) y el **field_token** (JWT emitido por el operador).

   El operador obtiene el `field_token` **fuera de la app** (el `operator_token`
   nunca toca el equipo de campo):
   ```
   POST /field-workers/{worker_id}/field-token?tenant_id=<ESP>
     Authorization: Bearer <operator_token>
   → { "token": "<field_token>", "expires_in_days": 30 }
   ```
   Pega ese `<field_token>` en Ajustes. La app decodifica el claim `exp` del JWT
   (sin verificar la firma) y **avisa** cuando el token está por vencer o venció,
   en Ajustes y con un banner en Inicio/Captura.
2. En **Abrir ruta**, pega el `route_id` (UUID) de la ruta congelada y pulsa
   **Abrir y reanudar** (con conexión trae el frame y restaura lo capturado).
3. Captura domicilio por domicilio: **placa** + tipo de acceso/observación opcionales →
   **Guardar y siguiente**. La tarjeta superior muestra la **última placa** para
   verificarla contra la puerta.

> Backend en `localhost`: un emulador Android ve el host como `10.0.2.2`
> (usa `http://10.0.2.2:8000`); un teléfono físico usa la IP LAN del PC, o
> `adb reverse tcp:8000 tcp:8000` y `http://127.0.0.1:8000`.

## Flujo de datos (contrato)

- `GET /field/capture/route/{route_id}` → frame para **reanudar**.
- `POST /field/capture/placas` → **upsert por lote**, idempotente por `client_id`.

Ver el contrato completo en [field-capture-api.md](field-capture-api.md) y las
decisiones de operación en [census-field-operations.md](census-field-operations.md).

## Arquitectura

Ver [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Resumen de capas:

```
lib/
  core/location/location_source.dart   # costura GNSS (NULA en el MVP)
  core/config/app_config.dart          # constantes / rutas de la API
  data/db/database.dart                # drift: tablas Routes, Captures + queries
  data/api/dtos.dart                    # DTOs del contrato (coordinate-free)
  data/api/api_client.dart             # dio: baseUrl + Bearer token
  data/settings/settings_store.dart    # URL (prefs) + token (secure storage)
  data/repositories/capture_repository.dart  # invariantes: append-only, idempotencia
  data/sync/sync_service.dart          # pull frame (reanudar) + push cola
  ui/…                                 # Riverpod + pantallas (Home, Captura, Lista, Ajustes)
```

## Invariantes (no violar)

- **Coordinate-free**: el payload no lleva lat/lon (test automatizado lo verifica).
- **Orden append-only**: lo asigna el repositorio (`max(orden)+1`); la UI no reordena.
- **Idempotencia** por `client_id`; re-enviar actualiza.
- La app **no** asigna PH/PV (quedan 00; es un milestone posterior).

## Fuera del MVP

Encuesta extendida (PH/PV, hogar, medidor), mapa, captura real de coordenadas,
diseño/validación de ruta, matching NPN (backend). El *insert/ausente/skip* a media
ruta es **v2**; el MVP es **append estricto**.

## Notas de mantenimiento

- El código generado (`*.g.dart`) está en `.gitignore`; se regenera con
  `dart run build_runner build --delete-conflicting-outputs`.
- `pubspec.lock` está ignorado al inicio; **descoméntalo del `.gitignore` y
  haz commit** tras el primer build estable para fijar versiones.
- Tests: `flutter test`. Los tests de BD usan sqlite3 nativo; si el host no lo
  tiene, se **saltan** solos (no fallan).
