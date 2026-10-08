# Spec 14 — No encontrado en campo (not-found-in-field, negative capture record)

> Status: **Draft** — spec phase. Branch `feature/no-encontrado` (to create).
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.
> Relates to: **Spec 10 / parada-scoped capture** (the prediction card, `currentParada`,
> the local prediction mirror `face_prediction.dart`), **Spec 12 / `es_lote`** (the
> "Construido / Sin construir" control — the key boundary: a demolished predio is a
> **lot**, not a not-found), **Spec 13 / ancla-por-manzana** (the anchor + `predictNext`),
> and the `strict-sequential-order` project note (the order of paradas and placas is the
> non-negotiable core).
>
> **Naming — read this.** This is **NOT** the CLAUDE.md audit rule **"Fantasma"** (a built
> polygon with **0 meters** — a SUI/utility consumption anomaly). This spec is a
> **capture-time negative record** that feeds **R1 / cadastre quality**: a phantom entry
> **in R1** with no field referent. It was renamed from "Fantasma" (2026-10-09, on the
> backend's catch) to avoid that collision. It **pairs with *hallazgo*** (found in the
> field, absent from R1): this is its inverse — present in R1, absent in the field. The
> *englobe / Camaleón* case (a predio that exists but whose identity merged) is a
> **separate future spec**, out of scope here.

## User story
As a **field surveyor (encuestador)** sweeping a parada in strict order, when the app
predicts the next expected placa (from R1) and I verify in the field that it has **no
physical correspondence at all** — no predio, no lot, no gap for it in the face sequence
— I want to declare it **"no encontrada en campo"** from the prediction card, so it is
recorded as a **not-found** observation (a negative record) for SIG to reconcile, and the
sweep advances to the next expected placa **without breaking the order**.

## Objective
Give an explicit exit to the case *"the registry says there is something here and there
is nothing"*, without inventing a placa or silently skipping. A not-found is a **negative
record**: no census unit is created. It is declared against the **currently predicted R1
placa**, it **advances** the sweep, and it counts as **resolved** for manzana exhaustion.

## Scope

### Includes
- A **"No encontrada en campo"** action on the **prediction card** of an assisted parada.
- A **brief confirm** before recording, which reminds that a demolished predio / empty lot
  is **"Sin construir"**, not a not-found (a guardrail against catch-all misuse).
- Recording a **negative local record** tied to the predicted R1 placa (its
  `direccion_norm` / `npn`), queued like any capture, pushed on **Enviar**.
- **Advancing the prediction** to the next expected placa after the not-found, same
  direction.
- Treating a not-found as **resolved** for manzana exhaustion (CL-R6).
- Showing not-found entries **distinctly** in the parada / resume view, and letting them
  be **undone** (before send; re-sent after).
- An **optional** observación on the not-found.

### Does NOT include
- **The CLAUDE.md audit rule "Fantasma"** (built polygon + 0 meters) — a different layer
  (SUI/utility audit), unrelated to this capture-time record.
- **Camaleón / englobe** (a predio that exists but whose identity merged/changed) — a
  separate future spec. A not-found is a *pure* negative record; an englobe is a *merge
  relation* handled elsewhere.
- **Demolido / baldío / potrero** — the lot exists → **"Sin construir"** (Spec 12
  `es_lote`), placa **deduced** from the neighbours. Not a not-found.
- **Re-numerado** — the predio exists with another number → capture the **real field
  placa** (a hallazgo if the new number is absent from R1). Not a not-found (it is a
  Camaleón).
- **Not-accessible-now** (closed, occupant absent) — the predio **exists**; an
  access/timing matter, resolved under strict order (resolve or switch route), never
  invented and never a not-found.
- **The server-side implementation** of a not-found (the `no_encontrados` table, exhaustion
  recompute) — the **backend owns it**; the wire contract is **resolved** (see **Backend
  contract**).
- PH/PV / interiores / aptos — extended-survey phase; the container predio exists.

## Actors and permissions
- **Encuestador (titular or pareja)** assigned to the route may declare a not-found, the
  same as a capture. Unsent not-found records belong to whoever declared them (CL4).

## Preconditions
- An **assisted** parada: it has a **manzana** and the R1 prediction is available (Spec 13).
- The parada is the **current** one (strict lock) and already has an **anchor** — at least
  one real placa captured — so there is a *predicted next placa* to declare absent.

## Trigger
On the current parada's capture screen, the prediction card shows the next expected placa
(e.g. *"siguiente: CALLE 13 # 3-20"*). The surveyor taps **"No encontrada en campo"** on
that card.

