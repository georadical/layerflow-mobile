# Spec — Parada-scoped capture, app side

Status: in progress — decisions Q1–Q3 resolved 2026-09-18 (offline sweep, LOCAL
prediction, foto_obligatoria valve); **Decisions v2 pinned with the backend
2026-09-22** (compose-on-read, every point is a parada, binding by `stop_id`,
terna on the parada, three capture modes). PC.1a/PC.1b/PC.2/PC.3 done;
PC.3b next.
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

### Walkthrough — Marta sweeps Ruta 10

Marta is a surveyor in Isnos. Today's Ruta 10 has five paradas: three faces of
manzana 001, a finca on the way out, and one face of manzana 002. She starts at
7am with no signal for most of the day.

**1. She opens the route and sees ONE walk, not two lists.** The app shows five
paradas **in order** — the finca is not filed under "the rural section"; it is
parada 4, between 3 and 5, exactly where she reaches it on foot (**Decision
5** — every point of the route is a parada; **Decision 6** — capture binds to
`stop_id`, which is what makes a face-less parada representable at all).

**2. First door of face 1: she types two digits.** The app already knows she is
on CARRERA 2, generadora 4 — the preview reads `CARRERA 2 # 4-__`. The door
says **09**. She types `09`. Nothing else: no vía, no `#`, no dash (**Decision
4** — only the distance changes along a face; **Decision 7** — the terna lives
on the parada, so the backend prepends it and composes).

**3. Second door: the app already knows what is next.** From the cached R1
(`09, 15, 23, 41`) and her anchor at the minimum, the direction resolves to
ascending and a card appears: *Siguiente esperada — CARRERA 2 # 4-15*. The door
says 15. She taps **Coincide** (**Decision 2** — prediction is local and
offline; the next entry is "next in the ordered list", never `+6` arithmetic).
Had she started mid-face, the app would have refused to guess a direction
("esta placa no inicia la cara") rather than flip a coin.

**4. Third door: something is off.** The door reads **14**. A soft banner
appears: *"Esta cara es impar, pero la distancia que escribiste es par. Revisa
la acera — se guarda igual."* Marta realizes she crossed the street — or, if
the plate genuinely says 14 (bad plaqueo happens), she keeps it anyway
(**Decision 10** — parity warns, never blocks; what she sees governs).

**5. Fourth door: a house the R1 does not know.** The app expects `23`; between
15 and 23 there is an unlisted door. She taps **No coincide**, types the
distance she sees, and it is recorded as a **finding** — the anchor does not
move, so prediction keeps resuming from 15, unaffected.

**6. The list runs out, the face does not.** *Fin de la cara* appears, but one
more house sits past the last plate, unnumbered. She captures it, THEN closes
the face (**Decision 9** — the surveyor closes, not the algorithm; had closing
required exhausting a prediction, parada 4 — the finca, with no R1 list at all
— could never close and the walk would stall). Closing unlocks parada 2 at
once, offline (**Decision 1** — the sweep is optimistic-local).

**7. Parada 4: the finca.** This parada carries no terna — there is no vía or
generadora to prepend. The field itself changes to **"Nombre del predio"**: no
preview, no prediction, no parity check. Marta types `FINCA CANAÁN`, stored
verbatim (**Decision 8** — three capture modes, chosen by the parada, never by
a manual toggle: Colombian rural addresses are topónimos, not vía+generadora+
distancia — ~32% of the national R1 by the backend's own measurement, not an
edge case).

**8. What is still open.** A corner house in manzana 002 carries two plates
(`K 6B 2 04` / `C 2AS 5A 19`) — captured once or twice? Diagnosed and
catalogued (§ Open, item 12) but deferred: low volume, not blocking the pilot.

In one line: Marta looks at the plate and types what it says; the app supplies
the context, the backend supplies the address, and the parada sequence — urban
and rural alike — guarantees the order of the walk.

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

## Decisions v2 — compose-on-read + paradas sin cara (backend, 2026-09-22)

Pinned after a round with the backend. Supersedes the parts of §2 and §5 that
assumed every parada has a manzana face and that the worker types an address.

4. **The worker types ONLY what the plate says.** A face fixes
   `(tipo_via, num_via, num_cruce)` — vía and generadora are constant along a
   block side; the only thing that varies door to door is the **distance to the
   corner**. So the app sends the distance alone and the **backend composes**
   `{tipo_via} {num_via} # {num_cruce}-{distancia}` (the dash is never typed).
   `placa_predio` stores what was typed **verbatim**; the full normalized
   address is composed **on read** — no redundant column, no drift.
