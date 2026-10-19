# Spec 18 — "Solo enlazar — no hay placa a la vista" (link to R1 without an observed placa)

> Status: **Draft** — spec phase. Branch `feature/solo-enlazar`.
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.
> Relates to: **Spec 7 / R1-assisted capture** (the link card, `soporte`
> classification), **Spec 13 / ancla-por-manzana** (anchor + middle-anchor block),
> **Spec 12 amendment / corner lot cruce** (corner predios without placa: if R1 lists
> the corner on this face → link without placa; otherwise the cruce).

## User story
As a **field surveyor**, when I find a **built predio with no visible placa** and R1
**does** list it on the face I am sweeping (typically the corner where the parada
starts), I want to **link it to that R1 row without its address being recorded as if
I had read it on the door**, so the parada anchors, the prediction works, and the
office verifies the link.

## Objective
Make "linked to R1, no placa observed" an **explicit, one-tap state** instead of a
manual workaround (today the surveyor must clear the text after linking, and can
forget — leaving the R1 address stored as an observed placa).

## Background (verified 2026-10-19)
- Tapping an R1 suggestion copies the R1 address into the placa field
  (`capture_screen.dart:303`); "Coincide" does the same (`_coincide`, line ~385).
- Clearing the text afterwards **keeps the link**: the capture saves `placa = null`
  + the link (`npn`, or `direccion_norm` for a multi-unit placa); the photo is
  classified `soporte = divergencia` (CL-R3 trigger 4) and is therefore always
  required.
- Backend (relay 2026-10-19): derives "sin placa a la vista" from `placa = null` +
  link and opens an **operator task** (approve the link or replace it with another R1
  row); `capturada` is computed from the link, so a replacement reverts/assigns it
  automatically. **Prod E2E on Ruta 20 passed** (push, photo, sweep, `capturada=true`).
- **No contract change.**

## Scope

### Includes
- A **"Solo enlazar — no hay placa a la vista"** button inside the **link card**
  ("Enlazada a…"), available whenever a capture is linked to R1 — both after picking
  an R1 suggestion and after **"Coincide"** on the prediction card.
- Turning the mode **on**: the placa field is **cleared and locked** (read-only),
  showing *"Sin placa a la vista"*.
- Turning it **off** (tap the button again, or remove the link with the X): the field
  is **unlocked and left empty**.