## Main flow (happy path)
1. The surveyor has anchored the parada (e.g. captured `CALLE 13 # 3-18`); the prediction
   card shows *"siguiente: CALLE 13 # 3-20"*.
2. In the field there is **no predio and no lot** for `3-20` — the neighbours are
   contiguous, there is no gap for it.
3. The surveyor taps **"No encontrada en campo"** on the prediction card.
4. A brief confirm appears: *"¿`CALLE 13 # 3-20` no existe en campo? Si está demolido o es
   un lote, usa 'Sin construir'."* with **[Cancelar]** / **[Confirmar: no existe]**.
5. The surveyor taps **[Confirmar: no existe]** (optionally after typing an observación).
6. A not-found is recorded against `3-20`'s R1 row: **negative** (no census unit, no
   `secuencia_parada` / `loc`), queued to send.
7. The sweep **advances**: the prediction card now shows the **next** expected placa
   (`CALLE 13 # 3-22`), same direction.
8. The resume / parada view lists `3-20` distinctly as **"no encontrada"**.

## Alternative flows (sad paths)
- **A — Declared by mistake (undo).** The surveyor confirms a not-found, then realises it
  was actually a lot. From the resume view (or an undo affordance right after), they
  **undo** it; `3-20` returns to *predicted / pending* and the prediction re-points to it.
- **B — Offline.** Connectivity is down. The not-found records **locally** and queues; it
  is sent on the next **Enviar** (full-replacement, idempotent by `client_id`). Declaring
  a not-found never needs the network.
- **C — It is really a lot (the guardrail bites).** At the confirm, the reminder makes the
  surveyor realise `3-20` is a demolition lot. They **[Cancelar]**, switch the form to
  **"Sin construir"**, and capture it as a lote with the deduced placa — no not-found.
- **D — Not found at the end of the face.** The last real placa is captured; the prediction
  points past it; that door is absent. The surveyor declares it not-found; the **face
  ends** (no further prediction), the parada can be closed.
- **E — Rural / unassisted parada.** There is no prediction card, so the **action is not
  offered**; the concept does not apply (the surveyor captures free placas as usual).

## Business rules
- **BR1 — Definition.** A not-found is an R1 placa with **no physical correspondence**: no
  predio, no lot, no gap in the face sequence. It is a **negative record**; **no
  census_code / placa** is created.
- **BR2 — Only the predicted placa.** A not-found can be declared only on the **currently
  predicted** next placa — never on an arbitrary typed address.
- **BR3 — Assisted only.** Available only on a parada with a manzana + R1 prediction, and
  only after the **anchor** exists (there must be a predicted next placa).
- **BR4 — Advances the sweep.** Declaring a not-found moves the prediction to the **next
  expected placa** in the **same direction**; the strict order is preserved.
- **BR5 — No sequence.** A not-found consumes **no `secuencia_parada` / `loc`** — it is not
  a predio in the walk order.
- **BR6 — Photo-exempt.** A not-found is **exempt from `foto_obligatoria`** (there is
  nothing to photograph); a photo of the spot is **optional**.
- **BR7 — Guardrail confirm.** A **brief confirm** precedes recording, and it **reminds**
  that demolido / lot → **"Sin construir"**, so not-found is not used as a catch-all.
- **BR8 — Reversible.** A not-found can be **undone** before send; after send it is
  corrected by re-sending (full-replacement).
- **BR9 — Counts as resolved (CL-R6).** A not-found marks its R1 placa **resolved** (not
  pending) for manzana exhaustion, so the manzana / parada can reach 100%.
- **BR10 — Observación optional.** The surveyor may add a note (why it is absent); it is
  never required.
- **BR11 — Ownership.** Any route worker (titular or pareja) may declare it; the unsent
  record is theirs (CL4).
- **BR12 — Consecutive not-founds.** Several not-founds in a row are allowed; each advances
  the sweep. A not-found at the face end ends the face.
- **BR13 — Not-a-not-found (documented).** Demolido/baldío → "Sin construir" (Spec 12);
  re-numerado → real placa (Camaleón); not-accessible → exists; englobe → Camaleón
  (separate spec). The UI steers these away from the not-found path.

## Edge cases and error handling
- **Absent door before the anchor.** A door that is absent *before* the parada's first
  captured placa is not surfaced by the prediction, so it cannot be declared from the
  card. See **Open decisions** (likely acceptable: rare, SIG reconciles; or the anchor
  flow needs a way to flag leading absences).
