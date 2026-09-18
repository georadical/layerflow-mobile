# Mobile contract — BlockFace, Paradas & parada-scoped placa capture

> **Mirrored from the backend repo** — read-only integration reference. The
> app-side spec built against it is
> [../specs/parada-capture-app.md](../specs/parada-capture-app.md). Do not
> edit this copy.

Integration reference for the field app. Covers two completed backend features:
**block-faces** (`specs/block-faces.md`) and **parada-scoped-capture**
(`specs/parada-scoped-capture.md`).

The app does **not** produce paradas — the GIS engineer generates them in QGIS →
PostGIS. The app **consumes** paradas and **binds** each capture to its face.

## 1. Model

- **`block_face`** — a physical manzana face (route-agnostic): geometry,
  `manzana_catastral`, canonical `face_index` (North/clockwise).
- **`route_block_face`** — the *parada* (route-scoped): `route_id`, `block_face_id`,
  `face_sequence` (recorrido order), `swept`.
- Navigation uses **`face_sequence`**; `face_index` is identity/QC only.
- A manzana may be split across routes without conflict.

## 2. Field endpoints (field token, assignment-scoped)

### a) List a route's paradas — for "current / next parada"
```
GET /field/routes/{route_id}/stops
→ { route_id, items: [{ stop_id, face_sequence, block_face_id, face_index,
     manzana_catastral, orientation, swept, es_actual }] }
```
`es_actual = true` marks the workable parada (lowest `face_sequence` not swept).

### b) Expected placa — the R1 prediction within a face
```
GET /field/routes/{route_id}/stops/{stop_id}/expected-placa?anchor_npn=<npn>&direction=<ascendente|descendente>
→ { manzana_catastral, direction, warning, face_total,
     expected_npn, expected_placa, expected_direccion }
```
- `anchor_npn` = the npn (R1) of the **last captured placa**.
- **First call:** omit `direction` → the backend infers it (min → `ascendente`,
  max → `descendente`, middle → `warning: "esta placa no inicia la cara"`).
  **Store `direction` and pass it on later calls** — otherwise, at the face end it
  would re-flip.
- `expected_placa = null` → end of the face (mark it swept).
- The prediction is READ from R1, never computed (metric-distance gaps are irregular).

### c) Capture a placa (now parada-aware) — `/field/capture/placas` accepts `block_face_id` per item
```
POST /field/capture/placas
body: { route_id, batch_id, items: [
   { client_id, posicion, placa, block_face_id, npn | sin_r1, tipo_acceso, observacion, ins_after } ] }
```
- `block_face_id` must be a parada of the route; the **sweep gate** applies; the
  `manzana_catastral` is taken from the face (authoritative).
- Sets `census_codes.block_face_id` **at capture** (coordinate-free binding),
  preserved on re-carry (omit → keep, like `sin_r1`).
- Out of order → per-item `ok:false, codigo:"barrido_fuera_de_orden"`.
- Omit `block_face_id` → legacy/rural (unassisted) capture.

### d) Mark a face swept / reopen
```
POST /field/routes/{route_id}/stops/{stop_id}/swept   body: { "swept": true | false }
```
- `swept:true` is gated: every lower-`face_sequence` parada must be swept
  (409 `barrido_fuera_de_orden`) **and**, when `foto_obligatoria`, every captured
  placa on the face must have a photo (409 `foto_obligatoria_pendiente`, with
  `localizaciones`).
- `swept:false` = reopen (ungated — the correction path).

## 3. Capture flow (face by face)

1. `GET /stops` → open the `es_actual` parada.
2. First placa: R1 dropdown bounded to the manzana (unassisted). Capture with
   `block_face_id` + `npn`. Photo.
3. `GET /expected-placa?anchor_npn=<npn1>` → store `direction`, show the expected placa.
4. Confirm → capture with `block_face_id` + `npn2` + photo. Repeat with
   `anchor_npn=<npn2>&direction=<dir>`.
5. End of face (`expected_placa=null`) → `POST .../swept {swept:true}`.

## 4. Config & photo

- `foto_obligatoria` (per route, pilot = **true**) **rides down in the resume frame
  and in `/field/routes`**. When true, a face cannot close until every placa on it has
  a photo (`proposito='placa'`).
- The photo still travels via `POST /field/capture/evidence` with `proposito='placa'`.

## 5. New error codes

- `barrido_fuera_de_orden` — capturing/sweeping a parada while earlier ones are unswept.
- `foto_obligatoria_pendiente` — closing a face with photo-less placas (carries
  `localizaciones`).

## 6. Rural / non-urban

Bounding + prediction is **urban** (structured nomenclature). Without it, capture is
free/unassisted — omit `block_face_id` (legacy flow). ~90% of the census runs on
cabeceras municipales with vía principal + generadora + placa.

## 7. Operator consult endpoints (reference — not for the app)

- `GET /consult/routes/{id}/stops` — paradas by `face_sequence`.
- `GET /consult/manzanas/{manzana}/faces` — faces by `face_index` + covering routes.
- `GET /consult/routes/{id}/block-face-coverage` — pending-snap indicator.
- `GET /consult/routes/{id}/sweep-progress` — swept / total + current parada.

## Adjacent (out of scope here)

The office **split-screen verification tool** (foto + captured address, coincide / no
coincide) consumes the mandatory photos — specced separately.
