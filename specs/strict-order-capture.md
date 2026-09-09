# Spec 2 — Strict-order placa capture

Status: draft, awaiting approval
Type: Mobile app (Flutter). No backend work for what is in scope; one item is
blocked on a contract gap that has been reported.
Chain: Spec 1 → 1.1 → 3 → **2 (this one)** → 4 offline-first queue and retry.

> **This spec is mostly a review.** The capture pass was built before the
> spec-driven workflow started and already ships. Writing the spec after the
> fact is worth it anyway: it is what surfaced the gaps below, and it records
> the three things we decided *not* to build and why, so they are not
> attempted later as if they had been overlooked.

## User story
**As** a field worker walking a route door to door, **I want** to register each
unit in the exact order I walk it, quickly and without being able to break the
sequence, **so that** the office can reconstruct the walk as it happened —
there are no coordinates to recover it from.

## Goal
Keep the capture order faithful and append-only, enforced by the app rather
than by the worker's memory, and give the worker an honest way out when they
notice a missed house.

## What already holds (verified in review)
- `orden` is computed in the repository as `max(orden) + 1` per route. The UI
  never supplies it and offers no way to edit it, on any screen.
- `placa` is optional and a blank one is stored as `null`, which the contract
  allows (a unit with the address still deferred).
- `manzana_catastral` persists between captures of the same block; everything
  else clears for the next household.
- `loc` and `ph`/`pv` are the backend's in this pass: the app neither computes
  nor sends them.
- Captures are local first; nothing leaves the device until the worker sends
  (Spec 3, BR1).

## Scope

**Includes**
- The capture form as it stands, specified rather than rewritten.
- **Queue visibility while capturing.** Removing the sync icon in Spec 3 also
  removed the pending count from this screen, so a worker can capture thirty
  units with no signal of how much is unsent without navigating back.
- **The missed-house procedure**: capture the house at the end of the queue and
  record where it belongs, so the office can re-sequence. One entry, nothing
  destroyed.

**Does NOT include** — each one decided, not forgotten

- **Mid-route insert.** `census-field-operations.md:57` says the gaps of 5
  exist to insert a missed domicile (a `loc` 7 between 5 and 10) without
  renumbering, and `field-capture-api.md:34` leaves that to the app. The app
  cannot do it: `POST /field/capture/placas` takes an integer `orden` and the
  backend computes `loc = orden × 5`, so **`loc` 7 is unreachable** — no
  integer `orden` produces it. Reported to the backend; until the contract can
  express an insert, the procedure below stands in for it.
- **Cascade shifting to fake an insert** — appending a row and moving every
  address one position forward until the gap lands where the missed house goes.
  It works mechanically and renumbers nothing, but it moves the houses *between*
  the identifiers: `loc` 25 stops meaning one address and starts meaning
  another. Anything already linked to that `census_code` (the NPN matcher, an
  observation, a meter) then points at the wrong house. It is also O(n) manual
  edits in the street, where a single slip silently swaps two houses, and it
  re-queues rows the server had already confirmed.
- **Simultaneous capture by titular and pareja on one route.** `orden` is a
  route-global counter that also encodes physical walk order; two devices each
  computing `max + 1` collide by construction, and the server rejects one item
  (contract A2). Letting the server assign `orden` on arrival would order the
  route by upload time instead of by walk, which destroys the invariant the
  census rests on. The sound answer is **route segments** — already a concept
  in this domain, and deferred on purpose. In practice one worker covers a
  route and the companion assists without capturing.
- **Absent, skip and order override.** Those guards belong to the **survey
  pass** (`census-field-operations.md:68`, §4), not to the placa pass.
- **PH/PV generation.** The survey pass declares structure with buttons and the
  app generates PH/PV under the sentinel convention. That is the observation
  layer, travels by `/sync/*`, and is out of scope here — in *this* pass
  `ph`/`pv` stay at the provisional `00`.

## Actors and permissions
Field worker with a `field_token`, on a route of their ESP in state
`verificada`.

## Preconditions
The route is open in the resume view; the worker reaches capture from there.

## Trigger
The worker stands at a door and taps "Capturar".

## Main flow (happy path)
1. The form shows the last captured unit as the anchor for checking against the
   door, and the `orden` about to be assigned.
2. The worker types the `placa` read at the door, optionally the access type and
   an observation, and saves.
3. The row is stored locally with the next `orden`, marked pending.
4. The form clears for the next household, keeping `manzana_catastral`, and the
   focus returns to `placa`.
