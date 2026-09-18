# Spec: Parada-scoped placa capture (levantamiento acotado por parada)

> **Mirrored from the backend repo** — read-only reference here (the backend
> contract + state). The app-side spec that consumes it is
> [parada-capture-app.md](parada-capture-app.md); the integration contract is
> [../docs/mobile-parada-capture-contract.md](../docs/mobile-parada-capture-contract.md).
> Do not edit this copy.

**Type:** [x] Backend/geoprocessing  [ ] UI/dashboard
<!-- Backend contract + state that enables the field app. App UI is built by the mobile team against this contract. -->

## User story
As a surveyor capturing placas in the field with the app, I want to sweep my route
**face by face (parada) in unambiguous order** — each parada shows me the R1 addresses
bounded to its manzana, I capture the placa I see (confirming the suggested next
address from R1, or recording a finding when it does not match), and I mark the face
**swept** to unlock the next parada — so that every address is bounded to its real face,
in order, without skips or ambiguity, and the face↔predio binding is made in the field
(coordinate-free).

## Objective
Turn the block-face/parada reference layer into a guided field sweep: bound each
capture to a face at capture time, drive an ordered no-skip navigation gated by a
per-face "swept" flag, and accelerate/validate capture by predicting the next expected
placa from R1's own ordered address list. Precision (right face, right order) and speed
(confirm instead of type) at once.

## Scope

**Includes:**
- **Sequential sweep** of a route's paradas in `face_sequence` order, one at a time.
- **Swept gate** (`route_block_faces.swept`): the next parada is unlocked only when the
  current one is marked swept; enforced in the BACKEND (multi-device).
- **Capture binding (Model B):** each captured census_code carries `block_face_id` of
  the current parada, set at capture — coordinate-free, authoritative.
- **R1 expected-placa prediction** within a face: after the first capture, the backend
  suggests the next address from R1's ordered list for that face.
- **Direction inference** (ascending/descending) from where the first placa sits in the
  face's R1 list.
- **Parity = acera** as an address-logic discriminator.
- **`foto_obligatoria`** config (campaign/route level); pilot default True.
- **Field-token read access** to a route's paradas (auth adjustment on the existing
  consult, scoped to assignment).

**Does NOT include:**
- Ingestion of paradas / block-faces (block-faces spec) or capture of geometry in the app.
- Re-keying `localizacion` (loc stays route-wide; face_sequence groups, never replaces).
- The extended PH/PV survey (its own CL-E8 lock) — this is the **placa pass (pass 1)**.
- The office **split-screen verification tool** (coincide/no coincide over the mandatory
  photos) — an adjacent office feature, fed by this one, specced separately.
- **Rural / unstructured capture:** parcels without urban nomenclature use the existing
  unassisted / `sin_r1` flow; prediction and parity apply to urban manzanas only.
- Auto-correction of R1: a mismatch is recorded as a finding, never overwrites R1.

## Actors and permissions
- **Surveyor** (field token, kind='field'): reads the paradas of their assigned routes,
  captures placas bound to a parada, marks a face swept / reopens it.
- **platform_operator**: reads sweep progress; may reopen a face; sets `foto_obligatoria`.
- **GIS engineer** (outside app): produced the paradas (block-faces spec) — precondition.

## Preconditions
- The route has paradas ingested (`route_block_faces` with `face_sequence`, each → a
  `block_face` with `manzana_catastral`), block-faces spec.
- R1 (`cadastral_reference`) loaded for the tenant, with parsed address columns
  (`tipo_via`, `num_via`, `num_cruce`, `placa`, `manzana_catastral`, `parse_ok`).
- Route `placas_estado = 'abierta'` (the placa-pass lock still applies) and the worker is
  assigned.

## Trigger
The surveyor selects an assigned route and opens its first (or current) parada.

## Main flow (happy path)
1. Surveyor selects route 10; the app lists its paradas by `face_sequence`; the current
   parada = the lowest-sequence face not yet `swept`.
2. Surveyor opens parada 1; the app shows R1 addresses bounded to that parada's
   `manzana_catastral` (manzana-assisted).
3. **First capture (unassisted by intersection):** surveyor reads the placa, picks the
   matching R1 suggestion from the dropdown (or `sin_r1`), takes the photo (mandatory
   when `foto_obligatoria`), saves. The census_code is bound to `block_face_id` = parada.
4. From the first placa the backend derives the **face list**: R1 rows matching
   `(manzana_catastral, tipo_via, num_via, num_cruce, parity)`, ordered by `placa`
   numerically. It infers **direction**: first placa at the list minimum → ascending;
   at the maximum → descending.
