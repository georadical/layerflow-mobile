# Spec 1 — Open and resume route (mobile capture app)

Status: draft (ready for tickets). Revised against the shipped backend contract.
Type: Mobile app (Flutter). No backend work left: every wire it needs already exists.
Approach: spec-driven & wire-driven. The wire is real, so the wire wins: where this
spec once guessed, it has been corrected to match what the backend actually returns.
Chain: **Spec 1 (this one)** → 2 strict-order capture (local) → 3 batch push (`POST placas`) → 4 offline-first/retry.

> **Revision note.** The first draft of this spec was written before
> `GET /field/routes` existed and guessed parts of its shape. Five things were
> wrong and are corrected here: the route state is `verificada` (the domain is
> `borrador | verificada`; **`congelada` does not exist**), `manzana_catastral` is
> per unit and never at route level, `nombre` exists and is nullable, a non-field
> token answers **403** (not 401), and the list is scoped **per field worker**
> (titular or pareja), not merely per ESP.

## User story
**As** a LayerFlow field worker using the capture app (authenticated with my
`field_token`, scoped to my ESP), **I want** to see the routes assigned to me and open
one to immediately see what has already been captured —with the **address** as the
leading piece of data, ordered by the walking sequence—, **so that** I can resume from
where I left off (or confirm that it is empty) without duplicating units or losing the
strict order.

## Goal
Provide the entry point that is usable in real field conditions: **see my routes → open
one → see the resumed state**. It is the foundation on which Specs 2–4 capture and
synchronize.

## Scope

**Includes**
- **Route selector** screen: the routes assigned to this field worker, from
  `GET /field/routes`, with `codigo`, `estado` and a `total_capturado` progress badge.
- Pull-to-refresh on the selector, which re-issues the request.
- Opening a route (by tapping it) → `GET /field/capture/route/{route_id}` → merge the
  frame with local data without overwriting unsent edits.
- **Resume (read-only)** view: units already captured, **address (`placa`) as the
  lead**, ordered by ascending `loc` (the walking order).
- UI states on both screens: loading / list / empty / network error / 401 / 403.
- Local cache of the route list so the selector is usable offline.
- Persist the opened route as the **active route** (survives an app restart).

**Does NOT include** (mandatory)
- Any backend change. Every endpoint consumed here already exists and is frozen for
  this spec.
- Capturing, editing or deleting units (Spec 2).
- Batch push `POST /field/capture/placas` (Spec 3) or queue retry (Spec 4).
- **Route segments** (a `localizacion` range): the whole route is opened.
- Issuing or renewing the `field_token`. There is **no login screen** in this app: the
  operator issues the token and the worker pastes it into Ajustes.
- The observation layer (`/sync/*`), PH/PV expansion, media/photos and **any
  coordinate** (coordinate-free invariant).
- Editing the order / reassigning `loc` (set by the backend: `loc = orden × 5`).

## Actors and permissions
- **Field worker (encuestador)**, authenticated with a `field_token` (`require_field`,
  kind=`field`), scoped to **one ESP (tenant)** and to themselves. The selector lists
  only routes assigned to them —as **titular or pareja**— and only those in state
  `verificada`. Routes in `borrador`, of another worker, or of another ESP simply do
  not appear; opening one by id answers 404.

## Preconditions
- The app has a **base URL** and a **field_token** stored in Ajustes (the token persists
  in `EncryptedSharedPreferences`).
- The backend is reachable (emulator → `http://10.0.2.2:8000`).
- The worker has at least one route in state `verificada` assigned to them (otherwise
  the legitimate empty state applies).

## Wire contracts consumed (source of truth — do not change from the app)

### `GET /field/routes`
Auth: `Authorization: Bearer <field_token>`. Missing token → **401**; a login (non-field)
token → **403**.

```json
{
  "esp": "ESP Isnos (muestra)",
  "items": [
    {
      "route_id": "405ca862-e116-4a12-a920-a520c0d063ee",
      "codigo": "10",
      "nombre": null,
      "estado": "verificada",
      "total_capturado": 2
    }
  ]
}
```
- `items` ordered by `codigo` ascending.
- `items: []` when the worker has no assigned routes → **200, not an error**.
- `route_id` is the very same id consumed by `GET /field/capture/route/{route_id}`.
- No coordinates. No `manzana_catastral` at this level — it belongs to the unit.

### `GET /field/capture/route/{route_id}`
Unchanged, already in use. Returns `{route_id, codigo, items:[{client_id, orden, loc,
placa, manzana_catastral}]}`.

## Trigger
The worker opens the app and lands on the route selector, or pulls to refresh it.

