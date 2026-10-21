# Spec 19 — Show the stored address without composing it twice

> Status: **Draft** — spec phase. Branch `feature/address-display`.
> Pipeline note: this is a **display-rule fix with no new layout** — the rows keep
> their structure, only the text they show changes. There is nothing to wireframe or
> style, so the Wireframe and Design phases do not apply; the gates are unit tests +
> an emulator check (CLAUDE.md "Verificable").
> Relates to: **Spec 10 / guided parada** (distance-only input + composed list),
> **Spec 13 AM.8** (distance composed from the anchor's R1 face), **Spec 12
> amendment** (corner-lot cruce), **Spec 18** ("Sin placa a la vista").

## User story
As a **field surveyor** reviewing what I captured, I want to **see each predio with
its full, correct address — never duplicated and never a bare number** — so I can
recognize it in the list and catch mistakes before sending.

## Objective
One display rule, shared by every screen that shows a captured placa, that composes
the address **only when the stored text is a bare distance**.

## Background (verified 2026-10-21, prod E2E on Ruta 20)
- In a guided parada the surveyor may type just the **distance** (`28`); the list
  then composes «vía principal # vía generadora-» + distance (Spec 10, commit
  `8a7c238`, `composeParadaAddress` in `lib/core/parada/face_prediction.dart`).
- The resume list ("Revisar / editar placas", `resume_route_screen.dart`) composes
  **whenever the parada carries its terna**, without checking what is stored. Two
  later features store something else on those same paradas, and the list was never
  updated:
  - after **"Coincide" / an R1 link** the full address is stored → shows
    `CALLE 20A # 3-CALLE 20A # 3-11`;
  - a **corner-lot cruce** is stored as typed → shows
    `CALLE 20A # 3-CALLE 20A CON CARRERA 4`.