5. **EVERY point of the route is a parada.** A rural predio in any stretch also
   gets its parada: order and sequence hold for the whole route, manzana or not.
   There is NO free mode and NO manual toggle — the app is in parada mode the
   whole way, and `GET /stops` lists **all** paradas (urban and rural) in one
   ordered sequence. (This replaced an earlier backend proposal of an
   urban/rural mode switch; a sticky mode is state the worker forgets, and a
   capture made in the wrong mode silently loses its binding.)
6. **The parada is the binding, not the face.** `block_face_id` is **nullable**
   on a parada (a rural one has no face), so the capture binds by **`stop_id`**
   in both the row and the push; the face is derived from the parada when it
   exists. `block_face_id` stays accepted for compatibility.
7. **The terna lives on the PARADA, and is nullable.** It is what the worker
   visits and what composition runs against. No duplication results: the app's
   prediction groups from the **R1 parsed columns** directly, so the face needs
   no terna of its own — the parada's is only for compose/preview. The backend
   derives the urban terna from that same R1 source (a free consistency check;
   if they diverged, preview and prediction would contradict each other on
   screen).
8. **Three capture modes, chosen per parada — never by the worker.**
   - **Parada with terna (urban)** → guided: R1 prediction, the worker types
     the **distance only**, live preview `CALLE 13 # 3A-__`, backend composes.
   - **Parada with terna NULL (rural)** → **free text**: Colombian rural
     addresses are **topónimos** (`LA ESPERANZA`, `FINCA CANAÁN`), not
     vía+generadora+distance — there is nothing to compose. Field labelled
     "Nombre del predio", stored **verbatim**, no prediction, no composition,
     no parity check. (Backend measured ~32% of 6.8M national R1 rows as pure
     topónimo, `parse_ok=false` — which is why the face list filters on
     `parse_ok`: that third must never be mis-grouped into a face.)
   - **Route with no paradas** → the classic pre-Spec-10 flow, unchanged.
9. **A parada closes on the worker's judgement.** Closing must be available
   whenever a parada is open — NOT gated on exhausting the R1 prediction, or a
   parada without a face could never be closed and the sequence would stall at
   the first rural point. The server still validates on push.
10. **Acera parity is a soft warning.** A face is one acera (all even or all
    odd). A typed distance of the other parity warns — the worker may be on the
    wrong side or the plate may be odd — but never blocks: "se guarda tal cual".

## Open (app-side)
11. **`block_face_id`/`stop_id` vs `ins_after` coexistence** — a skipped house
    within a face uses shift-insert (`ins_after`); a skipped parada is gated.
    Confirm they coexist unchanged in the push.
12. **Double-frontage corner predios** (`K 6B 2 04 S C 2AS 5A 19`) — DIAGNOSED
    2026-09-22, deferred (not blocking the pilot; ~11 rows in Isnos, 1.53%
    national). Not a PH case (addressing artifact, one predio two streets —
    independent from the PH/PV legal/physical axis, still decided purely by
    field observation). Resolution path (backend-side, reuses existing
    mechanisms, nothing new): split the R1 row into two same-NPN rows tagged
    "derivada de esquinero" — only when BOTH halves are complete ternas (a
    lone letter must never read as a second frontage — a documented false
    positive); capture happens ONCE, on whichever face the worker visits
    first; the OTHER face's row auto-shows `enlazadoLoc` (already keyed by
    NPN, not by row — no app change) and the app's existing duplicate-NPN
    banner (CL-R3) already reads as "ya capturado" without a dedicated
    "confirmar" affordance. The one real gap — a face's sweep/foto_obligatoria
    completeness gate must count an NPN enlazado-from-another-face as
    resolved, not pending — is a BACKEND-side gate (Decision 9 already means
    the app never locally gates a close on completeness). Future polish ticket
    only: a "confirmar" affordance on the 2nd face instead of "capturar",
    if/when volume warrants it.

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
- **PC.3b — Compose-on-read + paradas sin cara (Decisions v2):** schema bump —
  nullable `block_face_id` on the parada, the terna on the parada, `stop_id` on
  the capture and the push. Capture input becomes **distance-only + live
  preview** on a parada with terna, and **free-text "Nombre del predio"**
  (verbatim, no prediction/composition/parity) on a parada without one. Parada
  close available whenever a parada is open (no longer gated on end-of-face).
- **PC.4 — foto_obligatoria:** mandatory on-demand shot per capture when true
  (needsDeliberateShot returns true), with the valve behaviour of Decision 3.
- **PC.5 — Sweep (offline-capable):** optimistic-local `swept` that unlocks the
  next parada offline and syncs later; map `barrido_fuera_de_orden` and
  `foto_obligatoria_pendiente`.
- **PC.6 — Coordinated E2E** on a sacrifice route, both sides.

## To verify the happy path
A route with ingested paradas (block-faces done), R1 loaded, `placas_estado=
'abierta'`, `foto_obligatoria=true`, assigned to the worker.
