# Specs — index and backlog

Every feature is born as a spec here before any code, and runs through
`Spec → Wireframe → Design → Implementation` (see CLAUDE.md). Each phase ends
with a verifiable gate, a commit and explicit approval.

| # | Spec | File | Status |
|---|------|------|--------|
| 1 | Open and resume route | [open-and-resume-route.md](open-and-resume-route.md) | Done — verified against the backend |
| 1.1 | One editable list per route | [one-editable-route-list.md](one-editable-route-list.md) | Done — verified against the backend |
| 2 | Strict-order capture (local) | [strict-order-capture.md](strict-order-capture.md) | Done — T2.1 verified on device |
| 2.1 | Move a unit's localización | [relocate-unit.md](relocate-unit.md) | Done — verified against the backend |
| 3 | Batch push (`POST /field/capture/placas`) | [push-captured-batch.md](push-captured-batch.md) | Done — verified against the backend |
| 4 | Offline-first queue and retry | [offline-queue-and-retry.md](offline-queue-and-retry.md) | Done — T4.1 verified on device |
| 5 | Field worker login | [field-login.md](field-login.md) (shared) | Done — T5.1–T5.5 verified live against the backend |
| 6 | ESP switching (multi-ESP, app side) | [esp-switching.md](esp-switching.md) | Done — switch verified live both ways |
| 7 | R1-assisted capture | [r1-assisted-capture.md](r1-assisted-capture.md) (shared) | Done — full version E2E-verified both sides (2026-09-15) |
| 8 | Extended survey PH/PV | [extended-survey-phpv.md](extended-survey-phpv.md) (shared) | Done @ d2bb861 — T8.1–T8.6 complete; E2E 9/9 aplicada both sides (Isnos/Ruta 10, 2026-09-17) |
| 9 | Route-state locks (capture + survey gating) | [route-state-locks.md](route-state-locks.md) | Done — L.1 foundation, L.2 survey gate, L.3 placa gate; survey gate verified live (unlock on open route) |
| — | Road to production (backlog) | [road-to-production.md](road-to-production.md) | Backlog — deployment infra, rich census, pilot (run first); not scheduled |
| — | BlockFace & Paradas (reference) | [paradas-blockface.md](paradas-blockface.md) | Reference — backend model pinned; app consumes read-only (TP.4/TP.5) later, changes nothing today |

## Spec 7 — R1-assisted capture (shared spec, frozen 2026-09-12)

Frozen at backend `8d06a61` with the app's four contract observations
(frame carries `npn` — the ins_after lesson; normalization pinned as an
exact algorithm; evidence limits pinned; directory `version` tag) and
CL-R1…R5 as proposed. The worker never sees an NPN: they type the placa
they see (stored raw, always) and optionally tap a matching R1 **address**;
the NPN rides hidden behind it. "No está en la lista" is a first-class
action — divergence is the census's product, not an error.

