# Spec 12 — Captura de lote (`es_lote`)

> Status: **Draft** — spec phase. Branch `feature/captura-lote`.
> Pipeline: `Spec → Wireframe → Design → Implementation` (CLAUDE.md). Each phase
> ends with a verifiable gate, a commit and explicit approval.

Backend contract (LT.4): the `POST /field/capture/placas` item accepts a new
`es_lote: bool` (default false); the frame `GET /field/capture/route/{id}` already
returns `es_lote` per item (LT.1). The app consumes and displays it; the office
view (`direccion_lote`, `placa_predio`) is backend-side and out of scope here.

## User story
As a **field worker**, each predio on the route is either **Construido** (built) or
**Sin construir** (a vacant lot — `lote baldío`: an empty lot with no door/plate,
or a demolition lot that may still have an address). I want to pick that state with
a **segmented button** (Construido / Sin construir) in the capture form. Choosing
**Sin construir** makes the distance/placa field optional — I fill it when I can
read the address and leave it blank for an empty lot. The lot is **one more
parada** — it gets its `secuencia_parada` and enters the sequence. The backend
records it as `es_lote`; in the field I just pick the state and move on.

## Objective
Let the surveyor set a capture's built state with a **Construido / Sin construir**
segmented button (default Construido). "Sin construir" ⇒ `es_lote=true`, placa
optional. Carry the flag to the backend on push and back on resume; surface it in
the list. A lot **without** a placa is exempt from the mandatory photo; a lot
**with** a placa behaves like any predio.

## Scope

### Includes
- A **Construido / Sin construir** segmented button in the capture form (all capture
  modes), **default Construido** (`es_lote=false`).
- With **Sin construir** selected, the **distance/placa field is optional** (save
  allowed blank) and the R1 suggestions are hidden.
- **`es_lote`** sent on push (full-replacement) and read from the frame; persisted
  locally.
- A **"Lote"** indicator in the resume list; a plate-less lot reads **"Lote"** as
  its address.
- **Photo exemption** for a plate-less lot (`es_lote && placa == null`) — the app
  does not require the photo for it.

### Does NOT include
- The **operator/office view** (`direccion_lote`, `placa_predio`) — backend-side.
- Any change to the **urbano/rural classification** (still by the manzana zona).
- A separate lot screen or flow — it is the same form + the segmented button.
- The **backend carve-out** of the sweep photo gate (`_placas_sin_foto`) — that is
  the backend's own change; this spec only states the app side + the relayed
  decision.
- "Potrero" vs "demolición" as stored states — not distinguished; a lot is a lot,
  the difference only emerges from whether a placa exists.

## Actors and permissions
- **Field worker (titular or pareja)** — the only actor. Sets the built state.
- No new permission; same `field_token` scope as all capture.

## Preconditions
- The route is open and resumable on a `verificada` route.
- Parada-scoped capture (Spec 10) is in force; captures bind to a `stop_id`.
- The local DB can store the new flag (migration applied).

## Trigger
- On the capture screen, the surveyor selects **Sin construir** (or back to
  **Construido**) on the segmented button for the current predio.

## Main flow (happy path) — empty lot, no placa
1. The surveyor reaches a stop that is an empty lot (no door/plate).
2. They tap **Sin construir** on the segmented button. The distance/placa field
   becomes optional, and the R1 suggestions / "Coincide" (guided mode) are hidden.
3. They leave the placa blank, (optionally) take a photo of the lot and/or add an
   observación, and tap **Guardar y siguiente**.
4. The capture saves with `es_lote = true`, placa null — **no photo is required**
   (plate-less lot exemption), even on a `foto_obligatoria` route.
5. On **Enviar**, the push carries `es_lote: true` for the item; the backend
   assigns its `secuencia_parada` and returns it. The lot shows its `predio N`.

## Alternative flows (sad paths)
- **A1 — Demolition lot WITH an address.** The surveyor can read the address: pick
  **Sin construir**, type the distance/placa, **take the required photo** (a lot
  WITH a placa is NOT exempt), tap Guardar. Saved with `es_lote = true` and the placa.
- **A2 — Mis-set, corrected in the editor.** A normal predio was set Sin construir
  (or vice-versa). The surveyor opens the unit in **editar unidad**, switches the
  segmented button, and saves; the push re-carries the corrected flag
  (full-replacement).
