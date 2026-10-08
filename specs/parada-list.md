# Spec 16 — Parada list (sequential, hard-locked route navigator)

> Status: **Draft** — spec phase. Branch `feature/parada-list` (to create).
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.
> Relates to: **Spec 10 / parada-scoped capture** (paradas, `swept`, `currentParada`,
> `markSwept`), **Spec 11 / secuencia_parada** (per-parada "predio N"),
> **open-and-resume-route** and **route-state-locks**. Builds on the strict-order
> invariant (see the `strict-sequential-order` project note): the order of paradas
> and placas is the non-negotiable core of the levantamiento phase.

## User story
As a **field surveyor (encuestador)**, after I pick a route I want to see **its list
of paradas in recorrido order**, with the one I'm on clearly marked and the rest
locked, so I always know where I am, what's left, and I physically sweep them **one by
one in strict order** — never skipping ahead.

## Objective
Insert a **parada-list screen between route selection and capture**. It renders the
route's paradas ordered by `faceSequence`, marks each as **done / current / pending**,
and lets the surveyor open **only the current** parada for capture. Closing the current
parada ("Cerrar esta parada") unlocks the next. This is a **hard lock**: there is no
skip and no "open anyway". It is largely a **presentation layer over state that already
exists** (`Paradas.swept`, `ParadaRepository.currentParada`, `markSwept`).

## Scope

### Includes
- A new **ParadaListScreen** reached when the surveyor opens a route.
- One row per parada, ordered by `faceSequence`, each showing:
  - **Parada N** (its `faceSequence`),
  - **state**: ✅ barrida (`swept`) · 🔵 en curso (the current parada) · 🔒 pendiente,
  - the **manzana** label (`manzanaLabel`) and, when present, the face terna /
    orientation / geo-ref hint (the same fields the capture context card shows),
  - the **count of placas captured** in that parada (captures grouped by `stop_id`),
    and an "N sin enviar" marker when any are queued.
- **Route-level header**: progress (`barridas / total` paradas) and the existing
  **Enviar** action + "N sin enviar · M fotos" summary (moved/shared from the resume
  screen).