- **Undo after close.** If the parada was closed (swept) with a not-found and it needs
  undoing, it follows the normal reopen path for a swept parada.
- **Degrade, never crash.** If the prediction is `indeterminada` (no direction yet) there
  is no "next expected placa", so the action is hidden — a not-found always refers to a
  concrete predicted placa.
- **Duplicate.** Re-declaring the same R1 placa not-found is idempotent (same
  `client_id`), never a second record.

## Data (app side)
- A not-found is stored in a **sibling `no_encontrados` table** (NE.3, schema v23) — NOT a
  flag on `captures`: a row carrying the predicted **`direccion_norm`** (+ `npn` when
  single-unit), **`manzana`** / `stop_id`, an optional observación, `ownerEmail` (CL4) +
  `syncStatus`, and a stable **`client_id`**. **No `posicion` / `loc`** — which keeps the
  `captures` table's hard, non-null **append-only `posicion` invariant** intact (27
  call-sites) and mirrors the backend's own `no_encontrados` table. It advances the local
  prediction cursor (NE.4) and rides the **same** push batch, but creates no census unit.
  (The "reuse" is of the `/field/capture/placas` batch, not the local table.)
- **Push:** the item sets `no_encontrado: true`, sends `manzana_catastral` +
  `direccion_norm` + `client_id` (+ optional `npn`), and **omits `posicion`**; `placa` is
  ignored. Full-replacement, idempotent by `client_id`.
- **Frame / sync:** read the `no_encontrados` list from the frame for resume/reopen; after
  sync the R1 placa returns `capturada=true` and leaves the typeahead automatically (the
  existing `capturada` / `version` path — no extra app logic). Undo = drop it from the
  batch → `capturada` reverts to `false`.

## Backend contract (resolved — 2026-10-09)
The backend reuses the **existing batch push** + the **`capturada` / `version`** mechanism
(Spec 15 / V4.8), so the app needs **no new endpoint** and **no new exhaustion/typeahead
logic**.
- **D1 — Representation.** `POST /field/capture/placas` item gains **`no_encontrado: bool`**.
  With `true`: the backend creates **no census_code** — it writes a negative row (table
  `no_encontrados`). The item sends **`manzana_catastral` + `direccion_norm` (the predicted
  placa) + `client_id`**; `npn` optional; **`placa` is ignored**. Idempotent by `client_id`.
- **D1b — No posición.** A `no_encontrado` item carries **no `posicion`** (`posicion` is now
  optional *for this case only*). A normal placa item without `posicion` still **422**s — so
  the push builder must **omit `posicion` only** for `no_encontrado` items.
- **D2 — Full-replacement + frame.** They travel in the same full-replacement push. The
  frame `GET /field/capture/route/{id}` returns a **`no_encontrados` list**
  (`client_id, npn, direccion_norm, manzana, stop/face, observacion`) alongside `items`, so
  resume / reopen show them.
- **D3 — Exhaustion.** A declared not-found flips its R1 placa to **`capturada=true`** in
  `GET /field/r1-directory` → it leaves the typeahead and the manzana can close at 100%.
  The directory **`version` moves** (altas/bajas), so the **normal sync** re-downloads it —
  exactly like `capturada` (Spec 15 / V4.8). No new app logic to hide or count.
- **D4 — Photo.** Exempt server-side automatically — there is no census_code for the gate.
- **Undo (BR8).** Dropping a not-found from the batch (full-replacement) removes the
  `no_encontrados` row and flips `capturada` back to **`false`** (a *baja*; `version`
  moves) — the same revert path proven for `capturada` in V4.8.

### Decisions (resolved)
- **Observación. ✅ CONFIRMED (backend, 2026-10-09): persisted.** The item's `observacion`
  is stored as `no_encontrados.observacion` and returned in the frame
  (`no_encontrados[].observacion`) — e.g. "demolido, hoy parqueadero" is available to SIG.
  BR10 is fully backed; nothing to add app-side beyond sending it.
- **D5 — Absence before the anchor. ✅ DECIDED (Jorge 2026-10-09): not declarable.** A door
  absent *before* the parada's first captured placa is not surfaced by the prediction, so
  it cannot be declared from the card (rare; SIG reconciles). The contract accepts a
  `no_encontrado` item regardless of order, so this can be enabled later **without** a
  backend change if the field shows it matters.

## Acceptance criteria
- On an assisted parada **with an anchor**, the prediction card offers **"No encontrada en
  campo"**; on a rural/unassisted parada (or before the anchor) it does **not**.
- Declaring a not-found shows the **guardrail confirm** (mentions "Sin construir"), and
  only records on **[Confirmar: no existe]**.
