# Arquitectura

App Flutter de captura, offline-first, coordinate-free. Diseñada para que un solo
mantenedor la sostenga y para **enchufar GNSS después sin reescribir**.

## Capas

```
UI (Riverpod, Material 3)
  Home / Captura / Lista / Ajustes
        │  lee providers
        ▼
Providers (lib/ui/providers.dart)
        │  inyecta
        ▼
Servicios / Repositorio
  SyncService  ──►  ApiClient (dio)  ──►  Backend LayerFlow
  CaptureRepository ──► AppDatabase (drift/SQLite local)
        ▲
        │ (costura, no usada en el MVP)
  LocationSource → NullLocationSource
```

Regla: la **UI no toca** la BD ni la red directamente; pasa por el repositorio y el
servicio de sync. El repositorio es el **único** dueño de las invariantes de dominio.

## Modelo de datos local (drift)

- **Routes**: `routeId` (PK), `codigo`, `lastFrameSyncAt`.
- **Captures**: `clientId` (PK, UUID), `routeId`, `orden`, `placa?`,
  `manzanaCatastral?`, `tipoAcceso?`, `observacion?`, `loc?`, `remoteId?`,
  `syncStatus` (pending|synced|error), `syncError?`, `createdAt`, `updatedAt`.
  **No existe columna de coordenadas.**

## Invariantes y dónde se imponen

| Invariante | Dónde |
|---|---|
| Orden append-only (`max(orden)+1`, sin reordenar) | `CaptureRepository.appendCapture` / `nextOrden`; `editCapture` no toca `orden`. |
| Idempotencia por `client_id` | `clientId` = PK local; el POST reenvía la cola pendiente; el backend upsert. |
| Coordinate-free | DTOs sin lat/lon (`test/dtos_test.dart` lo verifica); `NullLocationSource` nunca entrega fix. |
| La app no asigna PH/PV ni `loc` | `loc` llega del server (`orden×5`) y se guarda al sincronizar; PH/PV son milestone posterior. |

## Sincronización

- **Pull (reanudar)** — `SyncService.pullFrame`: `GET` del frame → `mergeFrame`.
  - item del server nuevo → insertar como `synced`;
  - item local `synced` → refrescar placa/loc del server;
  - item local `pending`/`error` → **preservar** (no pisar ediciones sin enviar);
    el re-envío posterior es idempotente.
- **Push (cola)** — `SyncService.pushPending`: arma un lote (`batch_id` nuevo) con lo
  no sincronizado y hace `POST`. No es all-or-nothing: cada item se marca
  `synced`/`error` según su resultado. Se dispara manual (botón) y best-effort tras
  cada captura si hay conexión.

## La costura GNSS (futuro, no implementar aún)

`LocationSource` (interfaz) + `NullLocationSource` (MVP, siempre `null`). El provider
`locationSourceProvider` entrega la NULA hoy. Para la fase GNSS: crear
`BluetoothNmeaLocationSource implements LocationSource`, cambiar ese provider, y
extender el modelo/DTO **de forma aditiva**. Nada del flujo de captura actual llama a
`currentFix()`, así que el MVP permanece coordinate-free por construcción.

## Decisiones de dependencias

- **drift** (SQLite tipado) para la cola offline y las queries de orden.
- **dio** por interceptores (inyecta `Authorization: Bearer <token>` por request).
- **flutter_riverpod** para inyección/estado testeable.
- **flutter_secure_storage** para el token; **shared_preferences** para URL/ruta.
- **connectivity_plus** para habilitar/deshabilitar el push.

## Qué NO está aquí (por diseño)

Encuesta extendida (PH/PV, hogar, medidor), mapa, coordenadas reales, diseño de ruta,
matching NPN. Insert/ausente/skip a media ruta = v2.
