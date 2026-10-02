# Spec 11 — Per-parada sequence ("Parada N · predio M")

> Status: **Draft** — spec phase. Branch `feature/secuencia-parada`.
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.

Backend mirror / contract source: the backend assigns and returns a new field
`secuencia_parada`. The app only **consumes and displays** it. See the relay
captured in this spec's Business rules; the authoritative contract lives on the
backend side.

## User story
As a **field worker** walking a route parada by parada, I want to see each
predio's position **within its parada** ("predio 1, 2, 3…", restarting at 1 on
every parada) instead of the route-global `posicion`, so I reason as "predio N of
this parada" rather than about an abstract route-wide counter. The **definitive**
number is assigned and returned by the **backend after sync**; until then I see a
**clearly-marked provisional** local count that is replaced by the server value
once I sync.

## Objective
Replace the surveyor-facing route-global `posicion` with the per-parada sequence
`secuencia_parada`, shown as **"predio M"** (and **"Parada N · predio M"** where a
parada anchor is needed). Consume the field from the backend post-sync; show a
marked provisional before sync; never send it.

## Scope

### Includes
- Consume `secuencia_parada` from the **capture response** and the **resume
  frame**, and persist it locally.
- Display the per-parada number as **"predio M"**, context-aware (see Business
  rules): `Parada N · predio M` in the resume list, `predio M` in the capture
  screen.
- A **provisional** local count before sync, visually marked, replaced silently
  by the server value after sync.
- **Stop showing `posicion`** (the route-global number) to the surveyor
  everywhere it appears today.

### Does NOT include
- The **backend side** (assigning `secuencia_parada`, the `MAX+1` logic, the
  freeze and gap guarantees). The app trusts whatever the backend returns.
- Any **change to the push payload**: `secuencia_parada` is never sent. No change
  to `posicion`, `loc`, `stop_id` / `block_face_id`, the sweep (`barrido`) gate,
  or photos.
- **Hiding `loc`** — `loc` stays visible; it is business logic from the
  normativa/methodology, not a surveyor convenience to be removed.
- The **"total N"** route count stays (it is a count, not a position id).
- Historical **exports**, SUI or LADM_COL reporting: this is surveyor-facing
  display + local storage only.
- Grouping/collapsing the resume list by parada (possible later; out of scope
  here — rows stay flat and carry their own `Parada N ·` anchor).
- A backend-composed `display_parada` in the field endpoints, or the
  `abre_parada` / `cierra_parada` markers (office-only; the app composes its own
  label from the raw value — BR16).