- **A3 — Sweep a parada that contains a plate-less lot.** On a `foto_obligatoria`
  route, closing the parada does NOT block on the lot's missing photo (the lot is
  exempt) — provided the backend applies the same carve-out (relayed). Any
  non-exempt placa still without a photo blocks as usual.
- **A4 — Resume shows a lot.** Opening the route, the frame returns `es_lote`; the
  list marks the row **"Lote"**, with the composed address when it has a placa or
  just **"Lote"** when it has none.

## Business rules
- **BR1 — The flag.** `es_lote: bool`, default false, on the push item and the
  frame item. The app SENDS it and READS it; it never invents it.
- **BR2 — Full-replacement (not tri-state).** `es_lote` re-carries on **every**
  push of the item (like `npn`/`ins_after`): omitting it reverts to false
  server-side, so the app always sends the frame's value. Unlike `sin_r1`, it is a
  plain bool, not tri-state.
- **BR3 — The control.** A **segmented button** with two mutually-exclusive
  segments — **Construido** (default, `es_lote=false`) and **Sin construir**
  (`es_lote=true`). It replaces no existing field; it sits in the capture form in
  every mode. When **Sin construir** is selected the placa/distance may be blank;
  on **Construido** the field behaves exactly as today.
- **BR4 — Photo exemption (Jorge 2026-10-03).** `foto_obligatoria` still applies to
  every capture EXCEPT a **plate-less lot** (`es_lote && placa == null`), which is
  **exempt**. A lot WITH a placa requires the photo like any predio. The app
  enforces this in the save gate; the backend applies the matching carve-out in
  the sweep gate (`_placas_sin_foto`) — relayed and deployed. **Amended
  2026-10-14:** a lot whose placa is a **corner cruce** is exempt too — see
  **Amendment — Corner lot (cruce)** (BR-C3).
- **BR5 — A lot is one more parada.** It still gets a `secuencia_parada` and shows
  its `predio N` (Spec 11); it counts toward the parada and the sweep normally.
- **BR6 — No R1 / NPN on a lot.** A lot is never NPN-linked; with **Sin construir**
  selected the R1 typeahead / prediction / "Coincide" are hidden (nothing to link).
- **BR7 — Does not affect classification.** Urbano/rural (and the zona label) stay
  driven by the manzana zona (Spec 11); `es_lote` is orthogonal.
- **BR8 — Display.** The resume row carries a **"Lote"** indicator. A lot with a
  placa shows the composed address + the indicator; a plate-less lot shows **"Lote"**
  as the address. "Potrero" is not a term/state — it is just a lot with no placa.
- **BR9 — Default Construido.** The segmented button defaults to **Construido**
  (`es_lote=false`) for each new capture; flagging a lot is a per-capture,
  deliberate act. Switching to Sin construir does not erase already-typed text.

## Edge cases and error handling
- **Lot with a blank placa on a non-`foto_obligatoria` route** — saves fine; no
  photo involved either way.
- **Sin construir then a placa typed** — valid (demolition lot). The photo becomes
  required again (it has a placa). The address is stored and sent.
- **Sin construir, photo already taken, then placa left blank** — the photo is kept
  and uploaded (optional evidence of the lot); it just was not required.
- **Frame flips a row's `es_lote`** (office correction) — on resume the app takes
  the frame's value (source of truth), like `npn`.
- **Partial batch** — an item's `es_lote` rides with it; an `ok:false` item stays
  queued with its flag intact for the next Enviar.

## Acceptance criteria
- **AC1.** The capture form shows a Construido / Sin construir segmented button
  (default Construido); Sin construir makes the placa/distance optional and hides
  the R1 suggestions.
- **AC2.** A plate-less lot saves with `es_lote=true`, placa null, and is NOT
  blocked by `foto_obligatoria`.
- **AC3.** A lot WITH a placa still requires the photo on a `foto_obligatoria` route.
- **AC4.** `es_lote` is sent on every push of the item and read back from the frame;
  a local capture round-trips it.
