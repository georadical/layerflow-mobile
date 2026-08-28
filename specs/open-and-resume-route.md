# Spec 1 — Open and resume route (mobile capture app)

Status: draft (ready for tickets)
Type: Mobile app (Flutter) + 1 backend dependency (new wire)
Approach: spec-driven & wire-driven. The spec is the source of truth for the contract.
Chain: **Spec 1 (this one)** → 2 strict-order capture (local) → 3 batch push (`POST placas`) → 4 offline-first/retry.

## User story
**As** a LayerFlow field worker using the capture app (authenticated with my
`field_token`, scoped to my ESP), **I want** to see the list of routes assigned to me
(synchronized), open one and immediately see what has already been captured —with the
**address** as the leading piece of data and ordered by the walking sequence—, **so
that** I can resume from where I left off (or confirm that it is empty) without
duplicating units or losing the strict order.

## Goal
Provide the entry point that is usable in real field conditions: **sync assigned routes →
open one → see the resumed state**. It is the foundation on which Specs 2–4 capture and
synchronize.

## Scope

**Includes**
- List of **routes assigned** to the field worker, synchronized from the backend
  (**new wire**, see Dependencies) and cached locally so it can be seen offline.
- Opening a route (from the list) → `GET /field/capture/route/{route_id}` →
  merge the frame with local data (without overwriting unsent edits).
- **Resume (read-only)** view: units already captured, **address (`placa`)
  as the lead**, ordered by ascending `loc` (the walking order).
- Explicit empty state; loading states; error handling and translation
  (401/404/400/no connection); token expiration warnings.
- Persist the opened route as the **active route** (survives an app restart).

**Does NOT include** (mandatory)
- Capturing, editing or deleting units (Spec 2).
- Batch push `POST /field/capture/placas` (Spec 3) or queue retry (Spec 4).
- Issuing/renewing the `field_token` (done on the backend/by the operator; the app only
  stores it in Ajustes).
- Design of the token issuing endpoint, the observation layer (`/sync/*`), PH/PV
  expansion, media/photos and **any coordinate** (coordinate-free invariant).
- Editing the order / reassigning `loc` (set by the backend: `loc = orden × 5`).

## Actors and permissions
- **Field worker** (our team), authenticated with a `field_token` (`require_field`,
  kind=`field`), scoped to **one ESP (tenant)** and to their worker. They only see routes
  from their ESP; routes from another ESP are invisible (→ 404 when trying to open them by id).

## Preconditions
- The app has a **base URL** and a **field_token** stored in Ajustes (the token persists
  in `EncryptedSharedPreferences`).
- The backend is reachable (emulator → `http://10.0.2.2:8000`).
- The **new wire** for assigned routes exists (see Dependencies). While it does not exist,
  alternative flow B applies (manual entry of a `route_id`).
- The routes are **congelada** (validated) on the census backbone side.

