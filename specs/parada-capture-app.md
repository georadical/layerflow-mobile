# Spec — Parada-scoped capture, app side

Status: draft (awaiting approval to implement)
Type: App (UI + local state) consuming a backend contract → pipeline:
Spec → Wireframe → Design → Implementation
Consumes: [../docs/mobile-parada-capture-contract.md](../docs/mobile-parada-capture-contract.md)
(mirrors [parada-scoped-capture.md](parada-scoped-capture.md) +
[block-faces.md](block-faces.md)). Builds on: Spec 3 (batch push), Spec 7
(R1 typeahead), Spec 9 (route-state locks), the on-demand camera.

## User story
As **a surveyor**, I want to sweep my route **face by face (parada) in order**:
each parada shows me only the R1 addresses of its manzana, I capture the placa
I see (confirming the next one the app predicts, or recording a finding when it
does not match), take the required photo, and mark the face **swept** to unlock
the next one — so every address is bound to its real face, in order, with no
skips, and the face↔predio binding is made in the field (coordinate-free).

## Why this is bigger than "scope the typeahead by manzana"
This reworks the placa pass into a **guided, ordered, face-by-face sweep** with
a server-predicted next placa, a server-enforced sweep gate, per-capture face
binding, and (pilot) a mandatory photo. It is the placa pass (pass 1); the
PH/PV survey (Spec 8) is a separate pass with its own lock. The backend owns
the paradas, the prediction, the gate and the photo policy; the app **reflects
and drives** them.

## Scope
**Includes (app side):**
- Consume a route's paradas (`GET /field/routes/{id}/stops`), show the current
  one (`es_actual` = lowest `face_sequence` not swept) and the order.
- Capture bound to the current parada: send `block_face_id` per item on
  `/field/capture/placas`; it rides on EVERY push (omit → keep, like `sin_r1`);
  the `manzana_catastral` comes from the face (authoritative — the app stops
  asking for it inside a parada).
- The expected-placa flow: after the first capture, fetch
  `GET .../stops/{stop_id}/expected-placa?anchor_npn=&direction=`, **store the
  inferred `direction`** and pass it on later calls, show the predicted placa to
  confirm; `expected_placa=null` = end of face.
- Mark a face swept / reopen (`POST .../stops/{stop_id}/swept`), with the gate
  errors mapped.
- `foto_obligatoria` (rides in the frame + `/field/routes`): when true, a photo
  is required per capture.
- Local persistence of paradas, per-face `direction`, `block_face_id` and
  `foto_obligatoria`, so the flow degrades gracefully offline.

**Does NOT include:**
- Producing/editing paradas or block-face geometry (QGIS → PostGIS).
- Computing `face_index`, snapping, or the `expected-placa` prediction (server;
  the app reads it).
- The office split-screen verification tool (a separate office feature fed by
  the mandatory photos).
- The PH/PV survey (Spec 8).
- An in-app map.

## What the app consumes (contract, pinned by the backend)
- `GET /field/routes/{id}/stops` → `items[{ stop_id, face_sequence,
  block_face_id, face_index, manzana_catastral, orientation, swept,
  es_actual }]`. Navigation uses `face_sequence`; `face_index` is identity/QC.
- `GET .../stops/{stop_id}/expected-placa?anchor_npn=<npn>&direction=<asc|desc>`
  → `{ manzana_catastral, direction, warning, face_total, expected_npn,
  expected_placa, expected_direccion }`. First call omits `direction` (backend
  infers: min→asc, max→desc, middle→`warning "esta placa no inicia la cara"`);
  the app MUST store and re-send it, or it re-flips at the face end.
- `POST /field/capture/placas` — items now carry `block_face_id`; the sweep gate
  applies; out of order → per-item `ok:false, codigo:"barrido_fuera_de_orden"`;
  omit `block_face_id` → legacy/rural (unassisted).
- `POST .../stops/{stop_id}/swept {swept:true|false}` — `true` gated (all
  lower-sequence paradas swept → else 409 `barrido_fuera_de_orden`; and, when
  `foto_obligatoria`, every placa on the face photographed → else 409
  `foto_obligatoria_pendiente` with `localizaciones`); `false` reopens (ungated).
- `foto_obligatoria` (per route) in the frame and `/field/routes`.

## Local persistence (drift)
- **Paradas per route** (cache of `/stops`): stop_id, face_sequence,
  block_face_id, face_index, manzana, orientation, swept — refreshed on open
  like the frame, so navigation works offline with the last-known state.
