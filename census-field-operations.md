# Census field operations — faro roadmap (coordinate-free)

> **Copy — source of truth lives in the backend repo:**
> `layerflow/docs/census-field-operations.md` @ `b46e020`
> (branch `feature/extended-census`). Update the pinned commit when the
> backend announces a doctrine change; do not edit doctrine here.

Decisions that govern how the census is planned and captured in the faro project
(Isnos). This is the operational counterpart to the data specs
(`specs/cadastral-reference-r1.md`, `specs/npn-matching-engine.md`). It records the
**why**, not build tickets.

## 0. Core constraint: no coordinates in the faro
- **No GNSS receiver, and no phone GPS anywhere in the workflow.** We do NOT use
  Android phones to capture coordinates.
- A submeter/RTK GNSS receiver is the **deber-ser** (ideal, future). Including it
  in the first project is a **nice-to-have accelerator, not a precondition** — the
  faro must work without it.
- Why it matters: small-frontage predios are indistinguishable in Google/ESRI
  imagery, phone GPS is coarse (>3 m), and the cadastral base is displaced (2 m+).
  A point cannot reliably discriminate between adjacent predios, so we do not lean
  on point geometry at all in the faro.

## 1. Consequence: an ordinal + attribute model (not spatial)
- The cadastral parcel geometry is **not a source of truth** for the meter↔predio
  link (it is a reference/context layer only — demoted, not deleted).
- With no coordinates, **`loc` (localización) is the ONLY encoding of walk order**;
  there is no geometry to re-sort by later.
- The predio link (NPN) rides on the **placa (address) → R1**, resolved in the
  office by the matching engine (`specs/npn-matching-engine.md`), never on a
  spatial join.
- The **manzana** used to constrain matching comes from **route design** (the GIS
  engineer knows the block), **not** from an imprecise point.

## 2. The field workflow (Model A — recommended for the faro)
1. **Route design** in QGIS.
2. **Route validation** in the field → ends with the route **FROZEN** (all
   reroutes/redesigns applied, the line locked).
3. **Placa + access capture** in **strict route order** (a separate pass, after the
   route is frozen).
4. **NPN assignment via R1** in LayerFlow (office, before surveyors deploy) — the
   matching engine resolves the auto cases and queues the ambiguous ones.
5. **Surveyors** run the extended survey on top of the prepared data, expanding
   PH/PV where the structure requires it.

**Invariant — grábala:** **route final → then `loc`. Never the reverse.**
Assigning `loc` against a route still being redesigned corrupts the order
irreversibly (no coordinates to recover it). Steps 2 and 3 are **separate passes**;
do not bake `loc` while still validating.

> Merged single-pass capture (validate + capture together, assign `loc` in office
> from segment + local order) is possible but requires disciplined structured
> capture and is an **optimization for later** — not for the first project.

## 3. Localización — office autoincrement by 5
- The field worker focuses **only on placas + accesses**, captured in strict route
  order. The app stamps a **monotonic counter** per capture (1, 2, 3…).
- The office runs a trivial script: **`loc = order × 5`** (5, 10, 15…).
- **Invariant:** the capture order must be **faithful and append-only**, enforced
  by the **app**, not by the worker's memory. If the app allows free reorder, the
  inference corrupts.
- The gaps of 5 exist to absorb the cadastre's **future life** — subdivisions,
  remodelings, new units — by inserting (a 7 or 8 between 5 and 10) **without
  renumbering** the rest.

### Renumbering — two windows (DECIDED 2026-09)
"Never renumber" applies to the field and to the published cadastre — NOT to
the office while the codes are still private:
- **Field (during capture): never.** The app stays append-only; a skipped
  house is captured at the end with a typed `ins_after` flag (v2; the v1
  `[ins:after=N]` text token is deprecated).
- **Office (reconciliation window — before NPN matching / extended survey /
  any external use): shift-insert allowed.** The skipped unit is placed at its
  true position and the in-between stretch shifts +5 (census-loc-shift-insert
  spec). Identity lives in the row UUID/client_id, so nothing downstream
  breaks; the endpoint refuses the shift once any affected code is NPN-matched
  or bridge-linked. Several pending insertions apply in descending-after order
  (BR10).
- **Post-census (lifecycle): never again.** Codes are official; insertions use
  the gaps (a 7 between 5 and 10). Renumbering is forbidden.

## 4. Survey pass UX (surveyor)
- Forms are **pre-loaded per captured placa/loc** and **unlock in strict order** as
  the surveyor advances.
- **PH/PV is never hand-typed.** The surveyor **declares structure** with buttons
  ("add floor", "add a unit on this level") and the app **auto-generates** PH/PV.
  - PH = floors (stacked, going up). PV = units at the same level (side by side).
  - **Incremental per level**, not a rigid floors×units matrix — buildings are
    irregular (floor 1: 2 units, floor 2: 1, floor 3: 3).
- **Desync guards (non-negotiable):** the strict-order rail must allow **absent**
  (mark visited-pending), **insert** (new domicile), **skip** (demolished), and
  order override. The **placa shown and verified at each door** is the anchor that
  confirms "form N = house N" — it replaces GPS as the "am I at the right house?"
  check.

### Codification convention (DECIDED 2026-07 — sentinels)
- `00` and `99` are **sentinels**, not ordinary indices:
  - `00/00` = **unifamiliar only** (a single-unit predio).
  - `99/99` = acometida principal / totalizador, recorded **only when it physically
    exists** (evidence-based, never auto-generated).
- Real units start at `01`: **PH = floor** (street level = `PH 01`, increasing
  upward), **PV = unit within the floor** (`PV 01`+, in walk order).
- A placa-pass `00/00` that turns out multi-unit is **reclassified**: the `00/00`
  is dropped and units become `01/01`, `01/02`, … (never mix `00` with `01+`).