**App tickets (against the shared contract):**
- **T7.1 — R1 directory local**: drift table, fetch with `version` tag,
  and the client normalizer mirroring the pinned algorithm exactly (tests
  against the spec's own examples).
- **T7.2 — Typeahead wireframe**: free placa field + suggestion panel with
  "No está en la lista" as fixed first row (CL-R1), duplicate-NPN warning
  (CL-R3 trigger 5). Wireframe → approval → design → wiring.
- **T7.3 — `npn` end to end**: schema v5 column, request item, frame
  merge, ride-on-every-push (the ins_after pattern), per-item error
  mapping.
- **T7.4 — Photo evidence**: camera per capture, compression (JPEG ~70,
  1600px), evidence queue bound to the person, CL-R5 upload inside the
  Enviar gesture (divergence any network, routine WiFi-only).
- **T7.5 — OCR soft-check**: ML Kit on-device + edit distance over
  normalized strings; silent unless mismatch (CL-R2).

Blocked on backend TI.1–TI.3 for wiring; T7.1's normalizer, T7.2 and the
schema work can start now.

## Spec 8 — Extended survey PH/PV (shared spec, frozen 2026-09-13 @ a968d72)

The census pass: the surveyor declares building structure WITH BUTTONS
("agregar piso" / "agregar unidad"), the app generates PH/PV (never shown
as editable digits — "Piso 2 · Unidad 3"), and office promotion expands
the 00/00 anchor into real units. All four app blockers landed pinned:
the /sync/push contract with field-capture-api rigor (point 0), frame
invariance post-expansion — siblings have client_id NULL and never enter
the placa frame (point 1, verified in code), the PH/PV generation
algorithm including pre-send deletion with compact renumber (point 2),
and instancia semantics (point 4). CL-E1..E7 pinned as proposed.

**App tickets (against the shared contract):**
- **T8.1 — Sync client** ✅ DONE (36a2721, wired at 3f397bf): /sync/push
  envelope DTOs + `orderOperations` (parents before children), two-layer
  idempotency, `operaciones`/`resumen` result mapping (Q3), and the
  `SurveyStructure → visit → observation_set → field_response` builder with
  the Q2 `data` shapes (all `create`; totalizador photo out of band via
  evidence; deterministic v5 field ids).
- **T8.2 — Survey rail wireframe** ✅ DONE (58b2f2c): per-unit survey-state
  chips in the resume list (one list, not a parallel survey list), pre-loaded
  full-screen form (the editor refactor is the chassis), structure buttons,
  CL-E3 questions verbatim, totalizador gesture. Wireframe approved + on-theme.
- **T8.3 — Local pyramid + pinned PH/PV generator** ✅ DONE (Q1=(B),
  2a68eb4): positional model in `lib/core/survey/survey_pyramid.dart` —
  codes derived from position so pre-send deletion compacts for free, the
  app always emits a `unidad` (a lone unit is still 01/01; the backend
  decides 00/00-vs-expand), CL-E7 device-side convention validator. Unit
  tests against the spec's pseudocode + acceptance codes.
- **T8.4 — Totalizador photo** ✅ DONE (b4a4cb0): evidence flow with
  proposito='totalizador' (backend TJ.3), soporte=divergencia fixed,
  declared only WITH its photo; coexists with the placa photo (Evidence
  keyed by (client_id, proposito), schema v11).
- **T8.5 — The Enviar chain grows** ✅ DONE: resumable survey state in drift
  (T8.5a, cd07d3c, schema v10), the real survey screen + resume-list entry
  (T8.5b, 5d3e4f7), and the survey push chained into Enviar (T8.5c, 3f397bf,
  placas → evidence → /sync/push, CL-E5). The CL-E8 lock gate is Spec 9.
- **T8.6 — Coordinated E2E** ✅ DONE: Isnos / Ruta 10 / CALLE 7 3-21,
  9/9 aplicada both sides — lock passed, assignment_id derived by the
  backend, unidad 01/01 + totalizador photo landed; test rows cleaned up.

Spec 7 closed 2026-09-15: typeahead v1.2 (placa-only mode scoped by
manzana, part-match), graduated photos v1.1 (deliberate shot on
divergence, 1/10 lottery on rutina, pinch-to-zoom, hardware valve),
`enlazado` markers + discovery mode (CL-R6) and tri-state `sin_r1`
findings (CL-R7). Four-case E2E on a sacrifice route, confirmed on both
sides. Open item for a future E2E: the matcher's skip of
`field_sin_match` is covered by the backend's test but was never seen
live (the retraction case had already cleared the finding).

## Road to production (backlog — not scheduled)

The app is functionally complete (Specs 1–9, E2E-verified), but a real
rollout still needs deployment infra, richer census depth, and a field
pilot. That backlog now lives in its own ordered doc:
[road-to-production.md](road-to-production.md) — Track A (deployment infra),
Track B (rich census: hogar/connection/meter, which the app does not
capture yet), Track C (backend promotion/reconciliation), Track D (pilot,
to run FIRST). The old "Field deployment" list is folded into Track A there.

## Spec 3 — notes carried in from Spec 1.1

Both are now folded into [push-captured-batch.md](push-captured-batch.md),
kept here for the trail of where they came from:

- **The sync control sits in the wrong screen.** Today it is an icon in the
  capture form's app bar. The resume view is where a worker sees which rows
  read "sin enviar", yet it offers no way to send them: state is shown in one
  place and acted on in another. That is the same split Spec 1.1 removed
  between the two lists. The queue also belongs to the *route*, not to the
  form that captures a single unit, so the control is hanging off the wrong
  object. Move the pending indicator and the send action to the resume view.
- **Auto-sync is invisible.** Saving a capture pushes the queue silently, so
  an edit made minutes earlier can reach the backend without the worker doing
  anything they would recognise as sending. With intermittent signal in the
  field, that is an unseen effect on real data. Decide whether it stays
  automatic and becomes visible, or becomes explicit.

## Spec 5 — Field worker login (defined by the shared spec)

Resolved 2026-09-11. The open questions this section used to carry (login
endpoint, session lifetime vs offline, credential storage) were answered by
the backend and pinned in **[field-login.md](field-login.md)** — a shared
spec, single document for both repos; the mirrored copy here is read-only.

The decisions, in one breath: credentials are **per person** (`users`),
capture attribution stays **per person-ESP** (`field_workers`, bridged by
`user_id`); `POST /field/login` returns **one fresh 30-day token per active
ESP, always** (BR-FRESH); `POST /field/token/refresh` renews silently with a
**7-day grace window that exists only there**; revocation becomes effective
per request. Recovery hierarchy: signal → refresh → login. App-side rules
CL1–CL5 (paste-as-fallback, auto refresh on open, password never stored,
logout keeps the queue bound to the person, active-ESP choice at login) are
pinned in the spec itself.

**App tickets (against the shared contract):**
- **T5.1 — Token store per ESP + queue identity**: encrypted `ESP → token`
  map, and the local queue bound to the person (normalized login email — the
  response carries no person id; noted to the backend).
- **T5.2 — Login screen**: email + password, active-ESP choice when several
  (CL5), error paths A1/A2.
- **T5.3 — Silent refresh on app open** (CL2) + the recovery hierarchy,
  falling back to login beyond grace (A3).
- **T5.4 — Logout** (CL4): wipe tokens, warn "N sin enviar", park the queue
  by person; a different person's login neither merges nor pushes it.
- **T5.5 — Ajustes**: token paste demoted to visibly-exceptional fallback
  (CL1).

Blocked on: backend TG.1–TG.4 (endpoints do not exist yet).

## Spec 6 — Field worker across several ESPs (defined by the shared spec)

Resolved 2026-09-11 by the same identity decision: the same person in N ESPs
is one `users` row + N linked `field_workers`. **Path A confirmed** — one
token per ESP, never a multi-ESP token, switching is client-local. The login
response already lists every active ESP with its token, so no extra endpoint
is needed.

What remains is app work, deliberately out of Spec 5 (CL5): the ESP
**switcher**, and — the real work — **partitioning local state by tenant**
(active route, assigned-routes cache; the drift DB keys by route UUID, which
is already tenant-safe). To be spec'd after Spec 5 lands.

**Web frontend:** not assessed. It lives in another repo and was not
reviewed; any estimate here would be invented.