- **`direction` per face** (inferred once, stored, re-sent on expected-placa).
- **`block_face_id` on Captures** — rides on every push (full-replacement,
  omit → keep, like `sin_r1`/`npn`).
- **`foto_obligatoria` on Routes** — persisted like the Spec 9 locks.

## Camera reconciliation (with the on-demand change)
The on-demand camera stays (no persistent viewfinder — battery). Under
`foto_obligatoria=true` the shot becomes **required per capture**:
`needsDeliberateShot` returns true whenever `foto_obligatoria`, so the aimed
shot is forced (as divergence already forces it), still started on demand and
released after. This is exactly the "on-demand architecture, optionality
changes" note from the camera change. The hardware-valve tension (a dead
camera vs a mandatory photo) is an open question below.

## UI states (to wireframe)
- **Parada rail:** the route's paradas by `face_sequence`, the current one
  highlighted, swept ones marked, locked ones (higher sequence) shown locked.
- **Capture within a parada:** manzana shown (from the face, read-only), R1
  dropdown bounded to it (first placa); then the **predicted next placa** to
  confirm, with a "no coincide" path (finding).
- **End of face:** `expected_placa=null` → a "cara barrida" action.
- **Sweep gate / photo-pending:** clear messages for
  `barrido_fuera_de_orden` and `foto_obligatoria_pendiente` (name the pending
  `localizaciones`).
- Offline: the predicted-placa step falls back to the manzana-scoped typeahead.

## Open questions to validate BEFORE building
1. **Sweep + manual-only sync.** Capture data travels only on Enviar
   (manual-only doctrine). But the sweep gate is server-enforced and
   `expected-placa` is a live server call. Is marking swept an **immediate**
   online call (like the R1 refresh, exempt from manual-only), or queued? What
   happens when the worker finishes a face **offline** — can they mark it swept
   locally (optimistic) and it syncs later, or is swept online-only? A whole
   face captured offline still needs to unlock the next parada.
2. **Offline `expected-placa`.** It is server-side (reads R1). Offline, the app
   falls back to the local manzana-scoped typeahead (cached R1) — confirm this
   is the intended degrade (capture never blocks), and whether the app should
   try to predict locally from the cached R1 or simply drop to manual.
3. **`foto_obligatoria` vs the hardware valve.** Capture must NEVER block
   (offline-first law), yet `foto_obligatoria` rejects a photo-less capture. If
   the camera is dead under `foto_obligatoria`, does the app (a) block the
   capture, (b) save it photo-less and let the push/swept reject it, or (c)
   allow it and surface the face as photo-pending? Decide the field behaviour.
4. **Order of `block_face_id` vs `ins_after`.** A skipped house within a face
   uses shift-insert (`ins_after`); a skipped parada is gated. Confirm the two
   coexist unchanged.
5. **Manzana field.** Inside a parada the manzana is authoritative from the
   face. Does the manual manzana field disappear entirely on assisted routes,
   or stay as an override for rural/unassisted capture?

## Tickets (app side; wireframe-first per the workflow)
- **PC.1 — Foundation:** DTOs (`stops`, `expected-placa`, `swept`,
  `block_face_id`, `foto_obligatoria`) + drift (paradas cache, `block_face_id`
  on Captures, `foto_obligatoria` on Routes, per-face `direction`) + providers.
  Tests. (schema bump)
- **PC.2 — Parada rail wireframe:** the face-by-face navigation + capture flow
  states (current/next/swept/locked, predicted placa, end-of-face). Wireframe →
  approval → design → wiring.
- **PC.3 — Capture bound to parada:** `block_face_id` on the push (ride-on-every
  -push), manzana from the face, expected-placa fetch + `direction` persistence
  + confirm/"no coincide" (finding).
- **PC.4 — foto_obligatoria:** mandatory on-demand shot per capture; resolve the
  hardware-valve question (Q3).
- **PC.5 — Sweep:** mark swept / reopen; map `barrido_fuera_de_orden` and
  `foto_obligatoria_pendiente`; resolve the offline-sweep question (Q1).
- **PC.6 — Coordinated E2E** on a sacrifice route, both sides.

## To verify the happy path
A route with ingested paradas (block-faces done), R1 loaded, `placas_estado=
'abierta'`, `foto_obligatoria=true`, assigned to the worker.