5. The pending count on screen goes up, so the worker can see the queue growing
   without leaving the form.

## Alternative flows (sad paths)
- **A1 — Door with no readable placa**: saved blank. The unit exists with
  `placa = null` and reads "Sin dirección aún" in the list, to be filled in
  later from the same list (Spec 1.1).
- **A2 — A missed house, noticed later**: the worker captures it **at the end**
  and records that it belongs after a given placa. The `orden` stays
  append-only and nothing already captured is touched. The office re-sequences
  using that note.
- **A3 — Offline**: identical. Capture never needs the network.
- **A4 — Double tap on save**: guarded; one capture per tap.

## Business rules
- **BR1** `orden` is assigned by the repository, is monotonic per route, and is
  **append-only**. It is never editable, anywhere.
- **BR2** The app enforces the order, not the worker's memory. If the app let
  the order be edited freely, the office's inference would corrupt
  (`census-field-operations.md:53`).
- **BR3** `loc` and `ph`/`pv` belong to the backend in this pass.
- **BR4** A missed house is **added, never inserted by moving others**. The
  correction is recorded as data, not performed by rewriting neighbours.
- **BR5** Capture works fully offline; sending is a separate, deliberate act
  (Spec 3).
- **BR6** Coordinate-free.

## Superseded decision — how the "belongs after" note is recorded
The note has to reach the office in a form it can act on.

- **Free text in `observacion`** costs nothing to build and everything to
  parse: the office reads "va después de la casa azul" and guesses.
- **A structured hint**: the worker picks the placa it goes after from the
  route's own list, and the app writes a normalised line into `observacion`
  (e.g. `[insertar-después-de: loc 25]`). Deterministic for the office, one
  extra tap for the worker, and it needs no contract change because it rides
  in a field the contract already carries.

**Resolved, and neither option won.** The backend added a typed `ins_after`
field to the contract instead, which beats both: nothing for the office to
parse, and nothing to clobber when the worker edits an observation. See
[Spec 2.1](relocate-unit.md). `observacion` stays a purely human note.

## Edge cases and error handling
- First capture of an empty route is `orden` 1.
- The frame re-pulled mid-capture may raise the local maximum (units captured
  earlier and synced); the next `orden` follows from it, never backwards.
- Two captures with the same placa are allowed: the contract constrains
  `orden`/`loc`, not the address text.
- A worker who realises the miss immediately, before saving the next house, has
  no problem to solve — they simply capture it now.

## Acceptance criteria
- `orden` is monotonic, append-only, and unreachable from the UI.
- A blank `placa` is stored as null.
- `manzana_catastral` persists between captures; the other fields clear.
- The pending count is visible while capturing.
- A missed house can be captured at the end with a note recording where it
  belongs, without touching any existing row.
- Capture works with no network.
- `flutter test` green, plus a manual check on route 10: capture a unit
  offline, see the count rise, and confirm the order after sending.

## BDD (Gherkin)
```gherkin
Feature: Strict-order placa capture

  Scenario: Capture in walk order
    Given a route whose last captured unit is orden 4
    When the worker saves a new placa
    Then it is stored as orden 5
    And the form clears for the next household keeping the manzana

  Scenario: The order cannot be edited
    Given any captured unit
    When the worker looks for a way to change its orden
    Then no screen offers one

  Scenario: A door with no readable placa
    When the worker saves with the placa blank
    Then the unit is stored with placa null
    And it reads "Sin dirección aún" in the route list

  Scenario: A missed house noticed three doors later
    Given the worker realises a house was skipped
    When they capture it at the end and record that it goes after a given placa
    Then it takes the next orden
    And no previously captured unit is modified

  Scenario: Capturing with no connection
    Given no connectivity
    When the worker captures three units
    Then all three are stored locally and queued
    And nothing is sent until they ask for it

  Scenario: Seeing the queue without leaving the form
    Given four unsent units
    When the worker is on the capture form
    Then the pending count is visible there
```

## Suggested tickets
- **T2.1 — Pending count on the capture screen**: show the queue without
  offering a second send control (Spec 3, BR2 keeps sending in one place).
- **T2.2 — moved to [Spec 2.1](relocate-unit.md)**, which supersedes it with the
  typed `ins_after` field.
- **T2.3 — Tests**: `orden` append-only across an interleaved merge, blank
  placa, manzana persistence.
- **T2.4 — Manual check** on route 10.