5. **Next capture (assisted):** the app shows the **expected placa** = the next entry in
   the face list in the inferred direction. Surveyor confirms it matches, takes the
   photo, saves — no typing. Repeat down the face.
6. When the face is fully walked, surveyor taps **"cara barrida"**; the backend marks
   `route_block_faces.swept = true` and unlocks parada 2 (same or next manzana of the route).
7. The route is complete when all its paradas are swept.

## Alternative flows (sad paths)
1. **Mismatch → finding (submit via the "no coincide" path).** The expected placa does
   not match what the surveyor sees. They record the actual placa (typed or a different
   R1 pick, or `sin_r1`), take the evidence photo; the capture is flagged as a
   discrepancy for office review. R1 is never overwritten.
2. **Descending face.** The first captured placa is the list maximum → direction
   descending; expected placas count down. Same confirm flow.
3. **First placa not an endpoint (warn).** The first captured placa sits in the middle
   of the face list (placas exist both before and after) → the app warns "esta placa no
   inicia la cara" and asks the surveyor to start at an end; the capture is still saved
   but direction stays unresolved until an endpoint anchors it.
4. **Skip guarded at parada granularity.** The surveyor tries to open parada 3 while
   parada 2 is not swept → backend rejects (409, gate). A skipped *house within a face*
   is not blocked: it uses the existing shift-insert (`ins_after`).
5. **Reopen a swept face.** A missed placa is found after marking swept. The surveyor
   (or operator) reopens the parada (`swept = false`), captures, re-marks swept.
6. **Rural / no nomenclature.** The parcel has no structured address (`tiene_direccion`
   false) → prediction/parity are off; capture is free/unassisted (`sin_r1`), still
   bound to the parada if one exists, else unbound.
7. **`parse_ok = false` R1 row** (a placa range like "105 107") → not offered as an
   expected placa; the surveyor captures manually.

## Business rules
- **PS1 — Sweep gate (backend, multi-device).** `route_block_faces.swept` (default
  false). A capture or open on parada N is allowed only if every parada with a lower
  `face_sequence` on the route is `swept`. Enforced server-side (like CL-E8), so two
  devices on the same route cannot skip ahead.
- **PS2 — Swept is face state, not per-worker.** The flag lives on the `route_block_face`;
  either assigned worker advances the same shared sweep.
- **PS3 — Binding at capture (Model B).** The captured census_code's `block_face_id` is
  the current parada's `block_face`. `manzana_catastral` is taken from that block_face.
- **PS4 — loc is untouched.** `localizacion` (posición×5) stays route-wide sequential;
  face_sequence groups, never re-keys; a face's census_codes need not be contiguous in loc.
- **PS5 — Expected placa is READ from R1, never computed.** The suggestion is the next
  entry in the face list, ordered by `placa` **numerically** (the column is text — cast
  to int). Irregular gaps (04→08→16) are irrelevant because nothing is arithmetic.
- **PS6 — Face list key.** R1 rows filtered by `(manzana_catastral, tipo_via, num_via,
  num_cruce, parity)`, `parse_ok = true`. Parity = `placa mod 2` — it separates the two
  aceras that share vía + generadora (which are also distinct manzanas).
- **PS7 — Direction from the anchor.** First placa at the face-list minimum → ascending;
  at the maximum → descending; in the middle → unresolved + warning (PS/flow 3).
- **PS8 — Mismatch is a finding, never a correction.** A "no coincide" capture records
  the surveyor's observation + photo and flags a discrepancy; R1 is immutable here.
- **PS9 — Photo policy is configurable.** `foto_obligatoria` (campaign/route); pilot
  default True. When true, a capture without a photo is rejected. The mandatory photos
  feed the office verification tool (out of scope).
- **PS10 — Coexists with the placa-pass lock.** The sweep runs only while
  `placas_estado = 'abierta'`; closing the route freezes paradas too.
- **PS11 — Urban only.** Prediction/parity apply to rows with structured nomenclature;
  rural/unstructured parcels fall back to unassisted capture (~10% of the census).
- **PS12 — i18n.** Columns by function (`swept`, `block_face_id`, `face_sequence`);
  `manzana_catastral` stays catalog-style; no route path assumes `manzana ⊂ route`.

## Edge cases and error handling
- **Corner lot / double frontage** (address on both vía and generadora): ambiguous face;
  flag for manual assignment, do not auto-bind to a guessed face.
- **First parada of a route with no R1 rows** (all rural): sweep still works as a plain
  ordered gate; prediction is simply empty.
