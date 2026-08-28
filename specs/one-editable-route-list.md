# Spec 1.1 — One editable list per route

Status: draft, awaiting approval
Type: Mobile app (Flutter). No backend work: no endpoint changes, no new wire.
Why it exists: Spec 1 shipped a resume view without noticing the app already
had a second list of the same route. This closes that duplication.

## User story
**As** a field worker who already walked part of a route, **I want** to fix or
fill in the address of a unit I captured earlier, from the same list I use to
resume the route, **so that** I can correct what I got wrong at the door
without having to know a second, different list exists somewhere else.

## Objective
Collapse the two lists into one. The resume view becomes *the* list of a
route: it shows what has been captured and lets the worker correct it.

## Background — what is wrong today
- `resume_route_screen.dart` (Spec 1): designed, read-only. It is the first
  thing the worker sees after opening a route.
- `capture_list_screen.dart` (pre-existing): undesigned, editable through a
  dialog, reachable only from an icon inside the capture screen.

The list the worker meets first is the one that cannot fix anything, and the
one that can is hidden one screen deeper. A unit captured with no placa —
which the contract explicitly allows — therefore looks uncorrectable.

## Scope

**Includes**
- Tapping a unit in the resume view opens an editor for `placa`,
  `tipo_acceso`, `manzana_catastral` and `observacion`.
- Saving marks the row `pending`; the later push is idempotent by `client_id`,
  so a unit that came from the server is updated in place, never duplicated.
- Editing works offline: it only touches the local database.
- `capture_list_screen.dart` is deleted.
- Every path into a route lands on the resume view first, including the manual
  `route_id` entry on Home, so the capture screen is always reached from it
  and no longer needs its own list icon.

**Does NOT include**
- Deleting units. The contract has no delete, and `orden` is append-only.
- Changing `orden` or `loc` — assigned by the app and the backend
  respectively, never by the worker (BR4).
- Push mechanics beyond marking the row `pending` (Spec 3).
- The extended survey (PH/PV, hogar, medidor), media, or any coordinate.

## Actors and permissions
Field worker, same `field_token` as Spec 1. No new permission.

## Preconditions
A route is open in the resume view with at least one captured unit, whether it
arrived from the server frame or was captured on this device.

## Trigger
The worker taps a unit in the resume view.

## Main flow (happy path)
1. In the resume view, the worker **taps the row** of a unit showing
   "Sin dirección aún".
2. An editor opens with the current values and the unit's `orden` visible but
   not editable.
3. The worker types the address into `placa` and saves.
4. The row updates in place, keeps its position in the walking order, and now
   shows the "sin enviar" badge.
5. The next push sends it with the same `client_id`; the backend updates the
   existing `census_code` rather than creating another.

## Alternative flows (sad paths)
- **A1 — Cancel**: leaving the editor without saving changes nothing and the
  row keeps its previous sync state.
- **A2 — Blank placa**: clearing the field saves `null`. A unit with no placa
  is valid; the row goes back to reading "Sin dirección aún".
- **A3 — Offline**: the edit is stored and marked `pending`. Nothing is sent
  until there is signal.
- **A4 — Editing a row in `error`**: saving clears the previous sync error and
  marks it `pending` again, so a failed unit can be corrected and retried.

## Business rules
- **BR1** `orden` is never editable, anywhere in the UI. It is append-only and
  defines the walking order.
- **BR2** `loc` is the backend's to assign (`loc = orden × 5`); the app only
  displays it.
- **BR3** Any edit marks the row `pending`. Correctness comes from
  `client_id` idempotency, not from the app trying to guess what changed.
- **BR4** Editing a unit that originated on the server is allowed and is in
  fact the main case: filling in a placa the office does not have.
- **BR5** One list per route. If a second view of the same data appears again,
  it is a defect.
- **BR6** Coordinate-free: the editor has no coordinate field.

## Edge cases and error handling
- A synced unit with `placa = null` — the reason this spec exists — is
  editable like any other.
- Editing a unit and editing it again before any push: the row stays a single
  `pending` row; only the latest values are sent.
- A unit edited locally while the server also changed it: the push wins, since
  the contract's upsert takes the app's values as the newer truth.
- An empty route has nothing to tap; the empty state is unchanged.

## Acceptance criteria
- Tapping a unit in the resume view opens the editor.
- `placa`, `tipo_acceso`, `manzana_catastral` and `observacion` can be edited;
  `orden` is displayed and cannot be changed.
- Saving updates the row in place, preserves its order, and shows the
  "sin enviar" badge immediately.
- A blank placa is stored as null and the row reads "Sin dirección aún".
- Editing works with no network.
- `capture_list_screen.dart` no longer exists, and no screen offers a second
  list of the same route.
- Opening a route from Home's manual `route_id` field lands on the resume
  view, the same as opening it from the selector.
- `flutter analyze` clean, `flutter test` green, and a manual check on route
  10 filling in one of its two blank addresses.

## BDD (Gherkin)
```gherkin
Feature: One editable list per route

  Scenario: Fill in a missing address
    Given a synced unit with no placa in the resume view
    When the worker taps it, types an address and saves
    Then the row shows that address in the same position
    And it is marked "sin enviar"

  Scenario: The order cannot be changed
    Given any unit in the editor
    When the worker looks for a way to change its orden
    Then there is none, and orden is shown as read-only

  Scenario: Clearing the address is allowed
    Given a unit with a placa
    When the worker clears the field and saves
    Then the unit is stored with placa null
    And the row reads "Sin dirección aún"

  Scenario: Editing offline
    Given no connectivity
    When the worker edits a unit and saves
    Then the change is stored locally and marked pending
    And nothing is sent until there is signal

  Scenario: Re-pushing an edited server unit does not duplicate
    Given a unit that came from the server frame and was edited locally
    When the queue is pushed
    Then the backend updates the same census_code by client_id
    And no second unit is created

  Scenario: There is only one list
    Given a route open in the app
    When the worker looks for the list of what is captured
    Then the resume view is the only one, and it is editable
```

## Suggested tickets
- **T1.1.1 — Editor in the resume view**: move the existing edit dialog behind
  a tap on the row; show `orden` read-only.
- **T1.1.2 — Delete the duplicate**: remove `capture_list_screen.dart` and the
  list icon in the capture screen.
- **T1.1.3 — Single entry path**: Home's manual `route_id` opens the resume
  view instead of the capture screen.
- **T1.1.4 — Manual check**: fill in one of route 10's blank addresses and
  confirm the badge, the order and the push.