- The saved capture is `placa = null` + the R1 link; the photo is **mandatory**.
- Display: list / review rows read *"Sin placa a la vista · enlazada a <R1 address>"*.
- Correction in **editar unidad** before sending (switch between "sin placa a la
  vista" and an observed placa).

### Does NOT include
- The **operator verification screen** and its approve/replace logic — backend.
- The **"¿Te falta CON?" guard in Construido** mode, the **`tipo_acceso =
  sin_entrada_visible`** option and the **duplicate-link warning** — separate
  tickets/specs.
- **"Sin construir" (lots):** a lot is never linked to R1 (Spec 12 BR6), so the button
  never shows there.
- **Rural / manzana-less paradas:** no R1 suggestions → no link card → no button.
- Any **new request field** or automatic text in `observacion`.
- Changing the **middle-anchor block** — it applies exactly as today.

## Actors and permissions
- **Field surveyor (titular or pareja)** — same capture permissions; no new role.

## Preconditions
- An assisted parada (has a manzana; R1 directory available for it).
- Mode **Construido**.
- The capture is **linked** to an R1 row (suggestion picked or "Coincide").

## Trigger
The surveyor taps **"Solo enlazar — no hay placa a la vista"** in the link card.

## Main flow (happy path) — corner at the start of the parada
1. The surveyor opens the parada (no captures yet). The corner predio is built and has
   no visible placa.
2. They type the parada's street and the crossing number (e.g. `CALLE 20A # 3-`);
   the R1 suggestions appear; they tap the corner's row (`CALLE 20A # 3-03 · R1`).
3. The link card shows *"Enlazada a: CALLE 20A # 3-03"* and the button
   **"Solo enlazar — no hay placa a la vista"**.
4. They tap the button: the placa field empties and locks, reading
   *"Sin placa a la vista"*; the photo label reads *"(requerida)"*.
5. They tap **Guardar y siguiente** → the camera opens → they photograph the facade.
6. The capture saves (`placa = null`, linked, `soporte = divergencia`); the parada
   anchors and the prediction card shows the next expected placa.

## Alternative flows (sad paths)
- **A1 — Via "Coincide" mid-face.** The prediction card shows *"Siguiente esperada:
  CALLE 20A # 3-11"*; the door has no placa but it is that predio. The surveyor taps
  **Coincide** (the link card appears), then **Solo enlazar** → saves with the photo.
- **A2 — Changed their mind (button again).** With the mode on, they tap the button
  again: the field unlocks, **empty**; the link remains; they type the placa they now
  see and save normally.
- **A3 — Wrong row (X).** With the mode on, they tap the **X**: the link is removed,
  the mode turns off, the field unlocks (empty), and they pick another suggestion.
- **A4 — Middle row.** The linked row is in the middle of the face and the parada has
  no anchor yet: the middle-anchor block fires as today ("Esta placa no inicia la
  parada" → **Elegir otra**). The button does not bypass it.
- **A5 — Camera dead.** The hardware valve applies: the capture saves without the
  photo (the absent photo is itself the QA signal), as for any required shot.
- **A6 — Corrected later.** Before sending, the surveyor opens **editar unidad** on the
  capture and switches "Sin placa a la vista" off to type an observed placa (or on, to
  clear it); the push re-carries the corrected `placa` (full-replacement).

## Business rules
- **BR1 — The state.** "Sin placa a la vista" ≡ `placa = null` **and** an R1 link.
  No other field signals it; the backend derives it.
- **BR2 — Where.** The button lives only in the link card; the link card appears for
  both link paths (suggestion and Coincide). No link → no button.
- **BR3 — Any position.** Valid for any predio of the parada, not only the anchor.
- **BR4 — Construido only.** Hidden in "Sin construir" (no R1 link for lots).
- **BR5 — Lock.** On: field cleared and read-only, reading *"Sin placa a la vista"*.
  Off (button again or X): field editable and **empty** (the R1 address is never
  restored into it).
- **BR6 — Photo.** Mandatory whenever the mode is on, even on routes without
  `foto_obligatoria`; the camera-dead valve still applies.
- **BR7 — No confirmation dialog.** The button acts on the first tap (it is reversible).
- **BR8 — Observación optional.** Nothing is written into it automatically.
- **BR9 — Middle-anchor block unchanged.**
- **BR10 — Display.** List/review rows show *"Sin placa a la vista · enlazada a <R1
  address>"* (address looked up from the link, as `editar unidad` already does).
- **BR11 — Editable before send.** `editar unidad` offers the same on/off switch.
- **BR12 — No contract change.**

## Edge cases and error handling
- **Multi-unit R1 placa** (link by `direccion_norm`, `npn = null`): same behavior;
  the link survives with the placa empty.
- **Duplicate R1 row in the route:** the existing "ya capturada en la posición N"
  notice still shows; the mode does not change it.
- **Switching to "Sin construir" with the mode on:** the link is dropped (lots are not
  linked), the mode turns off, the field unlocks empty.
- **App restart mid-form:** the form state is not persisted today; nothing new here.
- **OCR soft-check:** with no typed placa there is nothing to compare; the shot is
  kept as evidence only.

## Acceptance criteria
- **AC1.** With a capture linked to R1 in Construido, the link card shows the button;
  without a link, in Sin construir, or on a rural parada it does not.
- **AC2.** Tapping it clears and locks the field ("Sin placa a la vista"); tapping it
  again or tapping X unlocks it empty.
- **AC3.** The saved capture has `placa = null` and keeps `npn`/`direccion_norm`; the
  photo was required (`soporte = divergencia`).
- **AC4.** Works after "Coincide" as well as after picking a suggestion.
- **AC5.** A middle row is still blocked as an anchor.
- **AC6.** List and review rows read "Sin placa a la vista · enlazada a …".
- **AC7.** `editar unidad` can switch the state before sending.
- **AC8.** `flutter analyze` clean, `flutter test` green; manual run on the emulator
  (Ruta 20).

## BDD (Gherkin)
```gherkin
Feature: Link a predio to R1 without an observed placa

  Background:
    Given an assisted parada with R1 rows for its manzana
    And the form is in "Construido"

  Scenario: Corner at the parada start, linked without placa
    Given the parada has no captures
    When the surveyor taps the R1 suggestion "CALLE 20A # 3-03"
    And taps "Solo enlazar — no hay placa a la vista"
    Then the placa field is empty and locked, reading "Sin placa a la vista"
    When the surveyor taps "Guardar y siguiente" and takes the photo
    Then the capture is saved with no placa and linked to "CALLE 20A # 3-03"
    And the prediction card shows the next expected placa

  Scenario: Via Coincide in the middle of the face
    Given the prediction card shows "CALLE 20A # 3-11"
    When the surveyor taps "Coincide"
    And taps "Solo enlazar — no hay placa a la vista"
    Then the placa field is empty and locked

  Scenario: Undo by tapping the button again
    Given the mode "Sin placa a la vista" is on
    When the surveyor taps the button again
    Then the placa field is editable and empty
    And the link remains

  Scenario: The middle-anchor block still applies
    Given the parada has no captures
    When the surveyor links a middle R1 row and taps "Solo enlazar"
    And taps "Guardar y siguiente"
    Then the app shows "Esta placa no inicia la parada"

  Scenario: Not offered for lots
    When the surveyor selects "Sin construir"
    Then no "Solo enlazar" button is shown
```

## Suggested tickets (each gated + committed + approved)
- **SE.1 — Spec** (this file). Gate: approved.
- **SE.2 — Wireframe.** The link card with the button (off/on), the locked field
  reading "Sin placa a la vista", and a list row "Sin placa a la vista · enlazada a …"
  — dummy data, gallery entry, render test. Gate: renders.
- **SE.3 — Capture form state.** The mode on/off, clear + lock, unlock on button/X,
  drop on "Sin construir"; photo mandatory (already via `divergencia` — verify).
  Unit/widget tests. Gate: analyze + tests.
- **SE.4 — Coincide path.** Ensure the link card (and button) appears after
  "Coincide"; test.
- **SE.5 — Display.** List/review rows for `placa = null` + link.
- **SE.6 — editar unidad.** The same switch in the editor.
- **SE.7 — Design pass + emulator E2E** (Ruta 20, local, then cleanup).
- **SE.8 — Guide.** Replace the manual "borra el texto" step with "toca *Solo
  enlazar*".