- **AC5.** The resume list marks a lot row "Lote"; a plate-less lot reads "Lote".
- **AC6.** `es_lote` does not change the urbano/rural label or the `predio N`.
- **AC7.** The editor can switch `es_lote` on an existing capture.
- **AC8.** `flutter analyze` clean, `flutter test` green (DTO / DB / gate tests).

## BDD (Gherkin)

```gherkin
Feature: Set a predio's built state (Construido / Sin construir → es_lote)

  Background:
    Given a field worker on a verificada route with parada-scoped capture

  Scenario: Empty lot, no placa, photo not required
    Given the route has foto_obligatoria = true
    And the worker is on an empty lot
    When the worker selects "Sin construir"
    And leaves the placa blank
    And taps "Guardar y siguiente"
    Then the capture saves with es_lote true and no placa
    And no photo was required

  Scenario: Demolition lot with an address still requires the photo
    Given the route has foto_obligatoria = true
    When the worker selects "Sin construir"
    And types the distance "3-30"
    And taps "Guardar y siguiente" without a photo
    Then the save is blocked until a photo is taken

  Scenario: es_lote re-carries on every push (full-replacement)
    Given a synced lot capture with es_lote true
    When it is pushed again
    Then the request item carries es_lote true

  Scenario: Resume marks the lot
    Given the frame returns an item with es_lote true and no placa
    When the worker opens the resume list
    Then that row shows "Lote"

  Scenario: Sweep a parada containing a plate-less lot
    Given the route has foto_obligatoria = true
    And a parada has a plate-less lot with no photo
    When the worker closes the parada
    Then the plate-less lot does not block the sweep
    And any non-exempt placa without a photo still blocks it
```

## Suggested tickets (small, atomic)
- **LC.1 — Contract plumbing (DTOs).** `PlacaItemRequest.esLote` (sent,
  full-replacement) + `RouteFrameItem.esLote` (read). Tests against sample payloads.
- **LC.2 — Local storage.** `captures.esLote` column + migration **v21**; populate
  from the frame merge and from the capture; round-trip test.
- **LC.3 — Wireframe.** The Construido / Sin construir segmented button (placa
  optional + R1 hidden on Sin construir), the resume "Lote" indicator, and a
  plate-less "Lote" row — flat widgets, dummy data. Gate: renders.
- **LC.4 — Capture form wiring.** Segmented button → `es_lote`, optional placa,
  hide R1 suggestions, and the **photo exemption** for `es_lote && placa == null`
  in the save gate. Gate: a plate-less lot saves with no photo on a
  foto_obligatoria route; a lot with a placa still requires it.
- **LC.5 — Resume + editor.** "Lote" indicator + "Lote" address in the list;
  `es_lote` switchable in editar unidad.
- **LC.6 — Design pass.** Style the segmented button + the "Lote" indicator with
  theme tokens.
- **LC.7 — Manual E2E.** Mark a lot (with/without placa), Enviar, resume shows
  "Lote"; sweep a parada with a plate-less lot (backend carve-out is deployed).

## Open items
- **Backend carve-out — DONE (deployed 2026-10-03):** `es_lote && placa == null`
  is exempt from the sweep photo gate `_placas_sin_foto`. The app side can land
  independently; the end-to-end sweep test (LC.7) runs against the deployed backend.

---

## Amendment — Corner lot (cruce) · 2026-10-14

> Branch `feature/lote-cruce`. Decided by Jorge with the backend (relay
> "Cruce de lote: patrón confirmado + contrato"). Tickets **LX.1–LX.5** below.

### User story
As a **field worker**, when the first predio at a corner is an **empty lot with no
placa and no sign of where its entrance will be**, I cannot know whether R1 lists it
under one street or the other. I want to record it as **Sin construir** and write
the **two streets of the corner** — `CALLE 13 CON CARRERA 3` — so the office can
recognize it, without the app mistaking that text for a door address.

### Why
Written as a plain address, a cruce is parsed by the pinned normalizer as
`CALLE 13 # CON-CARRERA` (num_cruce = `CON`) — garbage, but non-null. Without `CON`
(`CALLE 13 CARRERA 3`) it parses to a **fake face** (`CALLE|13|CARRERA|odd`): verified
on the emulator (2026-10-14) it persists a false `ascendente` direction on the
parada, shows "Fin de la parada" right after the lot, switches the field to distance
mode composing garbage (`CALLE 13 # CARRERA-CALLE 13 # 3-42`), hides the R1
suggestions and raises a false acera-parity warning.