### Dependencies — new wire (to be specified/built on the backend)
`GET /field/routes` (auth `require_field`, scoped to the token's ESP) →
```json
{
  "esp": "Isnos",
  "items": [
    { "route_id": "uuid", "codigo": "10", "manzana_catastral": "001",
      "total_capturado": 12, "estado": "congelada" }
  ]
}
```
- Returns only the routes visible to that token (ESP + worker).
- Ordered by `codigo`. `total_capturado` feeds the progress badge in the list.
- No coordinates. It is a **prerequisite**: it is handled as a separate backend spec and
  this Spec 1 consumes it.

## Trigger
The worker opens the app (or enters the Home screen) and taps **"Sincronizar rutas"**, or
selects a route already listed and taps **"Abrir y reanudar"**.

## Main flow (happy path)
1. On the Home screen, the app shows the **list of assigned routes** (from the local
   cache) and offers **"Sincronizar"**.
2. The worker taps **"Sincronizar"** → `GET /field/routes` with `Bearer <field_token>`.
3. The app stores/updates the local list and shows it ordered by `codigo`, each
   item with `codigo`, `manzana_catastral` and a `total_capturado` badge.
4. The worker **taps a route** in the list → the app calls `GET /field/capture/route/{route_id}`.
5. The app **merges** the frame with local data (rule BR3) and **persists the active route**.
6. It navigates to the **resume (read-only)** view, with:
   - title = **route code** (e.g. "Ruta 10"),
   - list of units ordered by **ascending `loc`**,
   - per item: **`placa` as the large title (the address)**; small, secondary
     subtitle with `orden` and `loc` (and `manzana` if present).
7. If the frame has no items → it shows the **empty state** ("Ruta sin capturas aún;
   empieza a capturar").

## Alternative flows (sad paths)
- **A1 — No connection while syncing**: `GET /field/routes` fails on the network → the app
  shows the **last cached list** with a "sin sincronizar (offline)" notice. It does not block.
- **A2 — Opening offline**: the worker taps a route with no network → the app opens with
  whatever is available **locally** and warns "abierta sin reanudar (offline)". When the
  network comes back, reopening synchronizes (idempotent).
- **B — Manual entry (fallback / while the new wire does not exist)**: the worker
  types/pastes a `route_id` and **taps the "Abrir y reanudar" button**; the app validates the
  UUID locally and continues from step 4. (A different interaction path from the happy
  path, which opens by **tapping the list**.)
- **C — 401 (missing/invalid/expired token)**: SnackBar "Token vencido o inválido —
  renuévalo en Ajustes" + an "Ajustes" action; it stays on Home.
- **D — 404 (route from another ESP or nonexistent)**: SnackBar "Esa ruta no existe o no es de
  tu ESP"; it does not navigate.
- **E — 400 (non-UUID route_id)**: in the manual fallback, it is detected **before** calling;
  SnackBar "route_id inválido (debe ser UUID)".
- **F — Timeout / unreachable host**: SnackBar "Sin conexión con el backend" + a
  "Reintentar" action.

## Business rules
- **BR1** Authorization: `require_field`, scoped to the token's ESP; routes from another ESP
  are invisible (404). The app never assumes cross-ESP access.
- **BR2** The app **validates the UUID** of the `route_id` in the manual fallback before calling.
- **BR3** Merge on resume (idempotent by `client_id`):
  - server item that does not exist locally → **insert as `synced`**;
  - local `pending`/`error` (unsent) → **preserved** (the local edit is not overwritten);
  - local `synced` → **updated** with `placa`/`loc`/`orden` from the server.
- **BR4** **Strict display order** = ascending `loc` (`loc = orden × 5`,
  set by the backend). The app never reorders or reassigns.
- **BR5** **Address takes the lead**: the main data point per item is the **`placa`
  (address in natural language)**; the `loc`/`orden` code is secondary metadata.
  A null `placa` → show "Sin dirección aún" (a unit created without a placa, which is valid).
- **BR6** **Coordinate-free**: no data shown or stored carries coordinates.
- **BR7** The `field_token` travels **only** as an `Authorization: Bearer` header; never in
  the URL, query, logs or telemetry.
- **BR8** Opening a route sets it as the persisted **active route**; the Home screen offers
  "Continuar ruta activa" and it survives a restart.
- **BR9** The list of assigned routes is **cached locally** for offline use; it is
  refreshed on every successful sync.

## Edge cases and error handling
- Empty frame (`items: []`) → empty state, **not** an error.
- Reopening the same route several times → no duplicates (BR3).
- Route with local `pending` captures that do not yet exist on the server → they are kept and
  shown alongside the `synced` ones (visually marked as pending).
- Valid but soon-to-expire token → non-blocking warning banner (days remaining).
- Response with `placa=null` on several items → all of them show "Sin dirección aún".
- Empty route list (worker with no assigned routes) → empty state "No tienes rutas
  asignadas en tu ESP".
- `total_capturado` missing from the wire → badge hidden, not an error.

## Acceptance criteria
- The app shows a list of assigned routes obtained from `GET /field/routes`, scoped to
  the token's ESP, ordered by `codigo`, and caches it so it can be seen offline.
- Tapping a route calls `GET /field/capture/route/{route_id}` and navigates to the resume
  view.
- The resume view orders by ascending `loc` and shows **`placa` as the leading
  title**; `orden`/`loc` as secondary metadata; a null `placa` → "Sin dirección
  aún".
- Empty frame → explicit empty state (not a blank list, not an error).
- 401 → token message + an action to Ajustes; 404 → route-not-visible message; 400
  (manual) → prior local validation; no connection → message + "Reintentar". In all of them,
  it does not navigate to resume.
- Reopening a route does not duplicate and preserves local `pending`/`error` captures.
- The opened route becomes the active one and persists after restarting the app.
- No coordinate field appears in the request, in storage or in the UI.

## BDD (Gherkin)
```gherkin
Feature: Open and resume route

  Scenario: Sync and list assigned routes
    Given a field worker authenticated with a token from the ESP Isnos
    When they tap "Sincronizar"
    Then they see the list of their routes ordered by codigo, with its total capturado
    And the list remains available offline

  Scenario: Open a route with captures, address taking the lead
    Given a route with 3 captured units (loc 5, 10, 15)
    When the worker taps that route in the list
    Then they see the 3 units ordered by ascending loc
    And each unit shows its placa as the title and loc/orden as secondary metadata

  Scenario: Open an empty route
    Given a congelada route with no captures
    When the worker opens it
    Then they see the empty state "Ruta sin capturas aún; empieza a capturar"

  Scenario: Manual fallback with an invalid UUID
    Given there is no assigned-routes wire available
    When the worker types "ruta-123" and taps "Abrir y reanudar"
    Then the app rejects it locally with "route_id inválido (debe ser UUID)"
    And it does not call the backend

  Scenario: Expired token
    Given an expired field_token
    When the worker opens a route
    Then the API responds 401
    And the app shows "Token vencido o inválido — renuévalo en Ajustes" with an action to Ajustes

  Scenario: Route from another ESP
    Given a token from the ESP Isnos
    When the worker tries to open a route from another ESP by id
    Then the API responds 404
    And the app shows "Esa ruta no existe o no es de tu ESP" and does not navigate

  Scenario: Reopening preserves what is pending
    Given a unit captured locally in pending state (not sent yet)
    When the worker reopens the route and the server frame arrives
    Then the pending unit is kept without being overwritten
    And the synced units are updated with placa/loc from the server
```

## Suggested tickets
- **T1.0 (backend, prerequisite) — `GET /field/routes`**: assigned routes scoped to the
  token's ESP, with `codigo`, `manzana_catastral`, `total_capturado`, `estado`.
  Gate: pytest (scoping by ESP, ordering by codigo, no coordinates).
- **T1.1 (app) — Route list + sync**: consume `GET /field/routes`,
  cache locally (drift), list UI with a progress badge, offline/empty states.
- **T1.2 (app) — Open and resume**: `pullFrame` + `mergeFrame` (already exists), navigation
  to the resume view; persist the active route.
- **T1.3 (app) — Resume view (read-only)**: ordering by `loc`, **placa taking the
  lead**, secondary metadata, empty state, pending marker.
- **T1.4 (app) — Error/state handling**: map 401/404/400/timeout to messages and
  actions (SnackBar + "Reintentar"/"Ajustes"); token expiration warning.
- **T1.5 (app) — Manual fallback**: keep the manual entry of a `route_id` with UUID
  validation while T1.0 does not exist.