- Omitting "predio 1" on a single-predio parada (backend's optional suggestion) —
  deferred; see Open items.

## Actors and permissions
- **Field worker (titular or pareja)** — the only actor. Read-only consumer of
  `secuencia_parada`; sees "predio M" / "Parada N · predio M".
- No new permission. Same `field_token` scope as all capture.

## Preconditions
- The route is open and resumable (Spec 1) on a `verificada` route.
- Parada-scoped capture (Spec 10) is in force: captures bind to a `stop_id`.
- The local DB can store the new field (migration applied).

## Trigger
- The surveyor opens a route's **resume list** or the **capture screen**, or
  **captures** a placa, or **syncs** (Enviar). Any of these renders or updates a
  per-parada number.

## Main flow (happy path)
1. The surveyor is on parada N (an urban face) and captures the first predio.
2. The app saves the capture bound to the parada's `stop_id`, with
   `secuencia_parada = NULL` (not yet assigned by the server).
3. The capture screen shows the provisional number for that predio: **`predio ~1`**
   in medium gray with a pending symbol.
4. The surveyor captures the 2nd and 3rd predios → provisional **`predio ~2`**,
   **`predio ~3`** (the local count, +1 each, restarting at 1 for this parada).
5. The surveyor taps **Enviar** (sync). The push carries the placas as today
   (no `secuencia_parada` sent).
6. The backend assigns `secuencia_parada` (MAX of the parada + 1 per item) and
   returns it in the response: `{ client_id, ok, id, loc, secuencia_parada, status }`.
7. The app stores each returned `secuencia_parada` and re-renders: the numbers
   drop the tilde and the pending symbol and show the **definitive** value in
   **bold green** — e.g. **`predio 1`**, **`predio 2`**, **`predio 3`**.
8. On the next parada the count restarts: the first predio there is **`predio ~1`**
   again (provisional) until its own sync.

## Alternative flows (sad paths)
- **A1 — Resume a route with already-synced predios (via the resume list).**
  The surveyor opens the route; the app loads the **resume frame**, which carries
  `secuencia_parada` alongside `posicion`/`loc`. Each row shows
  **`Parada N · predio M`** in bold green (definitive). No `posicion` is shown.
- **A2 — Offline capture, sync later.** The surveyor captures several predios
  offline; all show provisional **`predio ~M`** (gray, pending symbol). When
  connectivity returns and they press Enviar, the response's `secuencia_parada`
  replaces each provisional **silently** (no banner), turning them bold green.
- **A3 — Gap from a deleted predio.** A predio was deleted server-side; the
  backend's frozen numbering leaves a gap. The frame returns, e.g., 1, 2, 4 for a
  parada. The app shows **`predio 4`** verbatim — it never renumbers to close the
  gap (the recenso needs the gap).
- **A4 — Legacy / no `stop_id` capture.** A capture with `secuencia_parada = NULL`
  and **no parada to count against** (legacy data) shows a neutral fallback
  **`predio —`** (no provisional, no tilde, no color).
- **A5 — Provisional diverges from the definitive.** The local provisional said
  `~3` but the server returns `4` (e.g., a pre-existing synced predio the app had
  not counted). On sync the app shows **`predio 4`** (bold green) — the server
  value always wins, silently.

## Business rules
- **BR1 — Source of truth.** `secuencia_parada` is **backend-assigned** (MAX of
  the parada + 1) and returned in the capture response and the resume frame. The
  **app never sends it**.
- **BR2 — Per-parada, restarts at 1.** It is the predio's position **within its
  parada** (Mz 50 cara sur → 1, 2, 3; next parada → 1 again). Independent of
  `posicion`/`loc`, which do not change.
- **BR3 — Frozen.** Once assigned it does not change; a re-carry preserves it. A
  re-push of the same unit returns `status:"updated"` with the SAME frozen value
  (never recalculated); an `ok:false` item carries no `secuencia_parada` at all.
- **BR4 — Gaps are real.** A deleted predio's number is **not reused**; the app
  shows gaps verbatim and never renumbers (the recenso depends on it).
- **BR5 — NULL for legacy / no `stop_id`.** Such captures have no sequence; the
  app shows the neutral fallback `predio —`.
- **BR6 — Noun = "predio".** The counted element is a **predio** (LADM_COL
  cadastral term, consistent with the project glossary: "placa = número del
  predio").
- **BR7 — Context-aware label.**
  - **Resume list:** `Parada N · predio M` — rows span paradas, so each needs its
    own parada anchor. (`Parada N` = the parada's `faceSequence`.)
  - **Capture screen:** `predio M` only — the parada is already shown as
    "cara N" in the face card / strip; do not repeat it.
- **BR8 — Provisional vs definitive encoding.**
  - **Provisional (pre-sync):** tilde + **medium gray** + a **pending symbol** —
    e.g. `⏳ predio ~3`. It is the local count only; authoritative only after sync.
  - **Definitive (post-sync):** no tilde, **bold**, **green** — e.g. `predio 3`.
    (Exact gray/green tokens and the pending glyph are fixed in the Design phase,
    with a contrast check on the green.)
- **BR9 — Provisional computation.** Provisional M = (count of local captures
  already on this parada) **+ 1**, in capture order, starting at 1 for the
  parada's first predio. It **ignores gaps** (it cannot know them pre-sync).
- **BR10 — Provisional is derived, not stored.** The provisional is computed
  on the fly for display; only the **definitive** server value is persisted.
- **BR11 — Silent replacement.** On sync the provisional is replaced by the
  server's `secuencia_parada` **without any warning or reconciliation banner**,
  even when they differ.
- **BR12 — `posicion` removed from the surveyor's view** everywhere it appears
  today (resume list, capture header, the "Siguiente posición" chip, "La primera
  será la posición 1", the duplicate-address message, the edit-unit screen, the
  survey screen). It may remain in internal data/logs.
- **BR13 — `loc` and `total` stay.** `loc` remains visible (normativa/methodology);
  the route "total N" count remains (a count, not a position id).
- **BR14 — Rural paradas count too.** A rural parada (no terna, free-text
  topónimo) with a `stop_id` still gets `predio M`.
- **BR15 — Push unchanged.** Nothing about the push, `posicion`, `loc`,
  `stop_id`/`block_face_id`, the sweep gate, or photos changes.
- **BR16 — The app composes the label from the raw value.** The field endpoints
  return the raw integer `secuencia_parada` only; the app builds the display text
  ("predio M" / "Parada N · predio M"). The composed `display_parada` and the
  `abre_parada` / `cierra_parada` markers are OFFICE-only (`/consult/census-codes`)
  and are NOT requested for the field (confirmed with the backend 2026-09-30):
  a single fixed string cannot carry our context-aware label, the provisional
  state, or the "predio" wording.

## Edge cases and error handling
- **Partial batch.** A push returns `ok` for some items and `errores` for others;
  only the `ok` items get a `secuencia_parada` and turn definitive — the rest stay
  provisional (gray/pending) until a successful sync.
- **Re-sync of an already-definitive predio.** The frame returns the same
  (frozen) value; the app re-applies it — no visible change (idempotent).
- **Mixed parada in the resume list.** Rows from several paradas interleave;
  each carries its own `Parada N ·` anchor so the restart-at-1 is never
  ambiguous.
- **Response without the field (old backend).** If a response/frame omits
  `secuencia_parada`, the app keeps the capture at NULL and shows the provisional
  (if countable) or `predio —` — never crashes, never invents a number.
- **"Siguiente" chip removed.** The former "Siguiente posición: N" chip is
  **removed, not renamed**: the expected-address prediction card (Spec 10,
  "Siguiente esperada" + Coincide) already guides what comes next, and a
  provisional counter would add little. The **queue-status chip** ("Todo
  enviado" / "N sin enviar") **stays** as a non-actionable status pill — it never
  showed `posicion`, and the single send control remains in the resume view
  (Spec 3, BR2).

## Acceptance criteria
- **AC1.** No surveyor-facing screen shows the route-global `posicion` anymore.
- **AC2.** The resume list shows `Parada N · predio M` per row; the capture screen
  shows `predio M`.
- **AC3.** Before sync, a capture shows a provisional number with all three cues
  (tilde, medium gray, pending symbol).
- **AC4.** After a successful sync that returns `secuencia_parada`, the same
  capture shows the definitive value (no tilde, bold, green) with no banner.
- **AC5.** The per-parada number restarts at 1 on each parada (verified across ≥ 2
  paradas).
- **AC6.** Server gaps are shown verbatim; the app never renumbers.
- **AC7.** A legacy / no-`stop_id` capture shows `predio —`.
- **AC8.** `loc` and the route "total N" are still visible; the push payload is
  unchanged (no `secuencia_parada` sent).
- **AC9.** `flutter analyze` clean, `flutter test` green, including new DTO / DB /
  display tests.

## BDD (Gherkin)

```gherkin
Feature: Per-parada sequence ("predio M") replaces the route-global posicion

  Background:
    Given a field worker on a verificada route with parada-scoped capture
    And the route has at least two paradas

  Scenario: Provisional number before sync (capture screen)
    Given the worker is on parada 1 with no captures yet
    When the worker saves the first predio
    Then the capture screen shows "predio ~1" in medium gray with a pending symbol
    And the route-global posicion is not shown

  Scenario: Definitive number after sync, via the capture response
    Given the worker has three provisional predios on parada 1 ("~1".."~3")
    When the worker taps Enviar and the backend returns secuencia_parada 1,2,3
    Then the three predios show "predio 1", "predio 2", "predio 3" in bold green
    And no reconciliation banner is shown

  Scenario: The count restarts on the next parada
    Given parada 1 has synced predios up to "predio 3"
    When the worker captures the first predio on parada 2
    Then it shows "predio ~1"

  Scenario: Resume list shows the parada anchor
    Given a route whose predios are already synced
    When the worker opens the resume list
    Then each row shows "Parada N · predio M" in bold green
    And no row shows a posicion

  Scenario: Gaps are shown verbatim
    Given parada 1 lost its predio number 3 to a deletion
    When the frame returns secuencia_parada 1, 2, 4 for parada 1
    Then the resume list shows "predio 1", "predio 2", "predio 4"
    And no number is reused or shifted

  Scenario: Legacy capture without a stop_id
    Given a capture with secuencia_parada null and no parada to count against
    When it is rendered
    Then it shows "predio —" with no tilde and no color

  Scenario: Provisional diverges from the server value
    Given a local provisional of "~3" on a parada
    When the backend returns secuencia_parada 4 for that predio
    Then it shows "predio 4" in bold green
    And the change is silent

  Scenario: loc and total stay visible
    Given any capture on the route
    When it is rendered
    Then loc is still shown
    And the route "total N" count is still shown
    And the push payload carries no secuencia_parada
```

## Suggested tickets (small, atomic)
- **SP.1 — Contract plumbing (DTOs).** Parse `secuencia_parada` in the capture
  response item and in the resume-frame item. Tests against sample payloads.
  Gate: `flutter test` green.
- **SP.2 — Local storage.** Nullable `secuenciaParada` column on `captures` +
  migration (**v20**); populate from the response (SP.1) and the frame merge.
  Gate: migration test + round-trip test.
- **SP.3 — Wireframe: per-parada number.** Flat widgets, dummy data, both states
  (provisional vs definitive) and both contexts (resume `Parada N · predio M`,
  capture `predio M`), plus `predio —` fallback. Gate: the screen renders.
- **SP.4 — Remove `posicion` from the surveyor's view.** Replace every
  surveyor-facing `posicion` with the per-parada number (resume list, capture
  header, "primera será la posición 1", duplicate message, edit-unit, survey);
  **remove** the "Siguiente posición" chip entirely (keep the queue-status chip).
  Keep `loc` and "total N". Gate: no `posicion` on screen; tests updated.
- **SP.5 — Provisional count (derived).** Compute the on-the-fly provisional per
  parada (BR9/BR10). Gate: unit tests for restart-at-1 and +1 ordering.
- **SP.6 — Design pass.** Apply the theme tokens: medium gray + tilde + pending
  glyph (provisional), bold green (definitive), with a green-contrast check.
  Gate: compiles and looks right; commit.
- **SP.7 — Manual E2E.** Provisional visible on fresh captures; after sync the
  values turn definitive from the server; restart-at-1 across two paradas.
  (Definitive path is verified once the backend ships its side and we sync.)

## Open items
- **Theme tokens — RESOLVED (Design):** provisional = `colorScheme.onSurfaceVariant`
  (medium gray) + `~` + `Icons.cloud_upload` (matches the app's pending-sync icon);
  definitive = `kPredioDefinitivo` (`#2E7D32`, Green 800, ~4.9:1 on the light
  surface) + bold. Only the number carries the color; "Parada N ·" stays neutral.
- **Contract shape — RESOLVED (backend 2026-09-30):** raw `secuencia_parada`
  (int ≥ 1 or null) in the capture response (`ok:true` items) and the resume
  frame; `status:"updated"` carries the frozen value; the app composes the label
  (BR16).
- **Deferred (future):** omit "predio 1" on a single-predio parada — only safe
  post-sweep in the resume list; minor noise, not worth the edge cases now.