### Includes
- **LX — Cruce detector** mirrored from the authoritative normalizer
  (`backend/reconciliation/address.py`), exactly as the backend defines it.
- **Photo exemption** extended to a lot whose placa is a cruce.
- **Missing-`CON` guard** (app-only UX): a soft warning when a lot's text looks like
  two streets without `CON`.

### Does NOT include
- **Office dedup** of the same corner lot captured from both faces — backend/office
  (geometry: same manzana + adjacent faces + `es_lote`, cruce as confirmer; canonical
  key ordered so `CALLE 13 CON CARRERA 3` ≡ `KR 3 CON CL 13`). Separate backend spec.
- **Any new push/frame field.** The backend derives `es_cruce` from the raw placa;
  the app sends the placa as typed. No contract change.
- **R1 linking** of a cruce lot — it stays a hallazgo until the office resolves it.
- **Construido corner predios** — a built corner with a visible door is a normal
  predio registered only on the face of its door; the cruce convention does not apply.
- **Changing the pinned normalizer beyond the detector** (e.g. making the missing-`CON`
  form parse to null) — that is a contract change, the backend's call.

### Business rules
- **BR-C1 — Pattern (pinned, backend-defined).** After cleaning (pinned steps 1–3:
  ASCII, uppercase, `# - . , ; :` → space, collapse), the text is a **cruce** when the
  token `CON` is present **and** the token right after `CON` is in the pinned via map
  (`CALLE/CARRERA/AVENIDA/DIAGONAL/TRANSVERSAL` + abbreviations). `CON` is mandatory —
  a sentinel no real placa produces.
- **BR-C2 — Behavior on detection (mirror EXACTLY).** The normalizer stops before
  placa parsing: `esCruce = true`, `direccionNorm = null`. The raw text is kept as
  the placa (display + office dedup). Downstream this means: no face, no middle-anchor
  check, the lot does not anchor the parada, no R1 auto-link.
- **BR-C3 — Photo.** Exempt when `es_lote && (placa blank || esCruce)`. A demolition
  lot with a **real** placa keeps the photo requirement (BR4). Backend mirrors it in
  `_placas_sin_foto`.
- **BR-C4 — Missing-`CON` guard (app-only).** In **Sin construir** mode, if the text
  has two **street words** after cleaning (multi-letter via tokens only: `CALLE`,
  `CARRERA`, `AVENIDA`, `DIAGONAL`, `TRANSVERSAL`, `CL`, `CLL`, `KR`, `CR`, `CRA`, `AV`,
  `AVE`, `DG`, `DIAG`, `TV`, `TRANS` — single letters excluded to avoid
  `CALLE 13 A …` false positives) and **no** `CON`, then on **Guardar** a dialog asks
  *"¿Te falta CON?"* — example `CALLE 13 CON CARRERA 3` — with **[Corregir]** (back to
  the field) / **[Guardar igual]**. Soft, not a block: the heuristic can misfire.
- **BR-C5 — Both faces.** The corner lot is captured on **each** face/route that
  reaches it, written the same way; dedup is the office's (out of scope).

### Edge cases
- **First token not a street** (`VEREDA X CON CALLE 3`): mirror whatever the backend's
  detector returns — see Open item OI-C1.
- **`CON` followed by a non-via token** (`CALLE 13 CON 3`): not a cruce (BR-C1);
  normal parsing applies, unchanged.
- **Cruce typed in Construido mode:** the detector still yields `direccionNorm = null`
  (harmless), but no photo exemption (BR-C3 requires `es_lote`) and no guard (BR-C4 is
  lot-only).
- **Lowercase / accents / extra spaces** (`calle 13 con  cárrera 3`): handled by the
  pinned cleaning before detection.

### Acceptance criteria
- **AC-C1.** `normalizeAddress('CALLE 13 CON CARRERA 3')` → `esCruce = true`,
  `direccionNorm = null`; also for `KR 3 CON CL 13` and lowercase/accented input.
- **AC-C2.** Unchanged results for normal placas (`CALLE 13 # 3-20`), for
  `CALLE 13 CON 3`, and for the missing-`CON` form (`CALLE 13 CARRERA 3`).
