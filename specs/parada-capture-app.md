# Spec — Parada-scoped capture, app side

Status: draft — decisions Q1–Q3 resolved 2026-09-18 (offline sweep, LOCAL
prediction, foto_obligatoria valve); awaiting approval to start PC.1/PC.2
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

## Decisions (resolved with Jorge 2026-09-18)
1. **Sweep is offline-capable (optimistic-local).** A face MUST be closeable
   offline to unlock the next — the local `swept` mark advances the walk
   immediately and syncs on the next online moment; the field is never stalled
   waiting for the server. The backend gate still enforces server-side on push
   (multi-device: another device cannot skip); if the server later rejects a
   sweep it surfaces as an error to reconcile, but never blocks the walk.
2. **Prediction is LOCAL (a client mirror), not a runtime server dependency.**
   The expected placa is computed ON DEVICE from the cached R1, near-instant
   and offline — the app must not wait on the server to predict. The algorithm
   is the backend's pinned one (PS5–PS7), mirrored like the address normalizer;
   any change to it is a contract change the app follows. The server's
   `expected-placa` endpoint stays as the authority/reference.
   - **Face list:** cached R1 rows of the parada's manzana, parseable, grouped
     by `(tipo_via, num_via, num_cruce, parity)`; `parity = placa mod 2` (the
     two aceras of the same vía+generadora), ordered by placa **numerically**
     (text→int; irregular gaps are irrelevant — it is "next in the ordered
     list", never arithmetic).
   - **Direction from the anchor** (first captured placa): list minimum → asc;
     maximum → desc; middle → unresolved + warning "esta placa no inicia la
     cara" (start at an end). This is the "check placas before/after" step.
   - **Next expected** = the next entry after the anchor in that direction;
     none → end of face → offer "cara barrida".
   - The pieces come from the existing normalizer: `direccionNorm`
     "CALLE 5 # 2-06" → via/num_via(5)/num_cruce(2)/placa(06), parity = 06 mod
     2. No new R1 columns strictly required; the backend may add parsed columns
     later for robustness. Mirror lives beside `address_normalizer`.
3. **`foto_obligatoria` vs the valve — local capture NEVER blocks.** When
   `foto_obligatoria` and the camera works, the aimed shot is required at save
   (cancelling aborts the save — you must shoot). When the camera is genuinely
   dead, the capture still saves (valve), photo-less and flagged; the photo
   obligation is then enforced server-side — the push rejects a photo-less
   capture / the face cannot close (`foto_obligatoria_pendiente`) — until the
   worker re-shoots when the camera is back. Never stall the walk; the face
   just cannot close without its photos.

## Open (app-side, resolved at PC.3/PC.5 design)
4. **`block_face_id` vs `ins_after` coexistence** — a skipped house within a
   face uses shift-insert (`ins_after`); a skipped parada is gated. Confirm
   they coexist unchanged in the push.
5. **Manzana field** — inside a parada the manzana is authoritative from the
   face (the manual field hides on assisted routes); it stays as an override
   for rural/unassisted capture. Finalise in PC.3.

## Tickets (app side; wireframe-first per the workflow)
- **PC.1 — Foundation:** DTOs (`stops`, `expected-placa`, `swept`,
  `block_face_id`, `foto_obligatoria`) + drift (paradas cache, `block_face_id`
  on Captures, `foto_obligatoria` on Routes, per-face `direction`) + providers.
  Tests. (schema bump)
- **PC.2 — Parada rail wireframe:** the face-by-face navigation + capture flow
  states (current/next/swept/locked, predicted placa, end-of-face). Wireframe →
  approval → design → wiring.
- **PC.3 — Capture bound to parada + LOCAL prediction:** `block_face_id` on the
  push (ride-on-every-push), manzana from the face, and the on-device
  expected-placa mirror (face list by `(via,num_via,num_cruce,parity)` ordered
  by placa::int; direction from the anchor; next/end-of-face) with tests against
  the pinned examples; `direction` persisted per face; confirm/"no coincide"
  (finding). The server `expected-placa` stays the authority; runtime is local.
- **PC.4 — foto_obligatoria:** mandatory on-demand shot per capture when true
  (needsDeliberateShot returns true), with the valve behaviour of Decision 3.
- **PC.5 — Sweep (offline-capable):** optimistic-local `swept` that unlocks the
  next parada offline and syncs later; map `barrido_fuera_de_orden` and
  `foto_obligatoria_pendiente`.
- **PC.6 — Coordinated E2E** on a sacrifice route, both sides.

## To verify the happy path
A route with ingested paradas (block-faces done), R1 loaded, `placas_estado=
'abierta'`, `foto_obligatoria=true`, assigned to the worker.
