# Spec — Extended survey with PH/PV expansion (the census pass)

> **Shared spec, mirrored copy** — source of truth in the backend repo
> (`specs/extended-survey-phpv.md`) @ `d2bb861` (pins the app's T8.1 Q1/Q2/Q3:
> Q1=(B) the app always emits a `unidad`; the per-entity `data` shapes; the
> `operaciones`/`resumen` response envelope — on top of CL-E8). Do not edit
> here — changes go through the backend session and get re-copied. App
> tickets: [README.md](README.md), Spec 8.

Status: frozen (mobile observations 0–4 + CL-E1..E7 incorporated 2026-09-13; their index: Spec 8)
Type: Backend (promotion expansion) + app contract → pipeline: Spec → Tickets → Implementation
Consumed by: the capture app (survey UX — its Spec 7+) and office review
Depends on: census-sync (visit/observation push), review/promotion (incr 5),
field-capture-api (placa pass creates the 00/00 units), r1-assisted-capture
(field_confirmed NPN), census-field-operations.md §4 (UX doctrine, DECIDED 2026-07)

## User story
As **a surveyor standing at a captured unit**, I want to run the census form and
**declare the building's structure with buttons** ("agregar piso", "agregar
unidad en este nivel") instead of typing PH/PV codes, so a multi-unit predio
expands into its real units — each with its hogar, connection and meter — and
the office promotes them into official census codes without anyone hand-coding
`01/02`.

## What already exists (this spec builds on, does not rebuild)
- **Transport**: visits/observation_sets/field_responses/media_assets sync via
  `/sync/push|pull` (idempotent, client-generated ids). Untouched.
- **Grouping**: `field_responses` = (entidad_objetivo, instancia, campo, valor);
  promotion already groups `{entidad: {instancia: {campo}}}` — the multi-
  instance dimension exists.
- **Promotion (incr 5)**: promotes premise/hogar/connection/service_point/
  meter for ONE unit, bridges the census_code, matches billing by NUIS,
  quality-issues the rest. TF.1 + BR5 guards active.
- **Doctrine (census-field-operations §4)**: PH/PV never hand-typed; sentinels
  `00/00` unifamiliar and `99/99` totalizador (evidence-only); real units from
  `01`; PH=floor (street=01, up), PV=unit-in-floor (walk order); reclassify
  `00/00` when multi-unit; never mix `00` with `01+`. Separate-unit test:
  independent access is DECISIVE; own meter is NOT a criterion (multiusuario).

## The gap this spec closes
Nothing today turns a declared multi-unit structure into SIBLING census_codes.
The placa pass leaves one `00/00` row per predio; the survey must be able to
expand it to `01/01, 01/02, …` (+ optional `99/99`) at promotion, with every
unit carrying its own hogar/services observations.

## Sync contract for the capture app (PINNED — mobile point 0)
The app has never consumed `/sync/*`; this pin gives it field-capture-api
rigor. Verified against the implementation:

### `POST /sync/push` (field token — require_field, tenant-scoped)
```json
{ "batch_id": "<uuid, app-generated>", "device_id": "opcional",
  "operations": [
    { "entidad": "visit|visit_attempt|observation_set|field_response|media_asset",
      "op": "create|update",
      "id": "<client-owned UUIDv7 — THE identity of the row>",
      "data": { … } } ] }
```
- **Idempotency, two layers:** (a) `batch_id` replay returns the STORED result
  without re-applying (safe retry of the whole push); (b) `create` on an
  existing `id` → `duplicada` (safe re-send of one op). `update` requires the
  row to exist.
- **Response:** per-op `resultado`: `aplicada | duplicada | conflicto | error`
  (+ `motivo`), plus batch counters. Partial semantics like the placa push:
  one bad op never aborts the batch.
- Rules enforced server-side: a `visit` must belong to the pushing worker
  (403-equivalent error per op); an `observation_set` in `en_revision` refuses
  updates (the office took it).
- Ordering within a batch: parents BEFORE children (visit → observation_set →
  field_responses/media) — same chain discipline as CR3.