- **AC-C3.** On a `foto_obligatoria` route, a Sin construir lot with a cruce saves
  **without** a photo; a Sin construir lot with a real placa still requires it.
- **AC-C4.** In Sin construir, `CALLE 13 CARRERA 3` + Guardar shows the
  *"¿Te falta CON?"* dialog; [Corregir] returns to the field, [Guardar igual] saves.
  `CALLE 13 A 3 20`-style text does not trigger it.
- **AC-C5.** Emulator: lot `CALLE 13 CON CARRERA 3` saves as predio 1, the parada
  direction stays NULL, the next R1 placa anchors and predicts normally.
- **AC-C6.** `flutter analyze` clean, `flutter test` green.

### BDD (Gherkin)
```gherkin
Feature: Corner lot recorded by its cruce

  Background:
    Given a field worker on a foto_obligatoria route, parada 1 with no captures

  Scenario: Corner lot with a cruce saves without photo and does not anchor
    When the worker selects "Sin construir"
    And types "CALLE 13 CON CARRERA 3"
    And taps "Guardar y siguiente"
    Then the capture saves with es_lote true and placa "CALLE 13 CON CARRERA 3"
    And no photo was required
    And the parada direction is still unset
    And the next R1 placa anchors the parada

  Scenario: Missing CON is caught softly
    When the worker selects "Sin construir"
    And types "CALLE 13 CARRERA 3"
    And taps "Guardar y siguiente"
    Then a dialog asks "¿Te falta CON?"
    When the worker taps "Corregir"
    Then the field is focused with the typed text intact

  Scenario: A demolition lot with a real placa still needs the photo
    When the worker selects "Sin construir"
    And types "CALLE 13 # 3-30"
    And taps "Guardar y siguiente" without a photo
    Then the save requires a photo
```

### Tickets (atomic, each gated + committed + approved)
- **LX.1 — Spec** (this amendment). Gate: approved.
- **LX.2 — Detector.** `NormalizedAddress.esCruce` + the BR-C1/BR-C2 cut in
  `address_normalizer.dart`, mirrored from `address.py`. Unit tests AC-C1/AC-C2.
- **LX.3 — Photo exemption.** Extend the two save-gate checks in `capture_screen.dart`
  to `es_lote && (blank || esCruce)`. Tests AC-C3.
- **LX.3b — Missing-`CON` guard.** Detector helper + the soft dialog (BR-C4). Tests AC-C4.
- **LX.4 — Emulator E2E** (both forms) AC-C5, then clean up.
- **LX.5 — Guide.** Remove the red pending notes in the pilot guide for Mauro.

### Status (2026-10-16)
- **LX.1 ✅** spec `e45a0e5` · **LX.2 ✅** detector `a5ceaa6` · **LX.3 ✅** photo
  exemption `c20e6e3` · **LX.3b ✅** missing-`CON` guard `42bc3e2`.
- **LX.4 ✅ E2E.** Emulator: `CALLE 13 CON CARRERA 3` and `KR 3 CON CL 13` save
  photo-free and do not anchor (the next R1 placa anchors and predicts);
  `CALLE 13 CARRERA 3` raises "¿Te falta CON?" ([Corregir] keeps the text, [Guardar
  igual] asks for the photo); a lot with a real placa (`45`) requires the photo.
  **Prod (Ruta 20):** lot `CALLE 20A CON CARRERA 3` pushed (census_code
  `01a1441a…5860`, `secuencia_parada=1`, `loc=5`, `direccion_norm` null) and the
  parada **swept without a photo**; backend `--cleanup` + local reset restored the
  baseline (0 capturadas, 0/1 barridas).
- **LX.5 ✅** pilot guide updated (red pending note removed; photo-optional bullet and the "¿Te falta CON?" check added to the corner-lot section). The guide `.docx` is a local, untracked deliverable.

### Open items
- **OI-C1 — RESOLVED (backend 2026-10-16).** `es_cruce` is evaluated AFTER the
  "first token is a via" check; a non-via start is a geographic reference
  (`VEREDA X CON CARRERA 3`, `13 CON CARRERA 3` → not a cruce). The app's cut is in
  the same place; pinned by tests.