- **Tap behaviour (hard lock):**
  - 🔵 current → opens **CaptureScreen** for that parada (today's capture flow).
  - ✅ done → opens a **read-only** view of that parada's captures (no new capture).
  - 🔒 pending → **not tappable** (disabled, with a one-line "se desbloquea al cerrar
    la anterior" hint on long-press/tap-feedback).
- **Close empty face:** the current parada can be closed with **0 placas** ("barrida,
  0 placas") to advance — a legitimately empty / non-censable face must not trap the
  surveyor. Reuses `markSwept(swept: true)`.
- **Resume:** re-entering a route lands on the parada list with the current parada
  highlighted; opening it resumes capture exactly where it was left.

### Does NOT include (explicit out of scope)
- **Reopening a closed parada** / inserting a missed placa (reinsertion). Deferred to a
  future spec; `markSwept(swept: false)` exists in the repo but is **not exposed** in
  this list for v1. See the `parada-list-and-reinsertion` note.
- **Any skip / "open anyway" / out-of-order** entry. A difficulty in the field means
  the surveyor **stops this route and switches to another** — never jumps within a
  route.
- Changing the **capture screen** itself (it already knows its parada), the capture
  contract, `loc`/`secuencia_parada` computation, or anything backend-side.
- The **survey/encuesta** phase ("Levantar encuesta") and unit editing.
- Route selection, login, ESP switching (upstream screens, unchanged).
- Map / coordinates (coordinate-free, always).

## Actors and permissions
- **Surveyor (titular or pareja)** with a valid `field_token`, viewing a route from
  `GET /field/routes` in state `verificada`. Same auth as today; no new permission.

## Preconditions
- A route is selected and its paradas are available locally (`refreshStops` ran, or a
  cached set exists). A route with **no paradas** is an unassisted/classic route and
  falls back to today's single capture flow (no list).
- `placas_estado = abierta` for the route (a closed route shows the list read-only;
  see route-state-locks).

## Trigger
- The surveyor taps a route in the route selector.

## Main flow (happy path)
1. Surveyor taps a route → **ParadaListScreen** opens.
2. The list shows all paradas ordered by `faceSequence`. Paradas below the current are
   ✅, the current (lowest unswept) is 🔵, the rest are 🔒.
3. Surveyor taps the **🔵 current** parada → **CaptureScreen** for it.
4. Surveyor captures placas in order (existing flow), then taps **"Cerrar esta parada"**.
5. `markSwept(swept: true)` runs; the app returns to the list. The just-closed parada
   is now ✅ and the **next** parada is 🔵.
6. Repeat 3–5 until all paradas are ✅.
7. When every parada is ✅, the header shows **"Ruta barrida — N/N"**; the surveyor
   sends with **Enviar** (if anything is still queued) and leaves the route.

## Alternative flows (sad paths)
- **A1 — Empty/inaccessible face (legit empty):** on the current parada the surveyor
  finds no predios. They tap **"Cerrar esta parada"** with 0 placas → it closes
  (barrida, 0 placas), next unlocks. (Capture button via the list; close via the
  capture screen.)
- **A2 — Difficulty mid-route (gate locked, dog, obra):** the surveyor does **not**
  skip. They leave the route (Back to selector) with the current parada still 🔵 and
  go start/continue **another** route. Returning later resumes at the same 🔵 parada.
- **A3 — Taps a 🔒 pending parada:** nothing opens; a brief hint explains it unlocks
  when the previous one is closed. (Enter via the keyboard "submit"/tap both inert.)
- **A4 — Offline:** the list renders from the local `Paradas`/`captures`; `swept` is
  optimistic-local so closing still advances. `Enviar` is disabled/queued until online
  (existing behaviour).
- **A5 — Sweep rejected by backend (409 / foto_obligatoria_pendiente):** the existing
  `sweepRejectionsProvider` banner surfaces on the list; the rejected parada reverts to
  🔵 so the surveyor fixes it (this is the one backend-driven re-open, already in
  route-state-locks — not a user-initiated reopen).

## Business rules
- **BR1 — Strict order, hard lock.** Exactly one parada is open at a time: the lowest
  `faceSequence` with `swept = false` (`currentParada`). All earlier are ✅, all later
  are 🔒 and non-interactive.
- **BR2 — Close is the only unlock.** Only `markSwept(swept: true)` on the current
  parada advances the current pointer. No other action reorders or unlocks.
- **BR3 — No skip, no in-route override.** There is no UI to open a non-current parada
  for capture. Field difficulty → switch route.
- **BR4 — Empty close allowed.** A parada may be closed with 0 placas.
- **BR5 — No user reopen (v1).** A ✅ parada opens read-only. The only re-open is the
  backend sweep-rejection path (BR/route-state-locks), not a surveyor action.
- **BR6 — Order source.** Parada order is the backend's `faceSequence`; the app never
  reorders.
- **BR7 — No-paradas fallback.** A route with zero paradas uses today's classic capture
  flow (no list) — the feature is additive, never a regression for such routes.

## UI states
- **Loading:** stops being fetched/resumed → skeleton/spinner.
- **List (normal):** the ordered paradas with ✅/🔵/🔒 + progress header + Enviar.
- **Empty:** route has paradas = 0 → fall back to classic capture (no list screen), or
  (if that is undesired) a one-line "esta ruta no tiene paradas" + the classic Capturar
  entry. (Decision D2 below.)
- **All done:** every parada ✅ → "Ruta barrida — N/N", Enviar if queued.
- **Network error (stops pull failed, nothing cached):** error state with retry,
  consistent with open-and-resume-route; never blocks a cached list.

## Edge cases and error handling
- **Partner (pareja) already swept a parada:** on `refreshStops`, a parada may arrive
  `swept = true` from the backend → shows ✅ and the current pointer accounts for it.
- **Local optimistic close not yet synced** (`sweptSynced = false`): still ✅ locally;
  the pending sweep rides the next Enviar.
- **A ✅ parada with 0 placas** (closed empty): shows ✅ with "0 placas".
- **Route closed (`placas_estado != abierta`):** list is read-only; the 🔵 current (if
  any) is not openable for new capture (route-state-locks governs the gate + chip).
- **Reaching the last parada:** closing it leaves no 🔵; header → all-done.

## Data (per the existing model — no new columns)
- From `Paradas`: `stopId`, `faceSequence`, `manzana`, `orientation`/terna fields,
  `swept`, `sweptSynced`, geo-ref.
- From `captures` grouped by `stopId`: count + `sync_status` rollup per parada.
- `currentParada(routeId)` and `routeStopsProvider` already expose the needed state.

## Assumptions & open decisions
- **D1 — Navigation integration. ✅ DECIDED (Jorge, 2026-10-05): REPLACE.** The parada
  list **replaces** `resume_route_screen` as the route's landing screen. The route-level
  **Enviar** + send-summary move onto the list header; a parada row drills into its
  captures (current → CaptureScreen; done → read-only). `resume_route_screen` is retired
  as the route home (its captures-list view is absorbed into the done-parada read-only
  view). Implemented in PL.4.
- **D2 — No-paradas routes. ✅ DECIDED + implemented (PL.7): skip.** A route with
  genuinely 0 paradas auto-skips the list and opens the classic capture flow (BR7). The
  only nuance: the skip waits for the opening sync to resolve online (so empty = real,
  not mid-load); offline/failed sync keeps a manual one-tap fallback, never a blind skip.
- **D3 — Done-parada tap.** Proposed: read-only captures view. Confirm (vs. not tappable
  at all).
- **D4 — Close empty from where.** "Cerrar esta parada" lives in the CaptureScreen
  today; closing an empty face means opening the 🔵 parada then closing it with 0
  placas. Confirm this is acceptable, or add a "cerrar vacía" affordance on the list row
  for the current parada.

## Acceptance criteria
- Opening a route with paradas shows the ordered list with exactly one 🔵 (the lowest
  unswept), earlier ✅, later 🔒.
- Only the 🔵 parada opens for capture; 🔒 rows do nothing; ✅ rows open read-only.
- Closing the current parada (incl. with 0 placas) marks it ✅ and promotes the next to
  🔵, with no way to open a later parada before its predecessors are ✅.
- Leaving and re-entering the route returns to the list with the same 🔵.
- A route with no paradas behaves exactly as today (no list, classic capture).
- `flutter analyze` clean, `flutter test` green, verified on the emulator against the
  Pitalito routes (Ruta 10 = 14 paradas, Ruta 20 = 1 parada).

## BDD (Gherkin)

```gherkin
Feature: Parada list with strict sequential hard lock

  Background:
    Given I am signed in as a surveyor
    And I selected a route with paradas 1..N ordered by faceSequence
    And paradas before the current are swept

  Scenario: The list marks exactly one current parada
    When the parada list opens
    Then paradas below the current show "barrida"
    And the lowest unswept parada shows "en curso"
    And every parada above it shows "pendiente" and is not tappable

  Scenario: Only the current parada opens for capture
    When I tap the "en curso" parada
    Then the capture screen for that parada opens
    When I go back and tap a "pendiente" parada
    Then nothing opens
    And I see a hint that it unlocks when the previous parada is closed

  Scenario: Closing the current parada unlocks the next (strict order)
    Given I am capturing in the current parada
    When I tap "Cerrar esta parada"
    Then that parada becomes "barrida"
    And the next parada by faceSequence becomes "en curso"
    And I cannot open any later parada before it

  Scenario: Closing a genuinely empty face
    Given the current parada has no predios to capture
    When I close it with 0 placas
    Then it becomes "barrida" with "0 placas"
    And the next parada becomes "en curso"

  Scenario: Difficulty does not allow skipping
    Given the current parada is inaccessible
    Then there is no control to skip it or open a later parada
    And I leave the route and may open another route instead
    When I return to this route later
    Then the same parada is still "en curso"

  Scenario: Resume lands on the current parada
    Given I captured some paradas earlier and left
    When I re-open the route
    Then the parada list shows the lowest unswept parada as "en curso"

  Scenario: A route with no paradas uses the classic flow
    Given the selected route has zero paradas
    When I open it
    Then no parada list is shown
    And the classic capture flow opens as before
```

## Suggested tickets (small, atomic — each gated + committed + approved)
- **PL.1 — Spec** (this file) + wireframe of the 5 list states (data dummy, no style):
  loading / list (✅·🔵·🔒) / all-done / empty-fallback / network-error. Gate: renders.
- **PL.2 — `ParadaListScreen` read-only render.** Build the ordered list from
  `routeStopsProvider` + `currentParada`, with state chips and per-parada placa counts.
  No navigation yet. Gate: shows correct states for Ruta 10/20.
- **PL.3 — Hard-lock navigation.** 🔵 → CaptureScreen; ✅ → read-only; 🔒 inert + hint.
  Gate: cannot open a non-current parada.
- **PL.4 — Route-home integration (D1).** Make the list the route landing; move the
  Enviar + send-summary header onto it; wire Back → selector. Gate: send still works.
- **PL.5 — Close flow + advance.** Confirm "Cerrar esta parada" (incl. 0 placas) marks
  swept and the list promotes the next 🔵 on return. Gate: close-empty advances.
- **PL.6 — Resume + sweep-rejection banner on the list.** Re-entry lands on the 🔵;
  surface `sweepRejectionsProvider`. Gate: resume + a rejected sweep both behave.
- **PL.7 — No-paradas fallback (BR7/D2).** ✅ DONE. A route with GENUINELY 0 paradas
  auto-skips the list → classic capture (`pushReplacement`), but only once the opening
  sync has resolved while online (`refreshStops` is now awaited in `routeFrameProvider`,
  so an empty stops list is final — never an uncached/offline route mid-load). Offline
  or a failed sync keeps the manual one-tap fallback. No no-paradas route exists in
  Pitalito, so verified by widget tests (online-skip + offline-fallback), not live.
- **PL.8 — Tests + emulator E2E** on Pitalito (Ruta 10 multi-parada, Ruta 20 single).
```
