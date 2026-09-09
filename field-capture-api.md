# Spec — Minimal field-capture API (placa capture in strict order)

> **Copy — source of truth lives in the backend repo** @ `edf0f4f`
> (branch `feature/extended-census`). Field rename applied there:
> `posicion` → `posicion` (deprecated alias accepted during a compatibility
> window). This mirror was updated accordingly; do not edit doctrine here.

Status: draft (awaiting approval to implement)
Type: Backend / API (no UI) → pipeline: Spec → Tickets → Implementation
Consumed by: the custom capture app (built in a separate session)
Depends on: census backbone (routes, census_codes), npn-matching-engine (T3)

## User story
As **LayerFlow's field team using the capture app**, I want an endpoint to push
**placas + accesses captured in strict route order**, which **creates the
`census_code` units** (`loc = posicion × 5`, `ph/pv = 00`), tenant/route-scoped and
idempotent, so the app has a concrete backend contract and the units feed the
address→NPN engine. **No coordinates are captured.**

## Objective
Give the custom app a minimal, stable contract to register the census units of a
route from a coordinate-free placa pass. This is the input the matching engine
(T3) and, later, the extended survey (T5) build on.

## Scope
**Includes**
- `POST /field/capture/placas` — batch push of ordered placas → upserts census_codes.
- `GET /field/capture/route/{route_id}` — pull the route frame (already-captured
  units) so the app can resume.
- A `client_id` column on `census_codes` for idempotency.

**Does NOT include**
- The extended survey capture (PH/PV expansion, hogar, connection, meter) — that
  writes the OBSERVATION layer, separate flow.
- The app UI (separate session).
- Media/photos, offline conflict resolution beyond client_id idempotency.
- **Any coordinates** — the payload and storage carry none.
- Address normalization on ingest (the matcher normalizes at match time).
- `loc` re-sequencing / mid-route insert logic (the gaps of 5 absorb inserts; the
  app owns ordering).

## Actors and permissions
- **Field worker** (our team), authenticated with a **field-worker token**
  (`require_field`), scoped to tenant + worker. The target route must belong to the
  token's tenant.

## Preconditions
- The route exists and is frozen (validation done).
- The field worker's token is valid and scoped to the route's tenant.

## Trigger
The app POSTs a batch of captured placas for a route (during/after the placa pass).

## Main flow (happy path)
1. App `POST /field/capture/placas` with `{ route_id, batch_id, items: [...] }` and
   the field token.
2. API validates the token and that `route_id` belongs to the token's tenant.
3. For each item `{ client_id, posicion, placa?, manzana_catastral?, tipo_acceso?,
   observacion? }`:
   - **upsert by `(tenant_id, client_id)`**: if new → create a `census_code` with
     `localizacion = posicion × 5`, `ph = 0`, `pv = 0`, `placa_predio = placa`,
     `manzana_catastral`, tenant/route scoped; if it exists → update
     placa/posicion(→loc)/manzana.
4. Return per item: `census_code id`, assigned `loc`, and `created|updated`.
5. The batch is recorded (audit).

## Alternative flows (sad paths)
- **A1 — re-push (same `client_id`)**: idempotent update, never a duplicate.
- **A2 — duplicate `posicion`/`loc` within the route** (two different client_ids, same
  posicion): rejected for that item (would violate the unique census code) and
  reported; the rest proceed.
- **A3 — route not in the token's tenant**: `403`/`404`, nothing written.
- **A4 — blank placa**: allowed — the unit is created with `placa_predio = null`
  (placa deferred); the matcher will bucket it as sin_direccion.
- **A5 — non-field or invalid token**: `401`/`403`.

## Business rules
- **BR1** Dedicated endpoints; not the observation sync (creating units ≠ observing
  reality).
- **BR2** Item payload carries `client_id`, `posicion`, `placa?`, `manzana_catastral?`,
  `tipo_acceso?`, `observacion?`; batch carries `route_id` + `batch_id`. **No
  coordinates.**
- **BR3** Creates one `census_code` per item: `loc = posicion × 5`, `ph/pv = 00`,
  `placa_predio = placa`, tenant/route scoped.
- **BR4** `manzana_catastral` is an optional per-item value (from route design);
  stored if present, else null (the matcher falls back to municipality-wide).
- **BR5** Idempotent by `(tenant_id, client_id)` — re-push updates, never
  duplicates.
- **BR6** Auth: `require_field`, scoped to tenant + worker; route must be in-tenant.
- **BR7** Writes **directly to `census_codes`** (our team owns the unit registry);
  distinct from the surveyor's extended capture (observation layer).
- **BR8** Placa is stored **raw**; normalization happens at match time (T3).
- **BR9** `tipo_acceso`/`observacion` are stored as capture notes (minimal: in
  `observacion`); a dedicated access-evidence field belongs to the extended survey.

## Edge cases and error handling
- `posicion < 1` → rejected (loc must be ≥ 5).
- Empty `items` → 200 with an empty result (no-op).
- Partial failure: per-item results carry `ok|error`; the batch is not all-or-nothing.
- A census_code already promoted/linked (npn_match_method='manual') — the capture
  endpoint only sets placa/loc/manzana; it does NOT touch npn or match state.

## Acceptance criteria
- Migration adds `census_codes.client_id` (nullable) + unique `(tenant_id,
  client_id)`.
- `POST` creates census_codes with `loc = posicion×5`, `ph/pv = 0`, placa, tenant/route
  scoped; response returns id + loc per item.
- Re-posting the same `client_id` updates in place (no duplicate).
- A route from another tenant is rejected under a field token.
- `GET` returns the route's captured frame (client_id, posicion, loc, placa).
- No coordinate field exists anywhere in the request or the stored row.

## BDD (Gherkin)

```gherkin
Feature: Field placa capture

  Scenario: Batch creates ordered census units
    Given a frozen route in the worker's tenant
    When the app posts 3 placas with posicion 1,2,3
    Then 3 census_codes exist with loc 5,10,15, ph/pv 00, and those placas

  Scenario: Re-push is idempotent
    Given a placa already captured with client_id X
    When the app posts client_id X again with a corrected placa
    Then the same census_code is updated, not duplicated

  Scenario: Blank placa is allowed
    Given an item with an empty placa
    When the app posts it
    Then the census_code is created with placa_predio null

  Scenario: Cross-tenant route is rejected
    Given a field token for tenant A
    When it posts to a route of tenant B
    Then the API responds 403 and writes nothing
```

## Suggested tickets
- **TA.1 — Schema**: `census_codes.client_id` (nullable) + unique `(tenant_id,
  client_id)` + migration. Gate: alembic upgrade, column/constraint exist.
- **TA.2 — POST /field/capture/placas**: field-auth, per-item upsert (loc=posicion×5,
  idempotent, in-tenant route), per-item result. Gate: pytest (create, idempotent,
  cross-tenant, blank placa).
- **TA.3 — GET /field/capture/route/{id}**: return the captured frame. Gate: pytest.

### Downstream (separate)
- The custom capture app (separate session/repo) consuming this contract.
- Extended survey capture API (PH/PV expansion, hogar, meter) → observation layer.