### Per-entity `data` shapes (PINNED — mobile T8.1 Q2, from the real models)
`data` is whitelisted to the model's columns (id/tenant_id/created_at/updated_at
are server-owned and ignored). Client sends UUIDs/dates as ISO strings.
- **`visit.data`**: `assignment_id`, `census_code_id`, `field_worker_id`
  (must equal the token's worker — else per-op error), `fecha?`, `estado?`
  (default `pendiente`), `observacion?`.
- **`observation_set.data`**: `visit_id` (the FK back to the visit), `estado?`
  (default `borrador`), `observacion?`. The bridge FKs (premise_id, hogar_id,
  …) are populated by promotion, NOT by the app — omit them.
- **`field_response.data`**: `observation_set_id` (FK back to the set),
  `entidad_objetivo` ∈ {premise, hogar, connection, service_point, meter,
  meter_inspection, **unidad**}, `instancia` (int ≥ 1), `campo`, `valor?`.
- **`visit_attempt.data`** (if used): `visit_id`, `fecha_hora`, `resultado`,
  `proxima_visita_fecha?`, `proxima_visita_hora?`, `notificacion_dejada?`,
  `observacion?`.
- **`media_asset` in the survey batch — NOT needed for T8.** The totalizador
  photo travels via `POST /field/capture/evidence` with `proposito=
  'totalizador'` (CL-E4 / TJ.3, already deployed), linked to the ANCHOR unit's
  `client_id` — predio-level evidence "a totalizador exists here". So the T8
  builder can DROP `media_asset`. It stays in the envelope for future
  observation media (e.g. meter-serial photo), which the PH/PV survey does not
  emit. (Promotion's 99/99-requires-photo check reads that anchor-linked
  `proposito='totalizador'` media.)

### Response envelope (PINNED — mobile T8.1 Q3, from `_summary`)
```json
{ "batch_id": "…", "estado": "procesado", "replay": false,
  "resumen": { "total": N, "aplicadas": N, "duplicadas": N,
               "conflictos": N, "errores": N },
  "operaciones": [ { "entidad": "…", "id": "…", "op": "create|update",
                     "resultado": "aplicada|duplicada|conflicto|error",
                     "motivo": "…|null" } ] }
```
- Op-array key is **`operaciones`**. Named counters exist under **`resumen`**
  (no need to derive). `resultado` ∈ exactly {`aplicada`, `duplicada`,
  `conflicto`, `error`}.
- **`codigo`** (the CL-E8 machine code, e.g. `survey_no_autorizado`) is added to
  each op result by **TJ.6** — not present until that lands; absent today.

### `GET /sync/pull?since=<ISO>` (field token)
Returns the worker's frame: assignments + routes (+geometry as WKT — ignore),
census_codes and expected_meters; `since` filters changed rows but route
membership is always complete. The app may keep using `/field/*` for capture
and use pull only to hydrate observation context if needed.

## Model
### The `unidad` entity (observation layer — new)
The app encodes the declared structure as instancias of a new
`entidad_objetivo = "unidad"`:
```
entidad=unidad, instancia=1, campos: ph="01", pv="01",
  acceso_independiente="si|no", tipo_acceso="calle|zona_comun",
  medicion="individual|general", uso="vivienda|local|oficina|otro"
entidad=unidad, instancia=2, campos: ph="01", pv="02", …
entidad=unidad, instancia=99, campos: ph="99", pv="99"   ← totalizador (only
  if it physically exists; requires photo evidence per doctrine)
```
- The APP generates ph/pv from the buttons per the pinned convention (§4);
  the backend VALIDATES, never invents: 01–98 real units, 99/99 only as the
  totalizador instance, no gaps required, no `00` mixed with `01+`.
- Per-unit sub-entities ride the SAME instancia number:
  `entidad=hogar, instancia=2` belongs to unidad 2; same for
  connection/service_point/meter. Predio-level fields (premise) ride
  instancia 1 (the DB CHECK is `instancia >= 1`; there is no instancia 0).
- **Q1 pivot — DECIDED 2026-09-15: option (B), the app ALWAYS emits a `unidad`.**
  A unifamiliar predio emits **one** `unidad` instancia=1 (ph/pv `01/01`) with
  the four CL-E3 answers; a multi-unit predio emits `unidad` 1..N. Rationale:
  the census's atomic object is the unit — every predio has ≥1, so the four
  answers, ph/pv and per-unit sub-entities get ONE uniform home regardless of
  count, and the app's generator has no branch. The **00/00-vs-expand decision
  is the BACKEND's, at promotion** (doctrine: codification lives in the office),
  by counting real `unidad` instances (excluding 99):
  - 1 real unidad → unifamiliar: the anchor **stays `00/00`**; the declared
    `01/01` is NOT applied to the code; the unidad's answers promote onto
    premise/hogar.
  - ≥2 real unidad → expand (§ below): anchor becomes `01/01`, siblings for the
    rest.
- **Backward compatible:** a legacy set with NO `unidad` instances is still read
  as unifamiliar (today's promotion, unchanged) — (B) adds a carrier, it does
  not remove the zero-unidad path.

### Expansion at promotion (backend — the core of this spec)
When an approved set carries unidad instances, promotion additionally:
1. Validates the declared codes (convention above) → violations become
   quality_issues and the set is NOT promoted (`409`, reviewer fixes with the
   field).
2. **Count real `unidad` instances (exclude 99).** With ≤1 → unifamiliar: the
   anchor **stays `00/00`** (the declared `01/01`, if any, is ignored for the
   code); its answers promote onto premise/hogar; no siblings. With ≥2 → the
   anchor row (00/00) **BECOMES the first declared unit** (`01/01`) — its ph/pv
   updated in place. Identity (UUID/client_id), placa, npn, visit and media
   links all survive; the census code Ruta+Loc+PH+PV changes exactly once,
   inside the promotion gate (still pre-publication — same window doctrine as
   shift-insert).
3. Each further unidad creates a **sibling census_code**: same tenant/route/
   localizacion/placa_predio/manzana, **npn inherited** (the predio's link —
   PH units legitimately share it; provenance copied as-is), `client_id NULL`
   (server-born, not app idempotency), ph/pv as declared.
4. The totalizador (99/99), only if declared: sibling row like the others; its
   meter observations promote onto it (the shared general meter).
5. Per-unit sub-entities promote onto THEIR unit's census_code (hogar,
   connection → service_point → meter chain per instancia).
6. One audit record with the full expansion mapping (anchor before→after +
   created siblings).
- Idempotent re-promotion: expansion detects existing siblings (same route,
  loc, ph/pv) and updates instead of duplicating — consistent with today's
  promotion idempotency.
- Guards unchanged and inherited: TF.1 (pending insertions block promotion)
  and BR5 (bridge-linked rows block shifts) keep their order: reconcile →
  NPN → promote/expand.

### Frame invariance post-expansion (PINNED — mobile point 1, verified in code)
`GET /field/capture/route/{id}` is and stays a **placa-pass frame: one row per
captured placa**. Siblings are born with `client_id = NULL` and the frame
filters `client_id IS NOT NULL` → **expanded siblings NEVER appear in it**.
The anchor keeps its `client_id`, its `posicion`/`loc` (unchanged by
expansion) and its `npn`; its mutated ph/pv are NOT in this frame (they never
were). A post-expansion re-push of the anchor updates placa/manzana/obs/
ins_after/npn as always and **never touches ph/pv** (the capture engine only
sets 0/0 on CREATE). No ins_after-style trap: the app's resume model is
untouched.

## PH/PV generation — pinned algorithm (mobile point 2)
Codes are a function of the declared structure, generated by gestures:
```
state: levels = [counts per PH], current_level
"agregar piso"            → PH = max(PH) + 1; current_level = new;
                            creates its first unit (PV = 01)
"agregar unidad" (nivel L) → PV = max(PV in L) + 1
first gesture ever         → replaces the local provisional 00/00 with 01/01
totalizador (gesture apart)→ the 99/99 instance; requires its photo; never
                             part of a level
```
- PH = level index (street = 01, upward); PV = declaration (walk) order within
  the level. Codes are NEVER shown as digits nor editable ("Piso 2 · Unidad
  3", not "02/03").
- **Deletion BEFORE sending: allowed, with local compact renumber** (PV closes
  the gap within its level; removing a level renumbers the PHs above). Legal
  because nothing external references the codes until sent.
- **After sending: immutable from the app.** Corrections go through office
  review (shrink flags, never deletes — see Edge cases). Any change to this
  algorithm is a versioned contract change.

## Instancia semantics (PINNED — mobile point 4)
- `instancia` is app-assigned, a positive int (CHECK `>= 1`), **stable across
  retries** (like client_id: assigned once, never recomputed).
- Scope of uniqueness: **(observation_set, entidad, instancia)** — the app
  must not reuse an instancia within one entidad of one set. Row-level
  idempotency stays on the field_response `id` (create → duplicada).
- Mapping: `unidad` instances are numbered 1..98 in declaration order; **99 is
  reserved for the totalizador**. A sub-entity (hogar/connection/…) with
  instancia N belongs to unidad N. Sets WITHOUT unidad instances keep today's
  semantics (instancia 1 = the single unit) — backward compatible.

## App-side (CL — PINNED with the mobile session; their Spec 8)
- **CL-E1** Survey rail rides the placa-pass frame in strict order; the
  resume list gains a per-unit survey-state chip (sin encuesta / a medias /
  completa); tapping opens the pre-loaded full-screen form (the modal→full
  refactor is the rail's chassis). Unlock in strict order but NEVER blocking
  resume: closing mid-building and returning lands exactly where it was.
- **CL-E2** Local pyramid: observation rows (entidad=unidad, instancia N,
  generated ph/pv) + per-level counter in the form. First "agregar" replaces
  the provisional 00/00 locally. Codes shown as "Piso 2 · Unidad 3", never as
  editable digits.
- **CL-E3** Field wording (pinned verbatim):
  "¿Esta unidad tiene entrada propia, sin pasar por dentro de otra?" (sí/no —
  la decisiva); "¿Por dónde se entra?" (calle / zona común); "¿El servicio se
  mide aparte para esta unidad o con el general del predio?" (individual /
  general). El medidor propio informa sin ser el criterio.
- **CL-E4** Totalizador (99/99) requires its photo — via
  `POST /field/capture/evidence` with **`proposito='totalizador'`** (mobile
  point 3 accepted: same infra, one more enum value, `soporte=divergencia`
  fixed; idempotent per (unit, proposito) so it coexists with the placa
  photo). Never auto-generated.
- **CL-E5** Everything ships through /sync/push chained in the SAME Enviar,
  after placas and evidence (manual-only doctrine); nothing new in transport.
- **CL-E6** Resumable local state: a half-surveyed predio lives in drift
  (never memory-only), bound to the person (CL4), and never travels alone.
  No camera during the survey except the totalizador (battery).
- **CL-E7** Device-side validation of the pinned convention BEFORE sending
  (never mix 00 with 01+, units from 01, 99/99 requires photo): a convention
  409 must be impossible from a healthy app — same philosophy as the
  ins_after guard.

## CL-E8 — Extended-survey lock (backend-owned authorization) — DECIDED 2026-09-15
The survey pass is the error-prone one and may be run by a different, less
experienced surveyor. Gate WHO and WHEN it may run. An app-only lock is theatre
(bypassable, and two devices can't agree from a local flag — the `sin_r1`
multi-device argument). `/sync/push` is the survey write path, so the authority
lives there. Answers to the app's five questions:

1. **`can_survey` is a boolean on `field_worker`, NOT a token scope.** A scope
   would freeze the permission into the 30-day JWT (unrevocable until re-login);
   we built DB-checked field revocation precisely to avoid stale-token
   permissions. The flag is the AUTHORITY when checked at `/sync/push` (live,
   revocable) and merely ECHOED in the login response for offline UX gating.
   `field_workers.can_survey` bool, **default false (fail-closed)**.
2. **Route eligibility is a NEW explicit field, NOT derived from `estado`.**
   `routes.estado` (borrador|verificada) means "the route line is field-verified"
   — a different axis; overloading it couples two concerns (name by function).
   `routes.survey_estado` string (`bloqueada` | `abierta`, **default
   bloqueada**), leaving room for a future `condicionada`. **Survey MAY run
   concurrently with placas**: the backend enforces NO placa milestone — opening
   is a manual operator toggle, so "concurrent vs after-milestone" is operator
   policy, not code.
3. **Capability is per-worker-per-ESP; eligibility is per-route; the
   worker↔route binding already exists via the assignment.** `can_survey` is a
   property of the person-in-ESP (experienced → for all their routes there).
   The route↔worker link is the ASSIGNMENT (a route only appears in
   `/field/routes` if assigned) — no new assignment dimension now. **Effective
   unlock = assigned (pre-existing, invisible to the app) ∧ `can_survey` ∧
   `survey_estado='abierta'`.** From the app's view it is the two flags ANDed;
   the assignment is the silent third factor. A survey-SPECIFIC assignment (pass
   1 swept by worker A, pass 2 surveyed by worker B as routine) is a real future
   extension of the assignment table — recorded, not built (the faro is
   one worker).
4. **Operator provisioning, like `verificada` routes and credentials.**
   `can_survey` on the field-worker maintain endpoint + the unified worker form
   (TG.5's chassis). `survey_estado` a per-route toggle on the route maintain
   endpoint. Both audited via `write_unit`. The operator opens survey per route
   per policy; the backend never auto-derives it.
5. **`/sync/push` error shape:** per-op `resultado="error"` + a NEW stable
   `codigo="survey_no_autorizado"` (machine-mappable) + human `motivo`. Per-op
   (not a request-level 409) to keep partial-batch semantics. Enforced at the
   **visit-create** op (the survey's root — resolve the route via the visit's
   `census_code_id`; a blocked visit fails its children by the parent-before-
   child ordering). Defense in depth even though the app gates the UI offline.

**Hard requirement — the flags ride down (fail-closed):**
- `POST /field/login`: each active-ESP entry gains `can_survey` next to its token.
- `GET /field/routes` and the frame `GET /field/capture/route/{id}`: each route
  gains `survey_estado`.
- If a flag is absent, the app keeps survey LOCKED. So the app gates the survey
  entry before any offline work — never discovering rejection at Enviar.

## Out of scope
- Changes to /sync/* transport or to the placa-pass contract.
- PH/PV re-numbering after promotion (post-census lifecycle rules apply).
- The office review UI beyond what increment 5 already renders (a richer
  unidad-aware review screen can follow as its own ticket once real sets
  exist).
- Media pipeline beyond the placa-evidence path (meter-serial photos reuse
  the observation-layer media as today).

## Edge cases
- Declared unit collides with an existing sibling from a PREVIOUS promotion
  (re-survey): update-in-place (idempotency), never duplicate.
- Anchor already expanded once, new survey declares FEWER units: missing units
  are NOT deleted — a quality_issue flags the shrink for human review
  (destructive changes never ride promotion).
- 99/99 declared without photo evidence → validation issue, set not promoted.
- Unidad instances present but anchor is a lote (es_lote) → validation issue.
- Expansion + shift-insert: expansion happens at promotion, which TF.1 already
  blocks while insertions are pending — no new interaction.

## Acceptance criteria
- A set with unidad instances 01/01, 01/02, 02/01 promotes into: anchor
  mutated to 01/01 (identity preserved), two siblings created, sub-entities
  landing on their own units, one audit mapping.
- Unifamiliar sets promote exactly as today (regression suite green).
- Convention violations (00 mixed with 01+, 99/99 without evidence, duplicate
  ph/pv) → 409 + quality_issues, nothing promoted.
- Re-promotion is idempotent; a shrinking re-survey flags, never deletes.
- Siblings inherit npn + placa; Ruta+Loc+PH+PV unique constraint holds.

## BDD (Gherkin)
```gherkin
Feature: PH/PV expansion at promotion

  Scenario: Three declared units expand the predio
    Given an approved set on a 00/00 unit declaring unidades 01/01, 01/02, 02/01
    When the operator promotes it
    Then the anchor becomes 01/01 keeping its UUID, placa and npn
    And census codes 01/02 and 02/01 exist as siblings with the same loc

  Scenario: Unifamiliar path unchanged
    Given an approved set with no unidad instances
    When the operator promotes it
    Then behavior is identical to increment 5 today

  Scenario: Totalizador requires evidence
    Given a set declaring 99/99 without a photo
    When the operator promotes it
    Then the API responds 409 and a quality issue records the missing evidence

  Scenario: Shrinking re-survey never deletes
    Given a predio expanded to 3 units and a new set declaring 2
    When the operator promotes it
    Then the 2 declared units update and a quality issue flags the third
```

## Suggested tickets
- **TJ.0 — Schema unlocks (migration)**: `field_responses.entidad_objetivo`
  CHECK gains `'unidad'` (found reviewing point 0 — the current CHECK would
  reject every unidad row); `media_assets.proposito` CHECK gains
  `'totalizador'`. Gate: alembic + pytest.
- **TJ.1 — Convention validator**: pure function over grouped unidad instances
  (sentinels, ranges, duplicates, lote, 99/99-evidence, instancia scope).
  Gate: pytest.
- **TJ.2 — Expansion engine in promotion**: anchor mutation + siblings +
  per-instancia sub-entity landing + idempotency + shrink flag + audit
  mapping + frame-invariance regression test. Gate: pytest (the BDD set
  above; regression suite green).
- **TJ.3 — Evidence proposito param** ✅ IMPLEMENTED: `/field/capture/evidence`
  accepts `proposito` ∈ {placa, totalizador} (default placa; totalizador forces
  soporte=divergencia; coexists per unit). Gate: pytest.
- **TJ.5 — Survey-lock flags + ride-down (CL-E8)**: migration
  `field_workers.can_survey` (bool, default false) + `routes.survey_estado`
  (string, default `bloqueada`); expose `can_survey` in `/field/login` per ESP
  and `survey_estado` in `/field/routes` + the capture frame; operator toggles
  on the field-worker and route maintain endpoints (+ worker form + route form),
  audited. Gate: alembic + pytest.
- **TJ.6 — `/sync/push` survey guard (CL-E8)**: reject visit-create when NOT
  (`can_survey` ∧ route `survey_estado='abierta'`) with `resultado="error"`,
  `codigo="survey_no_autorizado"`; add `codigo` to the sync op result contract.
  Gate: pytest (authorized passes, unauthorized worker rejected, closed route
  rejected, placa pass unaffected).
- **TJ.4 — App-side (separate repo, their Spec 8)**: survey rail + structure
  buttons + evidence questions + totalizador photo + sync client
  (CL-E1..E7).
