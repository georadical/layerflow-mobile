# Spec: Block faces & route stops (paradas)

> **Mirrored from the backend repo** — read-only reference here. The app
> consumes this layer (does not produce it). App-side work lives in
> [parada-capture-app.md](parada-capture-app.md). Do not edit this copy.

**Type:** [x] Backend/geoprocessing  [ ] UI/dashboard

## User story
As a GIS engineer preparing a census route, I want to generate a "stop" point layer
— one point per **block face**, snapped onto the cadastral block polygon, inheriting
its `manzana_catastral` and receiving a route-ordered sequence — so that every address
captured in the field is bounded to a concrete, ordered face, letting us pair
**manzana + address + route** stably (a base for geocoding QC and cross-census
correspondence).

## Objective
Give the census a reference layer that bounds each `census_code` to a canonical block
face, so coverage, ordering and cross-census matching hold **even when a single
`manzana_catastral` is split across several routes**. The app **consumes** this layer;
it does not compute it (snap + geometry live in QGIS → PostGIS).

## Scope

**Includes:**
- Two entities:
  - **`block_faces`** (spatial, route-agnostic): stable identity of a real face —
    `manzana_catastral`, POINT geometry (MAGNA-SIRGAS), `face_index` (canonical),
    optional `orientation`.
  - **`route_block_faces`** (non-spatial, the *parada*): a route's coverage of a face,
    with `face_sequence` (recorrido order).
- Canonical `face_index` derived from geometry (rule below), stable across census cycles.
- `census_codes.block_face_id` (nullable FK) → the physical `block_faces` row.
- A read/consult surface: list faces per manzana, and stops per route.
- Multi-route sharing of a manzana without clash/block/contradiction.

**Does NOT include:**
- Capturing or editing face geometry / stops **from the app** (produced & edited in QGIS).
- Computing the snap or the `face_index` inside the field write-path (ingestion does it).
- The **geocoding QC check** (flag a predio whose address/placa does not fall on its
  face) — a separate later feature; this spec only lays the data + read layer it needs.
- **Cross-census matching logic** — enabled by stable `face_index`/UUID, but the matching
  algorithm is out of scope here.
- Rendering faces/stops on an in-app map (MVP Streamlit has no map surface).
- Re-keying `localizacion` (loc stays exactly as-is).
- Feeding SUI / LADM_COL regulatory export (internal QC/ordering aid only).

## Actors and permissions
- **GIS engineer** (outside the app, QGIS → PostGIS): creates/edits `block_faces`,
  `route_block_faces`, and sets `census_codes.block_face_id`.
- **platform_operator / tenant users**: **read-only** consult of faces and stops
  (tenant-scoped). No write path in the app.

## Preconditions
- Cadastral block polygons (with `manzana_catastral`) and routes exist in PostGIS,
  projected to MAGNA-SIRGAS (EPSG:4686 / 3116).
- `census_codes` exist for the route (route + loc backbone already in place).

## Trigger
The GIS engineer snaps one stop point per face while preparing a route; an ingestion
step computes `face_index` per manzana and links census_codes to their faces.

## Main flow (happy path)
1. GIS engineer places one point per face of each manzana, snapped to the block polygon.
2. Ingestion computes, **per manzana**, the bearing `manzana_centroid → face point`.
3. The face whose bearing is closest to **North (0°)** gets `face_index = 1`; the rest are
   numbered **clockwise** 2..n (tie-break: smaller clockwise angle / more-Eastern point).
4. Each face is stored as a `block_faces` row: `manzana_catastral`, POINT geom,
   `face_index`, optional `orientation`, stable UUID.
5. For each route that covers a face, a `route_block_faces` row is written with
   `route_id`, `block_face_id`, and `face_sequence` in recorrido order.
6. Each `census_code` on a face gets `block_face_id` set (spatial containment / snap).
7. A user consults `GET .../routes/{id}/stops` (stops in `face_sequence` order) or
   `GET .../manzanas/{manzana_catastral}/faces` (faces in `face_index` order) and sees
   the faces, their canonical index, and which routes cover them.

## Alternative flows (sad paths)
1. **Manzana split across routes.** Route A covers faces of index 1–2, Route B covers
   3–4 of the *same* `manzana_catastral`. Two independent sets of `route_block_faces`
   reference the shared `block_faces`. Neither route's write blocks or contradicts the
   other. Manzana coverage is the **union** of face coverage across routes.
2. **census_code not yet snapped.** `block_face_id` is null. Consult still works; the
   face is reported as *pending snap*, counted as a data-quality gap, not an error.
3. **Face split between two routes (valve).** A face is exceptionally covered by two
   routes (route boundary cuts mid-face). Two `route_block_faces` rows point to the one
   `block_faces`; predios divide by their own `census_code.route_id`. Allowed by the
   model though discouraged by the planning norm.
4. **Ambiguous North (symmetric manzana).** Two faces tie for closest-to-North; the
   documented tie-break (more-Eastern point) resolves it deterministically.

## Business rules
- **BF1 — Two-layer identity.** A face's identity (`block_faces`, incl. geometry and
  `face_index`) is **route-agnostic**; a route's coverage/order (`route_block_faces`,
  `face_sequence`) is route-scoped. `face_sequence` never lives on `block_faces`.
- **BF2 — Canonical index.** `face_index` is derived from geometry only (centroid→face
  bearing; North-closest = 1; clockwise; tie-break East), reproducible by anyone, and
  **stable across census cycles**. Unique per `(tenant, manzana_catastral, face_index)`.
