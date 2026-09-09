# Spec 2.1 — Move a unit's localización

Status: draft, awaiting approval
Type: Mobile app (Flutter). The wire already exists: `ins_after` shipped on
`feature/extended-census` and is migrated and tested on the backend.
Supersedes: the open decision in [Spec 2](strict-order-capture.md) about how a
"belongs after" note is recorded. Both options there — free text and a text
token in `observacion` — are dead. The backend gave the field a type instead,
which is better than either: nothing to parse and nothing to accidentally
overwrite when the worker edits an observation.

## User story
**As** a field worker who skipped a house and noticed a few doors later, **I
want** to capture it now and mark where it actually belongs, **so that** the
office can put it in its place without me renumbering anything or losing the
walk order.

## Goal
Let the worker record a relocation intent as data, in one tap-through, without
typing a number and without touching any unit already captured.

## Wire contract consumed (source of truth — do not change from the app)

### `POST /field/capture/placas` — new per-item field
```json
{ "client_id": "<uuid>", "orden": 6, "placa": "K 9 9-77",
  "ins_after": 10, "observacion": "junto al poste" }
```
- `ins_after`: `int | null`, range **0–9999**. It is a **`loc`**, not an
  `orden`. `0` means the start of the route. Omitted or null means nothing
  pending.
- The upsert by `client_id` also writes it: re-pushing **with** it sets it,
  re-pushing **without** it **clears** it.
- Out-of-range rejects the **whole batch** with **422** — a body validation,
  not a per-item error like an invalid `orden`.
- `observacion` goes back to being a purely human note.

### `GET /field/capture/route/{route_id}` — frame items now carry `ins_after`
Used on resume to show which units are still awaiting relocation.

### Who executes the move
**The office, never the app.** The operator applies the shift and the flag
clears. The next frame returns the unit at its final `loc` with
`ins_after = null`. **The frame is the source of truth on resume: local `loc`
values do not necessarily survive reconciliation.**

## Scope

**Includes**
- A "Mover localización" action on a captured unit.
- A picker over the route's own units — the worker chooses *after which unit*
  this one goes, seeing `placa` and `orden`, and never types a number. Plus a
  dedicated "Al inicio de la ruta" option.
- A marker in the list for units with a pending relocation, naming the anchor.
- Clearing the mark.
- Persisting `ins_after` locally and carrying it on every push of that row.
- Reading `ins_after` back from the frame, so a mark set on another device — or
  cleared by the office — shows correctly.

**Does NOT include**
- Executing the shift. That is the office's, by explicit contract.
- The v1 text token in `observacion`. It was never implemented here; it is dead
  on both sides.
- PH/PV, `/sync/*`, coordinates.

## Actors and permissions
Field worker with a `field_token`, on a route of their ESP.

## Preconditions
The route is open in the resume view and has at least one captured unit. To
mark *after* something, at least one other unit must exist; on a route with a
single unit only "Al inicio de la ruta" makes sense.

## Trigger
The worker opens a unit and chooses "Mover localización".

## Main flow (happy path)
1. The worker captures the missed house at the end, as always (append-only).
2. On that unit they choose **"Mover localización"**.
3. A picker lists the route's units in walking order, each showing its `placa`
   (or "Sin dirección aún") and its `orden`, plus **"Al inicio de la ruta"**.
4. They pick the unit this one goes after.
5. The app stores the anchor's **`loc`** as `ins_after` (see BR2) and marks the
   row pending.
6. The list shows the unit with a marker naming the anchor, e.g. `→ tras Calle
   5 # 12-34`.
7. On the next send, `ins_after` travels with the item.
8. Once the office applies the shift, the next frame brings the unit at its
   final `loc` with no mark, and the app follows the frame.

## Alternative flows (sad paths)
- **A1 — Marking before ever syncing**: both the marked unit and its anchor are
  in the same batch. The anchor's `loc` does not exist yet, so the app sends
  `orden × 5`, which is exactly what the backend assigns it in that same
  request (BR2).
- **A2 — Marking after syncing**: the anchor already has a server `loc`; that
  value is used verbatim, not recomputed.
- **A3 — Editing the placa of a marked unit**: the edit re-queues the row, and
  the push **must carry its current `ins_after`** or the backend clears it.
  This is the trap the contract warns about, and Spec 1.1's editor is exactly
  the path that walks into it.
- **A4 — Removing the mark**: the row is re-pushed without `ins_after` and the
  backend clears it.
- **A5 — Anchoring to a unit the server rejected**: the anchor never gets a
  `loc`, so `ins_after` points at a `loc` that does not exist. The backend
  accepts it (it is only an integer) and the office sees a dangling reference.
  The app warns rather than blocks: the worker's intent is still information.