- **Two workers, one route**: the shared `swept` flag means one worker's mark unlocks the
  next parada for both — intended (PS2); a capture racing the gate is resolved by the
  server check at push time.
- **Photo required but missing** (`foto_obligatoria` true): capture rejected with a clear
  code, not silently accepted.
- **R1 incomplete for a face**: an early placa may look like the minimum falsely →
  ascending inferred wrongly; degrades to more mismatches (findings), never blocks.
- **Reopening a face that fed downstream promotion**: reopening only clears `swept`; it
  does not delete captured census_codes.

## Acceptance criteria
- [ ] `route_block_faces.swept` exists (default false); the backend rejects opening/
      capturing on a parada whose lower-sequence siblings are not all swept.
- [ ] A capture carries `block_face_id`; the stored census_code is bound to it and its
      `manzana_catastral` matches the parada's block_face.
- [ ] The expected-placa endpoint returns the next R1 address for the face, ordered by
      `placa` numerically, filtered by parity, respecting inferred direction.
- [ ] A first placa at the face-list minimum yields ascending; at the maximum, descending;
      in the middle, an "no inicia la cara" warning.
- [ ] Marking a face swept unlocks the next parada; reopening restores it without deleting
      captures.
- [ ] With `foto_obligatoria` true, a capture without a photo is rejected.
- [ ] The field token can read its assigned route's paradas; cross-assignment is denied.
- [ ] A rural parcel (no structured address) captures unassisted, still bindable to a parada.

## BDD (Gherkin)
```gherkin
Feature: Parada-scoped placa capture

  Scenario: Expected placa is the next R1 address, ascending
    Given the surveyor is on a parada whose R1 face list is [09, 15, 23, 41] (odd side)
    And the first captured placa is 09 (the list minimum)
    When the surveyor asks for the next expected placa
    Then the backend returns 15
    And the direction is ascending

  Scenario: Descending face
    Given the R1 face list is [04, 08, 16, 74] (even side)
    And the first captured placa is 74 (the list maximum)
    When the surveyor asks for the next expected placa
    Then the backend returns 16
    And the direction is descending

  Scenario: First placa in the middle warns
    Given the R1 face list is [09, 15, 23, 41]
    When the first captured placa is 23
    Then the app is warned "esta placa no inicia la cara"
    And the direction stays unresolved

  Scenario: Sweep gate blocks skipping a parada
    Given parada 2 of the route is not swept
    When the surveyor tries to capture on parada 3
    Then the backend rejects it with the sweep-gate code
    And parada 3 stays locked

  Scenario: Mark swept unlocks the next parada
    Given the surveyor finished parada 1
    When they mark the face swept
    Then route_block_faces.swept becomes true for parada 1
    And parada 2 is unlocked

  Scenario: Mismatch is recorded as a finding
    Given the expected placa is 15
    When the surveyor sees a different placa and chooses "no coincide"
    Then the actual observation and photo are stored as a discrepancy
    And R1 is not modified

  Scenario: Photo required
    Given foto_obligatoria is true for the route
    When the surveyor saves a capture without a photo
    Then the capture is rejected
```

## Suggested tickets (small stories)
- [ ] **PS.1 — Schema: `route_block_faces.swept`** (boolean, default false) + reopen. Gate:
      migration applies; toggling round-trips.
- [ ] **PS.2 — Sweep gate at capture/open.** Server check: a parada is workable only if all
      lower-`face_sequence` paradas on the route are swept; reject otherwise (409 + code).
      Gate: test blocks parada 3 while 2 unswept; unlocks after sweeping 2.
- [ ] **PS.3 — Capture binding (Model B).** `/field/capture/placas` accepts `block_face_id`;
      sets it on the census_code; derives `manzana_catastral` from the block_face. Gate:
      captured code is bound; manzana matches.
- [ ] **PS.4 — Field-token access to paradas.** Expose a route's paradas to the field
      token, scoped to assignment (ordered by face_sequence). Gate: assigned worker reads;
      unassigned denied.
- [ ] **PS.5 — Expected-placa endpoint.** Given a parada + last captured placa, return the
      next R1 address (face list by `(manzana, tipo_via, num_via, num_cruce, parity)`,
      ordered by `placa::int`, `parse_ok`), with inferred direction and the middle-start
      warning. Gate: ascending/descending/middle cases over seeded R1.
- [ ] **PS.6 — `foto_obligatoria` config + enforcement.** Config at campaign/route
      (pilot default true); reject photo-less capture when true. Gate: rejected without
      photo, accepted with.
- [ ] **PS.7 — Sweep progress indicator.** Per route: paradas swept / total (+ current).
      Gate: reflects a seeded partial sweep.