- **BF3 — Manzana is never a route unit.** `manzana_catastral` is a shared, non-unique
  attribute; it is never a uniqueness key per route nor a lock target. Coverage and
  completeness for a manzana are computed at the **face** level, unioned across routes.
- **BF4 — Face coverage keys.** `route_block_faces` is unique per `(route_id,
  face_sequence)` and per `(route_id, block_face_id)`. There is **no** global
  `unique(block_face_id)` — a face may appear under more than one route (BF3 / valve).
- **BF5 — census_code → physical face.** `census_codes.block_face_id` targets the
  physical `block_faces` row (never a `route_block_faces` row); route context already
  comes from `census_codes.route_id`. The FK is nullable.
- **BF6 — App is read-only.** No app endpoint creates/updates/deletes `block_faces` or
  `route_block_faces`; they are reference data ingested via QGIS → PostGIS.
- **BF7 — Orientation is decorative.** `orientation` (N/NE/E/…/NO, nullable) is an
  optional human hint or derivation, never an identity or key.
- **BF8 — i18n naming.** Columns named by function (`block_face`, `route_block_face`,
  `face_index`, `face_sequence`, `orientation`); no route path assumes `manzana ⊂ route`.

## Edge cases and error handling
- **1-face / irregular / >4-face manzana:** one `block_faces` row per real face, n
  arbitrary; ordering by continuous bearing, not four fixed buckets.
- **Point outside its manzana polygon (bad snap):** ingestion-side validation; such a
  face is rejected/flagged at ingestion, not stored as valid.
- **Two stop points on the same face:** ingestion dedupes to one `block_faces` per real
  face (a face has one point).
- **census_code snapped to a face of a different route than its own:** allowed — face is
  route-agnostic (BF5); no contradiction.
- **Null `orientation`:** valid; consult renders it blank.
- **Re-planning between cycles:** `route_block_faces` (route_id, face_sequence) is
  replaced per cycle; `block_faces` identity/`face_index` persist untouched.

## Acceptance criteria
- [ ] `block_faces` and `route_block_faces` tables exist, tenant-scoped, with the
      constraints of BF2 and BF4; `census_codes.block_face_id` is a nullable FK.
- [ ] Given a manzana with n snapped faces, `face_index` is assigned deterministically
      (North-closest = 1, clockwise, tie-break East) and is reproducible on re-run.
- [ ] A `manzana_catastral` split across two routes produces two `route_block_faces`
      sets over shared `block_faces` with no constraint violation.
- [ ] Consult returns faces per manzana ordered by `face_index`, and stops per route
      ordered by `face_sequence`, tenant-scoped.
- [ ] A `census_code` with null `block_face_id` is reported as *pending snap*, not an
      error.
- [ ] No app endpoint can write `block_faces` / `route_block_faces` (read-only).

## BDD (Gherkin)
```gherkin
Feature: Block faces & route stops

  Scenario: Canonical face index from geometry
    Given a manzana with 4 snapped face points
    When the face_index is computed from the manzana centroid bearings
    Then the face closest to North is index 1
    And the remaining faces are numbered clockwise 2..n
    And re-running the computation yields the same indices

  Scenario: One manzana shared by two routes without conflict
    Given manzana "M" whose faces of index 1-2 are covered by route A
    And whose faces of index 3-4 are covered by route B
    When route B's stops are ingested
    Then two route_block_faces sets reference the shared block_faces of "M"
    And no uniqueness constraint is violated
    And manzana "M" coverage is the union of both routes' faces

  Scenario: census_code pending snap
    Given a census_code with block_face_id null
    When a user consults the route's stops
    Then the census_code is listed as pending snap
    And it is not reported as an error

  Scenario: App cannot write the reference layer
    Given an authenticated tenant user
    When they attempt to create or edit a block_face via the API
    Then the request is rejected (no write endpoint exists)

  Scenario: Ambiguous North resolved by tie-break
    Given a symmetric manzana where two faces tie for closest-to-North
    When the face_index is computed
    Then the tie-break (more-Eastern point) assigns index 1 deterministically
```

## Suggested tickets (small stories)
- [ ] **TP.1 — Schema: `block_faces`.** Table (tenant, `manzana_catastral`, POINT geom
      MAGNA-SIRGAS, `face_index`, `orientation` nullable, UUID), with
      `unique(tenant, manzana_catastral, face_index)`. Migration + model. Gate: migration
      applies, insert of a face row round-trips.
- [ ] **TP.2 — Schema: `route_block_faces` + `census_codes.block_face_id`.** Coverage
      table (`route_id`, `block_face_id`, `face_sequence`) with `unique(route_id,
      face_sequence)` and `unique(route_id, block_face_id)`; nullable FK on census_codes.
      Gate: migration applies; a shared face under two routes inserts without violation.
- [ ] **TP.3 — `face_index` function.** Deterministic PostGIS/Python function
      (centroid→face bearing, North-closest = 1, clockwise, tie-break East). Gate: unit
      test over a square manzana and an irregular 5-face manzana returns stable indices.
- [ ] **TP.4 — Consult: faces per manzana.** `GET /consult/manzanas/{manzana}/faces`
      ordered by `face_index`, tenant-scoped, read-only. Gate: endpoint returns expected
      order; cross-tenant isolation test.
- [ ] **TP.5 — Consult: stops per route.** `GET /consult/routes/{id}/stops` ordered by
      `face_sequence`, including each stop's `face_index` and covering route. Gate:
      endpoint returns expected order; a shared-manzana case lists faces under the right
      routes.
- [ ] **TP.6 — Pending-snap indicator.** Surface count of `census_codes` with null
      `block_face_id` per route (data-quality gap). Gate: indicator counts a seeded
      null-face census_code.
