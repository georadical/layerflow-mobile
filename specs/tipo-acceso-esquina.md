# Spec 20 — Mandatory access type on built corners (+ "Sin entrada visible")

> Status: **Draft** — spec phase. Branch `feature/tipo-acceso-esquina` (cut from
> `fix/edit-placa-link`, since both touch editar unidad).
> Pipeline note: no new layout — an existing field gains one option, a dynamic label
> and an error state. Wireframe/Design collapse into the implementation tickets;
> the gates are tests + an emulator check (CLAUDE.md "Verificable").
> Relates to: **Spec 12 amendment** (corner-lot cruce), **Spec 18** ("Sin placa a la
> vista"), backend corner-lote-dedup v2 (GD28, relay 2026-10-21).

## User story
As a **field surveyor**, when I register a **built corner** — written as a cruce
(`CALLE 13 CON CARRERA 3`) in **Construido** mode, or linked **"sin placa a la
vista"** — I want the app to **require the access type**, including **"Sin entrada
visible"**, so the office has the datum it uses to decide corner duplicates and
fusions.

## Objective
Make `tipo_acceso` mandatory exactly where the office needs it (built corners) and
give the surveyor a proper option for "no visible entrance", instead of a free-text
note in Observación.

## Background (verified 2026-10-22)
- `tipo_acceso` is optional today. Capture options (`capture_screen.dart`):
  `puerta_calle` "Puerta a la calle", `area_comun` "Área común (hall/escalera/
  patio)", `otro` "Otro". The editor keeps its own list (`edit_unit_screen.dart`,
  `area_comun` labelled just "Área común").
- Backend (GD28): the **app** enforces it on built corners; the backend keeps
  accepting items without it (old app versions) and the office sees when it is
  missing. `sin_entrada_visible` is an accepted key. **No contract change** — the
  field `tipo_acceso` already travels on every push.
- Guide v1.3 tells the surveyor to write "sin entrada visible" in Observación.

## Scope
### Includes
- The rule "built corner ⇒ access type required" (BR1) as one pure function.
- The new option `sin_entrada_visible` "Sin entrada visible", in one shared list for
  capture and editor.
- Enforcement + dynamic label in **capture** and in **editar unidad**.
- Guide v1.3 update (not yet delivered).

### Does NOT include
- The **"¿Te falta CON?"** guard in Construido mode (separate ticket).
- Requiring `tipo_acceso` on **non-corner** predios.
- Retroactive marking/blocking of captures already saved or sent without it.
- Any **backend or contract** change.
- Changes to **where** a corner is registered (Spec 12 amendment rules stand).

## Actors and permissions
- **Surveyor** (field_token). No new permission.

## Preconditions
- A capture form (new capture or editar unidad) in **Construido** mode.

## Trigger
The surveyor taps **"Guardar y siguiente"** (capture) or **"Guardar"** (editor).

## Main flow (happy path)
1. In Construido mode the surveyor writes the cruce `CALLE 13 CON CARRERA 3`.
2. The access-type label changes to **"Tipo de acceso (obligatorio en esquina)"**.
3. They pick **"Sin entrada visible"** from the menu.
4. They take the photo and tap **"Guardar y siguiente"**: the capture saves with
   `tipo_acceso = sin_entrada_visible`.

## Alternative flows
- **A1 — Forgot the access type.** They tap "Guardar y siguiente" with the field
  empty: nothing is saved; the field turns red with *"Elige el tipo de acceso: es
  una esquina"* and the screen scrolls to it. Typed text and photo stay. They pick
  "Puerta a la calle" and save.
- **A2 — "Sin placa a la vista".** They link an R1 row and tap **Solo enlazar**: the
  label turns mandatory; same enforcement as A1.
- **A3 — Stops being a corner.** They remove `CON`, turn "Sin placa a la vista" off,
  or switch to **Sin construir**: the label returns to "(opcional)" and the chosen
  value, if any, is kept.
- **A4 — Editor.** In editar unidad, a built corner without access type (e.g. an old
  capture) cannot be saved until one is picked — same message, via **"Guardar"**.
- **A5 — Non-corner predio.** A normal placa (`CALLE 13 # 3-20`) saves with or
  without access type, as today; "Sin entrada visible" is offered there too.

## Business rules
- **BR1 — Built corner.** Construido mode (not `es_lote`) **and** either (a) the
  placa is a **cruce** (the app's cruce detector: `CON` + a via, as in
  `address.py`), or (b) **"Sin placa a la vista"** is on.
