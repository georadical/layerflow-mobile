# Spec 15 — R1 directory v4 (grouped by placa) + multi-unit capture

> Status: **Draft** — spec phase. Branch `feature/r1-directory-v4`.
> Pipeline: `Spec → Wireframe → Design → Implementation`. The UI barely changes
> (the typeahead already shows addresses); this is mostly data-layer + capture.
> Unblocks the backend's held v4 deploy — ship the parser + APK, then the backend
> cherry-picks v4 (isolated, ~minutes).

## Backend contract (v4, confirmed 2026-10-05)
- **`GET /field/r1-directory`** — each item is now a **PLACA** (collapsed by
  `(manzana, direccion_norm)`, NOT by conjunto flag: local/interior/apto share the
  base `direccion_norm`). Fields per item: `direccion_norm`, `manzana`, the terna
  (`tipo_via`/`num_via`/`num_cruce`), `placa` (the distance), `unidades` (count),
  `es_conjunto` (bool, derived `unidades>1`), **`capturada`** (bool — the placa is
  already captured on a route), and **`units[]`** (the per-unit `npn`/`direccion`
  that used to be flat rows). `version` → `v4` (auto re-download fires on mismatch).
- **`POST /field/capture/placas`** — gains **`direccion_norm`**. A placa of **1
  unit** sends its `npn` (as today). A **multi-unit** placa sends `npn=null` +
  `manzana` + `direccion_norm`. Re-carry `direccion_norm` on every push
  (full-replacement; the frame returns it like `npn`). Idempotency is by
  `client_id`, so `npn=null` never duplicates.
- **`units[]`** (apto/local/interior with ph/pv) are linked LATER, in the survey
  phase (Spec 8) — out of scope here (this is placa capture).

## User story
As a **field worker**, a door with several census units (3 "CALLE 14 # 2-104" =
local 1, interior 1, interior 2) appears in the typeahead **once**, as the placa.
I capture the placa a single time; whether it is one unit or several is the
backend's concern (and the survey's, later). Captured placas drop out of the
typeahead so I never re-offer a done door.

## Objective
Consume the v4 grouped directory and capture at the placa level. One row per placa
locally; a placa with one unit carries that unit's npn, a multi-unit placa carries
none (npn=null) and is identified by `direccion_norm`. Hide `capturada` placas from
the typeahead. The full `units[]` list is **deferred** to the survey phase (Spec 8).

