# Spec 13 — Anchor by manzana (full-placa R1 anchor for assisted paradas)

> Status: **Draft** — spec phase. Branch `feature/ancla-por-manzana`.
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.
> Relates to: the **R1-assisted capture** spec (typeahead + field-confirmed NPN +
> "No está en la lista") and **Spec 10 / Decisions v2** (parada-scoped capture,
> prediction). This spec changes the gate that selects the **assisted vs rural**
> capture mode: from "the parada has a terna" to "the parada has a manzana".

No backend contract change. No terna seeding required. The R1 directory the app
already downloads per tenant is enough.

## User story
As a **field worker**, when a parada has a **manzana catastral**, I type the
**full placa** (`dirección en la puerta`) of the first predio — the **anchor** —
and a dropdown offers R1 addresses **restricted to that manzana**. I pick the one
that matches (it links by NPN) or mark **"No está en la lista"** (a finding). From
that anchor, the following placas on the parada are **predicted** (Spec 10
"Siguiente esperada"). The assisted mode turns on because the parada **has a
manzana** — not because it has a terna.

## Objective
Make **"has a manzana"** the condition for R1-assisted capture
(manzana-scoped full-placa anchor + prediction), instead of **"has a terna"**. A
parada with a manzana but no terna must offer the anchor dropdown — today it falls
to **rural free-text** ("Nombre del predio") even though the manzana's R1 rows are
already loaded (e.g. 714 rows for Ruta 20·parada 1, 155 for Ruta 10). Reserve rural
mode for paradas with **no manzana** (topónimo). The parada's terna is no longer
consumed by the capture flow — prediction derives the face from the anchor's own R1
row.

## Scope

### Includes
- **Mode selection by manzana:** a parada **with** a manzana → R1-assisted; a parada
  **without** a manzana → rural (unchanged free-text topónimo).
- **Full-placa anchor field** for assisted paradas: label `"Placa (dirección en la
  puerta)"`, helper `"Escribe lo que VES. Se guarda tal cual, siempre."`; the
  dropdown is scoped to the parada's manzana via the existing manzana search
  (`r1.search(tenantId, text, manzana)`).
- The fixed first row **"No está en la lista"** (finding) preserved.
- Linking an R1 row stores the **NPN**; the typed text and the linked address are
  both kept (no silent overwrite — the pair is the record).
- **Prediction after an R1-linked anchor**, derived from the anchor's R1 row + the
  manzana's R1 rows (lift the `!hasTerna` gate in `paradaCaptureContextProvider`).
- The **soft acera/parity warning** retained, read from the placa number.
- On save, a manzana parada is **not "rural"**: it stores NPN (if linked) or
  `sinR1=true` (if "No está en la lista"), plus the parada's `manzana_catastral`.