- The opposite gap: Pitalito paradas mostly carry **no terna** (Ruta 10: only parada
  6 has one — the face comes from the anchor's R1 row, AM.8). There a stored distance
  shows **bare** (`28`) in the list, in "Última capturada" and in the parada list.
- **Data is correct.** The app sends the placa exactly as stored and the backend
  stores and returns it raw (BR8); it never composes on read (relay 2026-10-21). Only
  the display is wrong. No contract change.

## Scope
### Includes
- A single pure display function (stored placa + context → text shown).
- Applying it in: **"Revisar / editar placas"**, the **"Última capturada"** card and
  the **rows of a swept parada** in the parada list (read-only).
- Tests for every case below + an emulator check.

### Does NOT include
- **Normalizing at save time** (always storing the full address, or always the
  distance). If ever wanted, it is decided with the backend.
- **editar unidad**: its placa field keeps showing the stored text as is (editing
  must not alter what is stored).
- The **live preview** while capturing (`CALLE 13 # 3-__`) — unchanged.
- The "Sin placa a la vista · enlazada a …" rows (Spec 18), "Lote" and "Sin
  dirección aún" — unchanged.
- Any change to what is sent to the server, or to the backend.
- The backend's «{vía} Lote» composition for a plate-less lot (the app keeps "Lote").

## Actors and permissions
- **Surveyor** (field_token): reads the lists. No new permission.

## Preconditions
- The capture exists locally (pending or synced; frame-merged rows included).

## Trigger
Any of the three screens renders a capture row.

## Main flow (happy path)
1. The surveyor captured, on a guided parada, a door by typing the distance `28`.
2. They open **"Revisar / editar placas"** (AppBar action on the parada list).
3. The row reads `CALLE 20A # 3-28` — composed from the parada's terna.
4. Another row, linked via **"Coincide"**, stored `CALLE 20A # 3-11`; it reads
   `CALLE 20A # 3-11` — shown as is, once.

## Alternative flows
- **A1 — Cruce.** A corner lot stored `CALLE 20A CON CARRERA 4` reads exactly that.
- **A2 — Parada without terna (Pitalito).** The surveyor typed `28` after an anchor
  linked to `CALLE 13 # 3-20`. The **"Última capturada"** card (seen right after
  saving, without opening any list) reads `CALLE 13 # 3-28` — composed from the
  anchor's face.
- **A3 — No prefix available.** Parada without terna and no earlier R1-linked or
  parseable anchor on the parada: `28` reads `28`, as today.
- **A4 — Swept parada, read-only.** Opening a swept parada from the parada list
  shows its rows with the same rule.
- **A5 — Rural / place name.** `FINCA CANAÁN` reads as is.
- **A6 — Spec 18 / lot / empty.** `placa = null` + link → "Sin placa a la vista ·
  enlazada a …"; plate-less lot → "Lote"; empty, unlinked, not a lot → "Sin
  dirección aún". All unchanged.

## Business rules
- **BR1 — Full address or cruce = shown as is.** If the stored text's **first word
  is a via type** (CALLE, CL, CARRERA, KR, … — the app normalizer's via list, which
  mirrors the backend's `address.py`), it is a full address or a cruce and is shown
  exactly as stored.
- **BR2 — Bare distance = composed.** Otherwise (it does not start with a via) it is
  a bare distance and is shown as «vía principal # vía generadora-» + distance (+ the
  face's cardinal, as `composeParadaAddress` already places it).
- **BR3 — Prefix source, in order:** (1) the **parada's** terna when it carries one;
  (2) otherwise the **anchor's face in force when that capture was made** — the
  nearest earlier R1-linked (or parseable) capture of the same parada — i.e. what the
  live preview showed the surveyor (AM.8).
- **BR4 — No prefix available → bare.** Shown as stored.
- **BR5 — Cruce never composed** (it starts with a via, BR1).
- **BR6 — Unchanged states:** "Sin placa a la vista · enlazada a …" (Spec 18),
  "Lote", "Sin dirección aún".
- **BR7 — Rural / non-address text** (does not start with a via, no prefix source
  on a rural parada) → shown as is.
- **BR8 — One rule, three screens:** resume list, "Última capturada", swept-parada
  rows — all through the same function.
- **BR9 — Display only.** Never rewrites the stored placa nor the pushed payload.
- **BR10 — Distance with letter or BIS** (`28A`, `28 BIS`) is a distance → composed.

## Edge cases and error handling
- **Leading/trailing spaces or lowercase** (`  calle 20a # 3-11`): the first-word
  check is case-insensitive after trimming; the text shown is the stored one,
  trimmed.
- **Abbreviated via** (`CL 20A # 3-11`, `KR 4`): counts as a via (normalizer list).
- **A "distance" that is actually a typo** (`3-11` without via): not a via first →
  composed (`CALLE 20A # 3-3-11`). Accepted: it reflects what was typed; the editor
  shows the raw text for correction.
- **Anchor row missing from the local directory** (directory reloaded): BR3 step 2
  finds no face → BR4 bare.
- **Frame-merged rows** (captured on another device): same rule; the prefix source
  is the local parada / local directory.
- **Open question OQ1 (for Jorge):** a parada WITH terna whose sweep crosses a
  generadora (e.g. the parada terna says `# 3-` but later doors are `4-xx` after a
  Coincide on `4-05`). BR3 uses the parada's terna first, so a later typed distance
  would compose with `3-` while the live preview (anchor's face) showed `4-`.
  Proposed: keep BR3 as approved; revisit only if seen in the field.

## Acceptance criteria
- **AC1.** Stored `28`, parada with terna `CALLE 20A # 3` → `CALLE 20A # 3-28`.
- **AC2.** Stored `CALLE 20A # 3-11` → `CALLE 20A # 3-11` (no duplication).
- **AC3.** Stored `CALLE 20A CON CARRERA 4` → shown as is.
- **AC4.** Parada without terna, earlier anchor linked to `CALLE 13 # 3-20`, stored
  `28` → `CALLE 13 # 3-28`.
- **AC5.** No terna and no anchor → `28`.
- **AC6.** `placa = null` + link → "Sin placa a la vista · enlazada a …";
  plate-less lot → "Lote"; empty unlinked → "Sin dirección aún".
- **AC7.** Resume list, "Última capturada" and swept-parada rows show the same text
  for the same capture.
- **AC8.** Stored placa and pushed payload unchanged (no write path touched).

## BDD (Gherkin)
```gherkin
Feature: Show the stored address without composing it twice

  Scenario: A bare distance on a parada with terna is composed
    Given a guided parada with terna "CALLE 20A # 3"
    And a capture stored with placa "28"
    When the surveyor opens "Revisar / editar placas"
    Then the row reads "CALLE 20A # 3-28"

  Scenario: A full address stored after "Coincide" is shown once
    Given a guided parada with terna "CALLE 20A # 3"
    And a capture stored with placa "CALLE 20A # 3-11"
    When the surveyor opens "Revisar / editar placas"
    Then the row reads "CALLE 20A # 3-11"

  Scenario: A corner-lot cruce is never composed
    Given a guided parada with terna "CALLE 20A # 3"
    And a lot stored with placa "CALLE 20A CON CARRERA 4"
    When the surveyor looks at the swept parada's rows
    Then the row reads "CALLE 20A CON CARRERA 4"

  Scenario: A distance on a parada without terna composes from the anchor
    Given a parada without terna
    And an earlier capture on it linked to R1 "CALLE 13 # 3-20"
    When the surveyor saves a capture typing "28"
    Then the "Última capturada" card reads "CALLE 13 # 3-28"

  Scenario: No prefix available keeps the distance as stored
    Given a parada without terna and no R1-linked capture on it
    And a capture stored with placa "28"
    When the surveyor opens "Revisar / editar placas"
    Then the row reads "28"
```

## Suggested tickets (each gated + committed + approved)
- **AD.1 — Spec** (this file). Gate: approved.
- **AD.2 — Display function.** Pure `displayPlaca(...)` implementing BR1–BR10, reusing
  the normalizer's via list and `composeParadaAddress`; unit tests for AC1–AC6 + the
  edge cases. Gate: analyze + tests.
- **AD.3 — Prefix source.** Resolve BR3 per parada (parada terna, else the face of the
  nearest earlier R1-linked/parseable capture) for the list screens; tests.
- **AD.4 — Wire the three screens** (resume list, "Última capturada", swept-parada
  rows) through the function; widget tests for AC7.
- **AD.5 — Emulator check** (local only, then cleanup): Ruta 20 (parada with terna:
  distance, Coincide, cruce) and Ruta 10 parada 1 (no terna: anchor + distance).
  Ruta 10 is the pilot route — local only, never sent, cleaned after.