## Main flow (happy path)
1. The worker opens the app and reaches the **route selector**.
2. On entry the app issues `GET /field/routes` with `Bearer <field_token>` and shows a
   loading state.
3. It renders the list ordered by `codigo`. Each item shows the **route code** as the
   lead (`nombre` beside it when not null), its `estado`, and a badge with
   `total_capturado`.
4. The worker **taps a route** → the app calls `GET /field/capture/route/{route_id}`
   with that exact `route_id`.
5. The app **merges** the frame with local data (rule BR3) and **persists the active
   route**.
6. It navigates to the **resume (read-only)** view:
   - title = route `codigo` (e.g. "Ruta 10"),
   - units ordered by **ascending `loc`**,
   - per item: **`placa` as the large title (the address)**; small secondary line with
     `orden`, `loc` and `manzana` when present.
7. If the frame has no items → **empty state** ("Ruta sin capturas aún; empieza a
   capturar").

## Alternative flows (sad paths)
- **A1 — Worker with no assigned routes**: `items: []` → empty state "No tienes rutas
  asignadas en tu ESP". Not an error; pull-to-refresh stays available.
- **A2 — No connection on the selector**: the request fails → the app shows the **last
  cached list** with a "sin sincronizar (offline)" notice. If there is no cache either,
  it shows the error state with a "Reintentar" action.
- **A3 — Pull-to-refresh**: the worker **pulls down** on the list (an interaction
  distinct from the entry request in the happy path) → the request is re-issued and the
  list and badges are refreshed in place.
- **A4 — Opening offline**: the worker taps a route with no network → the app opens with
  whatever exists **locally** and warns "abierta sin reanudar (offline)". Reopening once
  the network is back synchronizes (idempotent).
- **B — 401 (missing, invalid or expired token)**: message "Token vencido o inválido —
  renuévalo en Ajustes" with an **"Ajustes"** action. There is no login screen: Ajustes
  *is* where credentials live, so that is where 401 sends the worker.
- **C — 403 (a login token, not a field token)**: message "Ese token no es de campo —
  pide un field_token al operador" with an **"Ajustes"** action. Distinct from 401: the
  token is valid but of the wrong kind, and re-pasting the same one will not help.
- **D — 404 when opening a route** (another ESP, another worker, or nonexistent):
  message "Esa ruta no existe o no es de tu ESP"; it does not navigate.
- **E — Timeout / unreachable host**: message "Sin conexión con el backend" +
  "Reintentar".

## Business rules
- **BR1** Authorization: `require_field`. The selector shows only routes assigned to
  this worker (titular or pareja) in their ESP and in state `verificada`. The app never
  assumes cross-ESP or cross-worker access, and never filters by state itself — it
  renders what the wire returns.
- **BR2** Route state vocabulary is **`borrador | verificada`**. The app must not use
  the word "congelada" anywhere, in code or in UI copy.
- **BR3** Merge on resume (idempotent by `client_id`):
  - server item that does not exist locally → **insert as `synced`**;
  - local `pending`/`error` (unsent) → **preserved** (never overwritten);
  - local `synced` → **updated** with `placa`/`loc`/`orden` from the server.
- **BR4** **Strict display order** = ascending `loc` (`loc = orden × 5`, set by the
  backend). The app never reorders or reassigns.
- **BR5** **Address takes the lead**: the main data point per unit is the **`placa`
  (address in natural language)**; `loc`/`orden` is secondary metadata. A null `placa` →
  "Sin dirección aún" (a unit created without a placa, which is valid).
- **BR6** **Coordinate-free**: no data shown or stored carries coordinates.
- **BR7** The `field_token` travels **only** as an `Authorization: Bearer` header; never
  in the URL, query, logs or telemetry.
- **BR8** Opening a route sets it as the persisted **active route**; it survives a
  restart.
- **BR9** The route list is **cached locally** for offline use and refreshed on every
  successful request.
- **BR10** The whole route is opened. Segmenting by `localizacion` range is out of scope.

## Edge cases and error handling
- `items: []` on the selector → empty state, **not** an error (A1).
- Empty frame on resume (`items: []`) → empty state, **not** an error.
- `nombre: null` → show the `codigo` alone; no placeholder, no empty parentheses.
- `total_capturado: 0` → badge shows zero rather than hiding, so "assigned but untouched"
  is distinguishable from "no data".
- `total_capturado` absent from the payload → badge hidden, not an error.
- A route disappears between two refreshes (unassigned, or moved to `borrador`) → it
  vanishes from the list; if it was the active route, local captures are **kept** and
  the worker is told it is no longer assigned.
- Reopening the same route several times → no duplicates (BR3).
- Route with local `pending` captures not yet on the server → kept and shown next to the
  `synced` ones, visually marked as pending.
- Valid but soon-to-expire token → non-blocking warning banner (days remaining).
- Several units with `placa=null` → all show "Sin dirección aún".

## Acceptance criteria
- The selector lists the routes from `GET /field/routes`, in the order the wire returns
  them (`codigo` ascending), each with `codigo`, `estado` and a `total_capturado` badge.
- Seeded data check: the worker sees route `codigo` "10" with badge 2, and routes 20 and
  30 (state `borrador`) **do not appear**.
- Pulling down re-issues the request and refreshes the list.
- `items: []` → explicit empty state, not a blank list and not an error.
- 401 → token message with an action to Ajustes. 403 → wrong-kind-of-token message,
  worded differently from 401. Network failure → cached list, or error state with
  "Reintentar". None of them navigates onward.
- Tapping a route calls `GET /field/capture/route/{route_id}` with that route's id and
  navigates to the resume view.
- The resume view orders by ascending `loc` and shows **`placa` as the leading title**,
  with `orden`/`loc` as secondary metadata; a null `placa` → "Sin dirección aún".
- Reopening a route does not duplicate and preserves local `pending`/`error` captures.
- The opened route becomes the active one and persists after restarting the app.
- The word "congelada" appears nowhere in code or UI copy.
- No coordinate field appears in any request, in storage or in the UI.

## BDD (Gherkin)
```gherkin
Feature: Open and resume route

  Scenario: List the routes assigned to the worker
    Given a field worker authenticated with a field_token from the ESP Isnos
    When they open the route selector
    Then they see route codigo "10" with a total_capturado badge of 2
    And routes in state borrador are not listed

  Scenario: Worker with no assigned routes
    Given the wire answers 200 with an empty items list
    When the worker opens the route selector
    Then they see the empty state "No tienes rutas asignadas en tu ESP"
    And no error is reported

  Scenario: Pull to refresh
    Given the selector is showing a stale list
    When the worker pulls down on the list
    Then the app re-issues GET /field/routes
    And the codigos and badges are refreshed in place

  Scenario: Open a route with captures, address taking the lead
    Given a route with 3 captured units (loc 5, 10, 15)
    When the worker taps that route in the selector
    Then they see the 3 units ordered by ascending loc
    And each unit shows its placa as the title and orden/loc as secondary metadata

  Scenario: Open a verificada route with no captures
    Given a verificada route with no captures
    When the worker opens it
    Then they see the empty state "Ruta sin capturas aún; empieza a capturar"

  Scenario: Expired token
    Given an expired field_token
    When the worker opens the route selector
    Then the API responds 401
    And the app shows "Token vencido o inválido — renuévalo en Ajustes" with an action to Ajustes

  Scenario: A login token instead of a field token
    Given a valid login token that is not of kind field
    When the worker opens the route selector
    Then the API responds 403
    And the app shows "Ese token no es de campo — pide un field_token al operador"

  Scenario: No connection with a cached list
    Given a previously cached route list
    When the request fails on the network
    Then the app shows the cached list with the notice "sin sincronizar (offline)"

  Scenario: Reopening preserves what is pending
    Given a unit captured locally in pending state (not sent yet)
    When the worker reopens the route and the server frame arrives
    Then the pending unit is kept without being overwritten
    And the synced units are updated with placa/loc from the server
```

## Suggested tickets
- **T1.0 (backend) — `GET /field/routes`**: ✅ done, commit `e4e7957` on
  `feature/extended-census`.
- **T1.1 (app) — Route selector, wireframe**: layout with dummy data covering loading /
  list / empty / error / 401 / 403.
- **T1.2 (app) — Route selector, design**: theme pass, no structural or copy change.
- **T1.3 (app) — Resume view**: ✅ wireframe and design done. Wiring pending.
- **T1.4 (app) — DTO + api_client for `GET /field/routes`**: `RouteSummary` DTO,
  `getAssignedRoutes()`, unit tests over the documented payload including
  `nombre: null` and `items: []`.
- **T1.5 (app) — Wire the selector**: real request, local cache (drift), pull-to-refresh,
  navigation to the resume view with the tapped `route_id`.
- **T1.6 (app) — Wire the resume view**: `pullFrame` + `mergeFrame` behind the designed
  screen; persist the active route.
- **T1.7 (app) — Error mapping**: 401/403/404/timeout to their copy and actions.
- **T1.8 (app) — Copy fix**: remove "ruta congelada" from the Home screen hint; the
  domain word is `verificada` (BR2).