### Does NOT include
- **Backend contract changes** or seeding the paradas' ternas.
- The **distance shortcut** as the FIRST anchor: the anchor is always the full
  placa (the face's terna is unknown until an R1 row is linked). A distance-only
  input AFTER the anchor is added by **AM.8** (see below), composed from the
  ANCHOR's R1 terna — not the parada's, and with no backend change.
- Any **schema/migration** change (UI + providers logic only).
- **`es_lote` / Spec 12** behavior (a lote still bypasses R1 suggestions).
- The **urban/rural card classification** (stays by the manzana's zona código).
- **Unassisted routes** (no parada, `ctx==null`) — unchanged.
- **Making the anchor mandatory** — assist, not cage: a non-linked or blank placa
  can still be saved.

## Actors and permissions
- **Field worker** (`field_token`, titular or pareja): the only actor. Captures on
  a `verificada` route, coordinate-free, strict order.
- No office/operator surface here (NPN stays hidden; the office view is backend-side).

## Preconditions
- An open `verificada` route with a **current parada** that carries a non-empty
  `manzana` (`ParadaCaptureContext` is non-null).
- The tenant's **R1 directory** is downloaded locally (rows may or may not exist for
  the specific manzana — see edge cases).
- The capture is **Construido** (`es_lote=false`); a lote keeps its Spec 12 flow.

## Trigger
The worker opens **Capturar** on a parada with a manzana and focuses the placa
field, or types in it.

## Main flow (happy path) — anchor via dropdown selection
1. The worker opens Capturar on parada 1 (manzana present, no terna). The placa
   field reads `"Placa (dirección en la puerta)"`; no "Siguiente esperada" card yet
   (no anchor).
2. The worker types the full placa they read on the door (e.g. `CALLE 14 # 2-104`).
3. As they type, the dropdown lists R1 rows of **that manzana** matching the
   fragment, with **"No está en la lista"** fixed on top.
4. The worker **taps the matching R1 row**. The unit links by NPN; a linked card
   shows `Enlazada a: …` with the typed text preserved.
5. The worker taps **"Guardar y siguiente"**. The capture is stored with NPN +
   manzana, queued (`pending`).
6. The next capture now shows the **"Siguiente esperada"** card (predicted from the
   anchor's R1 row), and the sweep continues in order.

## Alternative flows (sad paths)
### A. Door not in R1 — finding (submit via the panel row)
1. The worker types a placa with no match (or a real door the list never had).
2. In the dropdown they tap **"No está en la lista"**.
3. The field keeps the typed text; the unit is flagged as a **hallazgo**
   (`sinR1=true`, no NPN).
4. They save. The capture is stored as a finding; it does **not** anchor the
   prediction (the sweep still has no R1 anchor).

### B. Prediction confirmed (submit via the "Coincide" button)
1. After an anchor exists, the "Siguiente esperada" card shows the predicted address.
2. The worker taps **"Coincide"** → the predicted R1 row links in one tap; save.
3. (Contrast with "No coincide": the prediction is dismissed for this capture and the
   worker enters what they see via the manzana dropdown.)

### C. Blank placa on a manzana parada
1. The worker leaves the placa empty (a unit with no readable address yet).
2. They save. The capture is stored with `placa=null`, no NPN — allowed; it does not
   anchor prediction.

### D. Parada without manzana — rural (unchanged)
1. The parada has no manzana. The field reads `"Nombre del predio"`, free text, no
   dropdown, no prediction (topónimo verbatim) — exactly as today.

## Business rules
- **BR1 — Mode by manzana.** Assisted mode (dropdown + prediction) is selected by a
  non-empty `parada.manzana`. The parada's terna (`tipo_via/num_via/num_cruce`) is
  **not** a condition and is **not consumed** by the capture flow.
- **BR2 — Manzana-scoped suggestions.** The anchor dropdown shows R1 rows for the
  **parada's manzana only** (`r1.search(tenantId, typed, manzana)`), as the worker
  types; never a full dump on an empty field.
- **BR3 — Full placa, verbatim.** The anchor is the **full placa** as read on the
  door, stored verbatim ("se guarda tal cual"). Linking an R1 row never overwrites
  the typed text — the raw placa and the NPN are **both** the record (NPN hidden).
- **BR4 — Findings are first-class.** "No está en la lista" stores the capture as a
  finding (`sinR1=true`, no NPN); it is a valid outcome, never an error.
- **BR5 — Anchor is not mandatory.** A non-linked placa (finding) or a blank placa is
  saveable. The flow assists; it never blocks (doctrine).
- **BR6 — Prediction needs an R1 anchor.** Prediction starts only once the parada has
  a capture **linked to R1** (NPN present); it is derived from that anchor's R1 row +
  the manzana's R1 rows. A finding does not move/create the anchor.
- **BR7 — One parada = one face sweep.** The anchor's R1 address determines the face;
  the worker closes the parada ("Cerrar esta parada") when the face is swept and the
  next parada unlocks. Several paradas may share a manzana (one per face).
- **BR8 — Coordinate-free & strict order unchanged.** `posicion` append-only,
  `loc = posicion × 5` (backend), `client_id` idempotent, PH/PV `00`. This spec adds
  no coordinates and no new push fields.
- **BR9 — NPN as the transversal key.** The linked NPN rides hidden under the same
  full-replacement rule as today (omitted on a re-push ⇒ the server clears it); this
  is what lets the office resolve the census unit (Fantasma/Camaleón audits depend on
  the NPN being carried only on a real affirmed link).
- **BR10 — es_lote precedence.** If the capture is `es_lote` (Sin construir), the R1
  dropdown stays hidden regardless of manzana (Spec 12 unchanged).

## Edge cases and error handling
- **Manzana present, zero R1 rows for it:** the field is still full-placa; the panel
  shows only "No está en la lista"; every capture is a finding; no prediction. Graceful
  degradation, no error.
- **R1 directory not downloaded at all** (tenant count 0): no suggestion panel; the
  worker types freely and saves (finding/sin-placa); manzana is still stored.
- **Anchor linked to a row whose face has a single entry:** prediction immediately
  reports end-of-face; the worker may capture stragglers as findings and close the
  parada.
- **Duplicate NPN in the route** (PH share a door): the existing soft duplicate
  warning shows; never blocks.
- **Parity mismatch** (placa number looks like the other acera): the existing soft
  warning shows; "se guarda igual".
- **Worker edits a pending capture** before sync: the worker's edits win (the merge
  never clobbers pending edits).

## Acceptance criteria
1. On a parada **with a manzana but no terna**, the placa field reads `"Placa
   (dirección en la puerta)"` and typing shows a dropdown of R1 rows **restricted to
   that manzana** plus "No está en la lista". *(Today it shows "Nombre del predio"
   and no dropdown.)*
2. Selecting an R1 row links the unit by NPN; the typed text is preserved.
3. After an R1-linked anchor, the next capture shows the "Siguiente esperada"
   prediction card — **without** the parada having a terna.
4. "No está en la lista" stores a finding (`sinR1=true`, no NPN); a blank placa saves
   with `placa=null`. Neither blocks.
5. A parada **without** a manzana still shows `"Nombre del predio"` free-text, no
   dropdown, no prediction.
6. A lote (`es_lote`) still hides the dropdown regardless of manzana.
7. No backend contract change, no schema/migration; `flutter analyze` clean,
   `flutter test` green.

## BDD (Gherkin)

```gherkin
Feature: Anchor by manzana for assisted paradas
  The assisted R1 flow (manzana-scoped dropdown + prediction) is selected by the
  parada having a manzana, not a terna.

  Background:
    Given an open verificada route
    And the tenant's R1 directory is downloaded

  Scenario: Manzana parada without terna offers the manzana-scoped anchor dropdown
    Given the current parada has a manzana and no terna
    And the parada has no captures yet
    When I type "CALLE 14 # 2-104" in the placa field
    Then the placa field label is "Placa (dirección en la puerta)"
    And a dropdown lists R1 rows of that manzana matching the text
    And "No está en la lista" is the fixed first row

  Scenario: Selecting the R1 anchor links the NPN and starts prediction
    Given the manzana dropdown is showing suggestions
    When I tap the matching R1 row
    And I tap "Guardar y siguiente"
    Then the capture is stored with the NPN and the manzana
    And the next capture shows the "Siguiente esperada" prediction card

  Scenario: Door not in the list is a finding, not an anchor
    Given the current parada has a manzana and no captures
    When I type an address with no R1 match
    And I tap "No está en la lista"
    And I tap "Guardar y siguiente"
    Then the capture is stored as a finding with sinR1 true and no NPN
    And the next capture shows no prediction card

  Scenario: Blank placa is allowed on a manzana parada
    Given the current parada has a manzana
    When I leave the placa field blank
    And I tap "Guardar y siguiente"
    Then the capture is stored with placa null and no NPN

  Scenario: Parada without a manzana stays rural
    Given the current parada has no manzana
    When I focus the placa field
    Then the label is "Nombre del predio"
    And no dropdown is shown
    And no prediction card appears

  Scenario: A lote hides the dropdown even with a manzana
    Given the current parada has a manzana
    When I select "Sin construir"
    Then no R1 dropdown is shown
```

## Suggested tickets (small stories)
- **AM.1 — Spec** (this document). Gate: approved.
- **AM.2 — Wireframe.** Assisted capture on a manzana parada **without terna** (dummy
  data): full-placa field + manzana dropdown + "No está en la lista" + prediction card
  after an anchor. Gate: renders the layout; rural (no-manzana) still renders free-text.
- **AM.3 — Design.** Theme pass. Reuses `_SuggestionPanel`, `_ExpectedPlacaCard`,
  `_LinkedCard` — expected to be near-noop. Gate: compiles and looks right; commit.
- **AM.4 — Context/prediction (providers).** In `paradaCaptureContextProvider`, drop
  `if (!hasTerna) return bare()`; compute prediction from the anchor's R1 row whenever
  a manzana + R1-linked anchor exist. Gate: unit tests for manzana-without-terna
  prediction.
- **AM.5 — Capture screen gates.** Key `_panelVisible`, `_onPlacaChanged`, `placaLabel`
  and the `rural` flag in `_saveAndNext` on **manzana presence** (not terna): full-placa
  label + directory helper + `r1.search(…, manzana)`; rural only when no manzana.
  Gate: widget test — manzana parada shows suggestions + links NPN; no-manzana stays rural.
- **AM.6 — Tests.** Unit + widget covering BR1–BR7 and the acceptance criteria.
  Gate: `flutter analyze` clean, `flutter test` green.
- **AM.7 — Manual E2E.** Against the Railway pilot (Pitalito Ruta 20): anchor from the
  manzana dropdown → NPN link → prediction → push → frame round-trip. Gate: verified
  live; cross-confirmed cleanup.

---

## AM.8 — Distance shortcut after the anchor (follow-up)

> Status: **Draft** — approved in concept (Jorge 2026-10-05, "solo distancia").
> Branch `feature/distancia-ancla`.

### Objective
Once a parada has an R1-linked anchor, the face's terna is known (from the anchor's
R1 row). From there the worker types **only the distance** (e.g. "12") and the app
composes the full address from that terna, searching R1 by distance on that face —
saving the street on every door. The FIRST anchor stays full-placa.