- Examples: 3 side-by-side units → `01/01, 01/02, 01/03`; floor 1 (2 units) +
  floor 2 (1) → `01/01, 01/02, 02/01`; building totalizer → `99/99`.
- The survey buttons emit codes per this rule: "add floor" → next PH from `01`;
  "add unit" → next PV from `01` on that floor; the provisional `00/00` is replaced
  on the first "add".

### "Separate unit" criteria (DECIDED 2026-07 — regulation-grounded)
A domicile is a **separate unit** (its own census-code / PH-PV row) when it meets
the "unidad independiente" test that converges across Decreto 302/2000, CRA Res.
319/2005, Ley 675/2001 and the DANE census manual:
- **Independent access — DECISIVE:** own access from the street/public way OR from
  common areas (hall, stairs, patio), **without passing through another unit's
  private/exclusive space** (you don't cross a bedroom/kitchen/living room to reach
  it).
- **Apt for independent use/habitation** per its destination (vivienda, local,
  oficina), with its own basic facilities.
- **NOT a criterion — having its own meter.** A *multiusuario* is 2+ independent
  units sharing ONE general meter; they are still separate units. That shared meter
  is the `99/99` totalizador. Using "own meter" as the test under-counts multiusuarios.

Surveyor evidence to capture: the independent-access answer ("can you enter without
crossing another unit's private rooms?") + access type (own door to street / common
area) + whether metering is individual or general (multiusuario).

## 5. Tooling implication
No GPS + guided-sequential flow + structural PH/PV buttons + dynamic forms makes
QField's strengths (map, "you are here") irrelevant and fights its form-per-feature
flow. This is the **strongest signal yet toward a custom mobile app** rather than
QField. **DECIDED (2026-07): build a custom mobile app** — QField cannot carry the
no-GPS guided-sequential flow with dynamic PH/PV forms.

**Stack: Flutter** (decided 2026-07). Single codebase, solid offline (SQLite/drift),
and — decisive — **native Bluetooth**, so a future external GNSS receiver (e.g.
Polaris, NMEA over Bluetooth) can be added without switching stack. PWA/Capacitor
were dropped precisely because they can't reliably talk to an external receiver.
The app starts coordinate-free; external-GNSS capture is a later add-on. Claude
writes the code; the user maintains it solo.

## 6. The map's role in the faro
- In the faro, LayerFlow is a **georeferenced registry with thematic/aggregate
  cartography**, not a precision GIS. **Do not oversell precise per-point spatial
  analytics.**
- Real map power for a user cadastre is **thematic at manzana/route/sector level**:
  coverage %, anomaly density (Fantasma/Camaleón/Invasor per block), route
  progress — all of which work **without GNSS** (they need the census_code→manzana
  link, which is ordinal + attribute).
- Spatial substrate we DO have: route lines, the manzana/street grid, parcels as a
  reference layer, census attached to manzana.
- Deferred to the GNSS phase (and mostly out of MVP scope anyway): survey-grade
  points, point-level heat maps, spatial join as truth, network tracing.

## 7. Two data layers and the coverage gap
- **Layer A — observable, no resident needed** (domicile existence, placa, access,
  meter presence/serial/status, connection type, built/vacant, external PH/PV):
  **target ~100%, non-negotiable** (no "nobody was home" excuse).
- **Layer B — extended census, requires an adult resident** (household, occupants,
  tenure, socioeconomic): **negotiate a coverage %**; a residual gap is inevitable
  (deadlines + absent residents).
- A domicile without Layer B is **not a hole in the cadastre** — it stays **in it,
  flagged "extended pending"**. It is a hole in enrichment, not in the registry.
- The **regulatory backbone and all three fraud rules run on Layer A + R1/CIS** —
  none need the resident (Camaleón is pure desk-work). So the census stays relevant
  even at 0% Layer B **technically**; **contractual** relevance depends on what was
  sold — if extended census was the headline deliverable, 0% is a breach.
- Use the **CU-005 revisit protocol** (nadie_presente → próxima visita) to shrink
  the Layer B gap before the deadline.
- **Platform requirement (DECIDED):** LayerFlow **must be able to capture Layer B** —
  a non-negotiable platform capability. The accepted coverage **%** is a
  **per-project/contractual** matter, not a platform decision: inform the client of
  the minimal gap, measure the proportion, and negotiate the % per project.

## Decided (2026-07)
- **No GNSS in the first project** — coordinate-free; GNSS is a later accelerator (§0).
- **PH/PV codification** — sentinels `00`/`99`, real units from `01`, ground =
  `PH 01`, reclassify `00/00` when multi-unit, `99/99` only if a physical totalizer
  exists (§4).
- **"Separate unit" = unidad independiente** — independent access, NOT own meter;
  regulation-grounded (§4).
- **Custom mobile app in Flutter** (not QField) — offline + native Bluetooth for a
  future external GNSS receiver (§5).
- **Layer B is a platform capability** (non-negotiable); coverage % is
  per-project/contractual (§7).

No open decisions remain for the field-operations roadmap.

## Relegated — legacy, NOT used in the faro
The coordinate-free pivot supersedes the earlier **spatial** approach. These
artifacts are kept (for a future GNSS phase) but must NOT be treated as the active
path in the faro:
- **`scripts/qgis/asignar_census_codes.py`** — assigns `npn` by spatial `contains`
  and creates `expected_meters` points. The faro links NPN by address→R1, not
  geometry, and captures no coordinates.
- **`expected_meters` (table/model)** — a per-domicile point layer; the faro's
  ordinal model uses no points. Unused until a GNSS phase.

Still active from the backbone: routes, census_codes, campaigns/assignments,
visits/observations, sync, the R1 reference and the address→NPN engine.