## Scope
### Includes
- New directory DTO parsing the v4 grouped item (placa-level fields + `units[]`),
  keeping the **representative npn** (the single unit's, when `unidades==1`).
- Schema **v22**: `R1Directory` becomes one row per placa (PK `(tenantId, manzana,
  direccionNorm)`, `npn` nullable, + `unidades`/`esConjunto`/`capturada`);
  `Captures` gains `direccionNorm`.
- Capture push: send `direccion_norm`; `npn=null` for multi-unit placas; re-carry
  both under the full-replacement rule; read `direccion_norm` from the frame.
- Typeahead **hides `capturada` placas**; exhaustion (CL-R6) counts non-capturada.
- Prediction: resolve the anchor's terna by **`direccion_norm`** (not only `byNpn`),
  so a multi-unit anchor (npn=null) still predicts.

### Does NOT include
- Storing the full `units[]` list (only the representative npn is kept). The
  per-unit npn/ph/pv for the **survey phase (Spec 8)** is a later ticket.
- Any survey/PH linking of units.
- UI redesign — the typeahead/anchor/distance flows (Spec 13 + AM.8) are unchanged
  except that each placa now shows once and captured ones disappear.
- Backend changes (the v4 contract is the backend's; the app only consumes it).

## Business rules
- **BR-V1 — One row per placa.** Local `R1Directory` holds one row per
  `(manzana, direccion_norm)`. `npn` is the single unit's when `unidades==1`, else
  null. `unidades`, `es_conjunto`, `capturada` are stored per placa.
- **BR-V2 — Capture link by unit count.** On a confirmed R1 link: `unidades==1` →
  send that `npn` (`npn_match_method=field_confirmed`, as today); `unidades>1` →
  `npn=null` + `direccion_norm` (the placa), `sin_r1=false`. The `direccion_norm`
  rides under the full-replacement rule (re-sent on every push; cleared on omit).
- **BR-V3 — Hide captured placas.** A placa with `capturada==true` is NOT offered in
  the typeahead (it is done). Unlike v3's "marked, never hidden" per-npn `enlazado`,
  v4 hides the whole placa — the worker never re-captures a finished door.
- **BR-V4 — Exhaustion by placa.** CL-R6 "manzana agotada" = every R1 placa of the
  manzana is `capturada`. Counts PLACAS, not units.
- **BR-V5 — Prediction survives a multi-unit anchor.** The anchor's face terna is
  resolved from its placa row: by `npn` when it has one, else by `direccion_norm`.
  So prediction (Spec 13/AM.8) works regardless of `unidades`.
- **BR-V6 — Idempotent, coordinate-free, strict order unchanged.** `client_id` is
  the key; `loc=posicion×5`; PH/PV `00`; no coordinates. `npn=null` is valid.
- **BR-V7 — Cache rebuild on migration.** The R1 directory is a disposable
  per-tenant cache (full-snapshot download). The v22 migration MAY drop + recreate
  the `R1Directory` table and clear the stored `version`, forcing a clean v4
  re-download — no data is lost (captures are a separate table).

## Migration (v21 → v22)
- `R1Directory`: drop + recreate with the new shape (PK `(tenantId, manzana,
  direccionNorm)`, `npn` nullable, add `unidades` int, `esConjunto` bool,
  `capturada` bool). Clear the stored R1 `version` so the next refresh re-downloads
  v4 clean.
- `Captures`: `addColumn(direccionNorm)` (nullable text).

## Acceptance criteria
1. After a v4 download, "CALLE 14 # 2-104" (3 units) appears **once** in the
   typeahead; capturing it stores one capture.
2. A single-unit placa capture sends its `npn`; a multi-unit placa sends `npn=null`
   + `direccion_norm`. Both round-trip through the frame.
3. A `capturada` placa does not appear in the typeahead.
4. Prediction works after a multi-unit anchor (terna resolved by `direccion_norm`).
5. The v22 migration upgrades an existing v21 install without losing captures.
6. `flutter analyze` clean, `flutter test` green; live E2E on Pitalito once the
   backend deploys v4.

## Suggested tickets
- **V4.1 — Spec** (this document). Gate: approved.
- **V4.2 — Directory DTO.** `R1DirectoryItem` → placa-level fields + parse `units[]`
  (keep the representative npn when `unidades==1`). `R1DirectoryResponse` unchanged
  shape. Gate: unit test parsing a v4 item (1-unit and multi-unit).
- **V4.3 — Schema v22 + migration.** `R1Directory` reshape, `Captures.direccionNorm`,
  drop/recreate + clear version. Gate: migration test / fresh build green.
- **V4.4 — Directory store + queries.** `replaceR1Slice` writes placa rows; the
  typeahead/prediction queries (`searchR1`, `searchR1Part`, `r1SearchByDistance`,
  `rowsForManzana`, `byNpn`, manzanaStats) adapt to the new shape + hide `capturada`.
  Gate: the Spec 13 + AM.8 scope/distance tests still green.
- **V4.5 — Capture flow.** `appendCapture`/`editCapture` + `PlacaItemRequest` +
  sync + frame carry `direccion_norm`; the capture screen sends `npn` or
  `null+direccion_norm` by `unidades`. Gate: round-trip test.
- **V4.6 — Prediction by direccion_norm.** `paradaCaptureContextProvider` resolves
  the anchor terna by `direccion_norm` when the anchor has no npn. Gate: unit test
  (multi-unit anchor predicts).
- **V4.7 — Tests.** analyze clean, flutter test green.
- **V4.8 — Live E2E + deploy.** Tell the backend the parser+APK are ready; they
  deploy v4; verify on Pitalito (collapsed placa, multi-unit capture, captured
  placa hidden); cross-confirmed cleanup.