### Business rules
- **BR-D1 — Trigger.** Distance mode activates only when the parada has a capture
  **linked to R1** (an anchor with an NPN). Before that → full-placa anchor (Spec 13).
- **BR-D2 — Terna from the ANCHOR.** The composing terna is the anchor's R1 row terna
  (`tipo_via/num_via/num_cruce`), NOT the parada's (paradas carry no terna).
- **BR-D3 — Distance-only input.** The field reads "Distancia (a la esquina)"; the
  worker types only the distance. The live helper shows the composed preview
  (`CALLE 13 # 3A-__` → `CALLE 13 # 3A-12`).
- **BR-D4 — Scoped search.** Typing searches `searchByDistance(anchor terna, distance,
  manzana)` — scoped to that face. "No está en la lista" stays the fixed first row
  (a finding on the same face).
- **BR-D5 — Prediction coexists.** The "Siguiente esperada" card (Coincide / No
  coincide) is unchanged — Coincide is the one-tap path; distance is for divergence.
- **BR-D6 — es_lote / no-manzana unchanged.** A lote hides it; a parada with no
  manzana stays rural free-text (no anchor → no distance mode).
- **BR-D7 — No backend/contract/schema change.** Reuses `searchByDistance` + the
  existing push (npn from the linked R1 row).

### Out of scope
- Hybrid input (full placa + distance together) — distance-only after the anchor.
- Cross-face capture within one parada (one parada = one face).

### Tickets
- **AM.8.1 — Spec** (this section). Gate: approved.
- **AM.8.2 — Expose the anchor terna.** `paradaCaptureContextProvider` surfaces the
  anchor's `FaceAddress` (terna) on `ParadaCaptureContext`. Gate: unit test.
- **AM.8.3 — Capture screen distance mode.** When the anchor terna exists (+ manzana,
  not lote): label "Distancia (a la esquina)", preview from the anchor terna,
  `searchByDistance`. Gate: live verify on Ruta 10 (anchor 3A-02 → type "08" →
  composes/links "CALLE 13 # 3A-08").
- **AM.8.4 — Tests.** analyze clean, flutter test green.