- **BR2 — Required.** On a built corner the access type is mandatory to save.
- **BR3 — Elsewhere optional.** Any other built predio: optional, as today.
- **BR4 — Lots exempt.** Sin construir never requires it, cruce or not.
- **BR5 — New option** `sin_entrada_visible` "Sin entrada visible", available for
  any predio.
- **BR6 — Order:** Puerta a la calle · Área común (hall/escalera/patio) · Sin
  entrada visible · Otro.
- **BR7 — Any option satisfies BR2**, "Otro" included.
- **BR8 — Enforcement:** no save; inline error *"Elige el tipo de acceso: es una
  esquina"*; scroll to the field; nothing typed/shot is lost.
- **BR9 — Advance notice:** label "Tipo de acceso (obligatorio en esquina)" while
  BR1 holds; "Tipo de acceso (opcional)" otherwise.
- **BR10 — Leaving the corner state** makes it optional again and keeps the value.
- **BR11 — Editor:** the same rule on save, old captures included.
- **BR12 — Not retroactive:** saved/sent captures are not flagged nor re-sent.
- **BR13 — One shared option list** for capture and editor (labels identical).
- **BR14 — Observación** stays free and optional; "sin entrada visible" no longer
  goes there.
- **BR15 — No contract change**; the key travels in `tipo_acceso`.

## Edge cases and error handling
- **Cruce typed in lowercase / with abbreviations** (`calle 13 con kr 3`): the
  detector normalizes → corner.
- **`CON` without a via after it** (`CALLE 13 CON`): not a cruce (detector rule) →
  optional. (The "¿Te falta CON?" ticket covers the opposite mistake.)
- **Camera-dead valve** (sin placa a la vista saves without photo): the access type
  is still required.
- **Duplicate R1 link notice / middle-anchor block:** unchanged; the access-type
  check runs with the other save checks, before writing.
- **Switching to Sin construir then back to Construido:** BR1 re-evaluates; the kept
  value still satisfies it.

## Acceptance criteria
- **AC1.** Construido + cruce, no access type → not saved, inline error, scrolled.
- **AC2.** Construido + "Sin placa a la vista", no access type → not saved.
- **AC3.** Sin construir + cruce, no access type → saves.
- **AC4.** Construido + normal placa, no access type → saves.
- **AC5.** "Sin entrada visible" is offered (capture and editor) and is stored as
  `sin_entrada_visible`.
- **AC6.** The label reads "(obligatorio en esquina)" exactly while BR1 holds.
- **AC7.** Editor: an old built corner without access type cannot be saved until one
  is picked.
- **AC8.** Capture and editor show the same four options, same labels, same order.

## BDD (Gherkin)
```gherkin
Feature: Mandatory access type on built corners

  Scenario: A built corner written as a cruce needs an access type
    Given the capture form in "Construido" mode
    And the placa field reads "CALLE 13 CON CARRERA 3"
    And no access type is selected
    When the surveyor taps "Guardar y siguiente"
    Then nothing is saved
    And the access type field shows "Elige el tipo de acceso: es una esquina"

  Scenario: "Sin entrada visible" satisfies the rule
    Given the capture form in "Construido" mode with the cruce "CALLE 13 CON CARRERA 3"
    When the surveyor picks "Sin entrada visible" and taps "Guardar y siguiente"
    Then the capture is saved with tipo_acceso "sin_entrada_visible"

  Scenario: A lot on a corner stays optional
    Given the capture form in "Sin construir" mode with "CALLE 13 CON CARRERA 3"
    When the surveyor taps "Guardar y siguiente" without an access type
    Then the capture is saved

  Scenario: The editor enforces it on an old "sin placa a la vista" capture
    Given a saved capture linked to R1 with no placa and no access type
    When the surveyor opens "editar unidad" and taps "Guardar"
    Then nothing is saved until an access type is picked
```

## Suggested tickets (each gated + committed + approved)
- **TA.1 — Spec** (this file). Gate: approved.
- **TA.2 — Rule + shared options.** Pure `isBuiltCorner(...)` (BR1) and the shared
  option list (BR5/BR6/BR13); unit tests. Gate: analyze + tests.
- **TA.3 — Capture.** Dynamic label, enforcement on "Guardar y siguiente" (error +
  scroll), new option; widget tests AC1–AC6.
- **TA.4 — Editor.** Same rule on "Guardar", shared list; widget tests AC5, AC7, AC8.
- **TA.5 — Emulator check** (Ruta 20, local only, cleanup): cruce Construido,
  sin placa a la vista, lot cruce, normal placa — together with the SE.9 editor check.
- **TA.6 — Guide v1.3.** "Sin entrada visible" → pick it in Tipo de acceso; mandatory
  on built corners.