- A recorded not-found creates **no census unit / no `secuencia_parada`**, and the
  prediction **advances** to the next expected placa in the same direction.
- A not-found is **photo-exempt**, carries an **optional** observación, and is **queued**
  (works offline; sent on Enviar).
- The resume / parada view shows the not-found **distinctly** ("no encontrada") and lets it
  be **undone**.
- With every R1 placa either captured or declared not-found, the manzana/parada can
  **close at 100%** (CL-R6).

## BDD (Gherkin)
```gherkin
Feature: Declare a predicted placa not found in the field (negative record)

  Background:
    Given an assisted parada on manzana 327 with the R1 face [18, 20, 22, 26]
    And the surveyor has anchored it by capturing CALLE 13 # 3-18
    And the prediction card shows "siguiente: CALLE 13 # 3-20"

  Scenario: Declare a not-found and advance the sweep
    Given in the field there is no predio and no lot for 3-20
    When the surveyor taps "No encontrada en campo" and confirms
    Then a not-found is recorded against CALLE 13 # 3-20 with no census unit
    And no secuencia_parada or loc is consumed
    And the prediction card now shows "siguiente: CALLE 13 # 3-22"

  Scenario: The guardrail steers a demolition lot away from not-found
    Given 3-20 is a demolition lot (the terrain is there, no building)
    When the surveyor taps "No encontrada en campo"
    Then the confirm reminds to use "Sin construir" for a lot
    And when the surveyor cancels and picks "Sin construir"
    Then 3-20 is captured as a lote with the deduced placa, not a not-found

  Scenario: Declared offline, sent later
    Given there is no connectivity
    When the surveyor declares 3-20 not found
    Then it is recorded locally and queued
    And it is sent on the next Enviar, idempotent by client_id

  Scenario: Undo a not-found declared by mistake
    Given 3-20 was declared not found
    When the surveyor undoes it from the resume view
    Then 3-20 returns to predicted and the card points to it again

  Scenario: The action is not offered on a rural parada
    Given a rural/unassisted parada with no prediction
    Then the "No encontrada en campo" action is not shown

  Scenario: A not-found counts toward manzana exhaustion
    Given every other R1 placa of the manzana is captured
    When 3-20 is declared not found
    Then the manzana is accounted for at 100%
```

## Suggested tickets (small, atomic — each gated + committed + approved)
- **NE.1 — Spec** (this file) **+ wireframe** of the prediction card with the "No
  encontrada" action, the guardrail confirm, and the resume "no encontrada" row (dummy
  data, no style). Gate: renders.
- **NE.2 — Backend contract.** ✅ RESOLVED (2026-10-09): `no_encontrado: bool` on the placas
  item (no census_code, no `posicion`), a `no_encontrados` list in the frame,
  `capturada=true` + `version` for exhaustion/typeahead, photo-exempt, `observacion`
  persisted. See **Backend contract**. (D5 decided: not declarable before the anchor.)
- **NE.3 — Local model. ✅ DONE.** Sibling `no_encontrados` table (schema **v23**) +
  `appendNoEncontrado` / `watchNoEncontrados` / `noEncontradosForRoute` /
  `deleteNoEncontrado` (undo) on `CaptureRepository`, CL4-scoped, idempotent by
  `client_id`. No posicion/loc/census. 5 unit tests.
- **NE.4 — Prediction advance.** A not-found advances the local prediction to the next
  expected placa (client mirror), same direction; consecutive ones + face-end handled.
  Gate: tests (not-found → next; at end → end-of-face).
- **NE.5 — Prediction-card UI + guardrail confirm.** The "No encontrada en campo" action
  (only when a concrete next placa is predicted) + the brief confirm that mentions "Sin
  construir". Gate: tap → confirm → recorded, sweep advances.
- **NE.6 — Resume display + undo.** Not-found entries shown distinctly ("no encontrada");
  undo before send. Gate: visible + reversible.
- **NE.7 — Exhaustion (CL-R6).** A not-found counts as resolved so the manzana/parada can
  close at 100%. Gate: a manzana with a not-found reaches 100%.
- **NE.8 — Push + frame.** Send `no_encontrado: true` items (**omit `posicion`**); read the
  `no_encontrados` frame list; rely on `capturada` / `version` to hide + count + revert.
  Gate: E2E on Pitalito.
- **NE.9 — Tests + emulator E2E.** Full flow on Pitalito Ruta 10 (declare, advance, undo,
  offline, exhaustion). Gate: `flutter test` green + manual E2E.
