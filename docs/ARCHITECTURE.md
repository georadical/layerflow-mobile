# Architecture

Flutter capture app, offline-first, coordinate-free. Designed so that a single
maintainer can sustain it and so that **GNSS can be plugged in later without a rewrite**.

## Layers

```
UI (Riverpod, Material 3)
  Home / Capture / List / Settings
        │  reads providers
        ▼
Providers (lib/ui/providers.dart)
        │  injects
        ▼
Services / Repository
  SyncService  ──►  ApiClient (dio)  ──►  LayerFlow backend
  CaptureRepository ──► AppDatabase (drift/local SQLite)
        ▲
        │ (seam, not used in the MVP)
  LocationSource → NullLocationSource
```

Rule: the **UI never touches** the DB or the network directly; it goes through the
repository and the sync service. The repository is the **sole** owner of the domain
invariants.

## Local data model (drift)

- **Routes**: `routeId` (PK), `codigo`, `lastFrameSyncAt`.
- **Captures**: `clientId` (PK, UUID), `routeId`, `orden`, `placa?`,
  `manzanaCatastral?`, `tipoAcceso?`, `observacion?`, `loc?`, `remoteId?`,
  `syncStatus` (pending|synced|error), `syncError?`, `createdAt`, `updatedAt`.
  **There is no coordinates column.**

## Invariants and where they are enforced

| Invariant | Where |
|---|---|
| Append-only orden (`max(orden)+1`, no reordering) | `CaptureRepository.appendCapture` / `nextOrden`; `editCapture` never touches `orden`. |
| Idempotency by `client_id` | `clientId` = local PK; the POST re-sends the pending queue; the backend upserts. |
| Coordinate-free | DTOs without lat/lon (`test/dtos_test.dart` verifies it); `NullLocationSource` never returns a fix. |
| The app assigns neither PH/PV nor `loc` | `loc` comes from the server (`orden×5`) and is stored on sync; PH/PV are a later milestone. |

## Synchronization

- **Pull (resume)** — `SyncService.pullFrame`: `GET` the frame → `mergeFrame`.
  - new item from the server → insert as `synced`;
  - local item that is `synced` → refresh placa/loc from the server;
  - local item that is `pending`/`error` → **preserve** (do not overwrite unsent edits);
    the later re-send is idempotent.
- **Push (queue)** — `SyncService.pushPending`: builds a batch (new `batch_id`) with
  everything unsynced and does a `POST`. It is not all-or-nothing: each item is marked
  `synced`/`error` according to its own result. It is triggered manually (button) and
  best-effort after every capture when there is a connection.

## The GNSS seam (future, do not implement yet)

`LocationSource` (interface) + `NullLocationSource` (MVP, always `null`). The
`locationSourceProvider` provider returns the NULL one today. For the GNSS phase: create
`BluetoothNmeaLocationSource implements LocationSource`, switch that provider, and extend
the model/DTO **additively**. Nothing in the current capture flow calls `currentFix()`,
so the MVP stays coordinate-free by construction.

## Dependency decisions

- **drift** (typed SQLite) for the offline queue and the orden queries.
- **dio** for its interceptors (injects `Authorization: Bearer <token>` per request).
- **flutter_riverpod** for testable injection/state.
- **flutter_secure_storage** for the token; **shared_preferences** for URL/route.
- **connectivity_plus** to enable/disable the push.

## What is NOT here (by design)

Extended survey (PH/PV, household, meter), map, real coordinates, route design,
NPN matching. Insert/absent/skip mid-route = v2.