- **A6 — Out-of-range value**: cannot be produced through the picker, but is
  validated before sending anyway. A single bad item would cost the **entire
  batch** a 422, so it is worth a client-side guard.
- **A7 — The office already moved it**: the frame comes back with
  `ins_after = null` and a new `loc`. The frame wins; the local mark clears.

## Business rules
- **BR1** The worker never types a number. `ins_after` is always derived from a
  unit they pointed at, or from "Al inicio de la ruta" (`0`).
- **BR2** `ins_after` is a **`loc`**. The app uses the anchor's stored `loc`
  when it has one, and falls back to `orden × 5` only for a unit that has never
  synced — correct because the backend assigns exactly that in the same batch.
  Blanket `orden × 5` would be wrong for any unit the office already relocated,
  which is precisely the population this feature creates.
- **BR3** `ins_after` is persisted locally and rides on **every** push of that
  row, until the office clears it. Omitting it on a re-push deletes it.
- **BR4** Marking never modifies any other unit. `orden` stays append-only.
- **BR5** The frame is the source of truth on resume, for both `loc` and
  `ins_after`.
- **BR6** Validate `0–9999` before sending: an invalid value costs the whole
  batch, not just its item.
- **BR7** Coordinate-free.

## Edge cases and error handling
- A unit cannot be anchored to itself; it is excluded from its own picker.
- A route with one unit offers only "Al inicio de la ruta".
- Two units marked after the same anchor: allowed. The office decides the
  resulting order; the app does not invent one.
- A unit already marked and marked again simply replaces its anchor.
- A `loc` of `0` is a real value (start of route), not "no value". It must
  never be conflated with null.

## Implementation constraints found in review
- **Schema migration.** `insAfter` is a new nullable column on `Captures`. The
  database is at `schemaVersion = 1` with **no `MigrationStrategy` defined**, so
  bumping it needs one written from scratch; without it an installed app breaks
  on upgrade instead of gaining a column.
- **Push path.** `SyncService.pushPending` builds `PlacaItemRequest` per row and
  must include `insAfter`, or BR3 is violated silently on every retry.
- **Frame merge.** `mergeFrame` must write `ins_after` back, including writing
  `null` over a local mark the office has cleared (BR5).

## Acceptance criteria
- A unit can be marked with the unit it goes after, chosen from a list, with no
  number typed anywhere.
- "Al inicio de la ruta" produces `ins_after = 0`, distinct from unmarked.
- A marked unit shows a marker naming its anchor.
- The mark can be removed.
- The mark survives an edit of the unit's placa and every retry.
- Resuming reflects the frame: the office clearing a mark clears it locally.
- Marking modifies no other unit's `orden`.
- `flutter test` green, including the anchor-`loc` rule and `ins_after`
  surviving a re-push, plus a manual check on route 10: mark, send, and see it
  come back in the frame.

## BDD (Gherkin)
```gherkin
Feature: Move a unit's localización

  Scenario: Mark a missed house
    Given a unit captured at the end of the route
    When the worker chooses "Mover localización" and picks the unit it goes after
    Then the unit is marked with that unit's loc
    And no other unit is modified

  Scenario: The worker never types a number
    When the picker is open
    Then it lists the route's units with their placa and orden
    And offers "Al inicio de la ruta"
    And offers no numeric field

  Scenario: Anchoring to a unit that has not been sent yet
    Given the anchor has never synced and has no loc
    When the marked unit is pushed in the same batch
    Then ins_after is the anchor's orden times five

  Scenario: Anchoring to a unit the office already relocated
    Given the anchor came back from the frame with a loc that is not orden times five
    When the worker anchors to it
    Then ins_after is that loc, not the recomputed value

  Scenario: Correcting the placa of a marked unit
    Given a marked unit
    When the worker edits its placa and it is pushed again
    Then ins_after travels with it
    And the mark is not cleared

  Scenario: The office applies the shift
    Given a marked unit that was sent
    When the office relocates it and the worker refreshes
    Then the unit shows its new loc
    And it carries no mark

  Scenario: Removing the mark
    Given a marked unit
    When the worker removes the mark and it is pushed
    Then the backend clears ins_after
```

## Suggested tickets
- **T2.1.1 — Schema**: `insAfter` column, `schemaVersion` 2 and the first
  `MigrationStrategy`.
- **T2.1.2 — DTOs**: `ins_after` on the request item and on the frame item,
  with tests for `0` versus null.
- **T2.1.3 — Repository**: set and clear the mark; resolve the anchor's `loc`
  per BR2.
- **T2.1.4 — Push and merge**: carry `insAfter` on every push (BR3); write it
  back from the frame including nulls (BR5).
- **T2.1.5 — Wireframe**: the action, the picker and the list marker.
- **T2.1.6 — Design**: theme pass.
- **T2.1.7 — Implementation and manual check** on route 10.
