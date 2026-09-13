# Spec — R1-assisted capture (typeahead, field-confirmed NPN, selective photo)

> **Shared spec, mirrored copy** — source of truth in the backend repo
> (`specs/r1-assisted-capture.md`) @ `8d06a61` (frozen with the app's four
> contract observations and CL-R1…R5). Do not edit here — changes go through
> the backend session and get re-copied. App tickets: see
> [README.md](README.md), Spec 7.

Status: frozen (mobile observations incorporated 2026-09; backend TI.1–TI.3 pending)
Type: Backend / API + app contract → pipeline: Spec → Tickets → Implementation
Consumed by: the capture app (typeahead + OCR + photo UX) and office QA
Depends on: cadastral-reference-r1 (R1 loaded per tenant), field-capture-api,
npn-matching-engine + npn-match-resolution (become the divergence path)

## User story
As **a surveyor walking an assigned route**, I want the app to offer me the
**R1 addresses as I type the placa I see**, so picking the right one links the
unit to its NPN **at the door** — and when what I see is NOT on the list, record
reality just as fast, because divergence is what the census exists to find.

## Design verdict this spec encodes (evaluated 2026-09)
- **Accelerator, never a cage.** The R1 is not reality: new/subdivided/demolished
  units, informality and R1's own errors are absent from the list. A
  selection-first flow biases the surveyor to force-fit reality into the
  reference — the inverse of a census, and it starves Fantasma/Invasor (which
  live in the divergence). Therefore **"no está en la lista" is a first-class
  action, as fast and visible as selecting**.
- **Match at the door beats match at the desk.** The surveyor in front of the
  house is the best disambiguator; the office queue we just built stays as the
  **divergence queue** (its right size), not the default path.
- **Applies to the urban addressed core** (Isnos: 2,240 of 9,235 R1 rows carry
  an address). Rural stays classic coordinate-free capture — typeahead over
  "CASA MEJORA" is useless.
- **Store the pair, not just the pick:** observed placa (raw, as today) AND the
  selected NPN. If they differ, that difference is a census finding.
- **Photo: capture 100%, upload lazily, retain by policy** (revised 2026-09 —
  Jorge's observation): since the on-device OCR check points the camera at
  EVERY plate anyway, the marginal capture cost is ~zero. The real costs are
  upload and storage, so the tiers split:
  1. **Capture: 100%**, compressed (~150–300KB), stored on-device.
  2. **Upload: 100% but lazy** — divergence photos travel with the push
     (immediate evidence); everything else uploads WiFi-only (end of day).
  3. **Retention: by policy** — divergence photos permanent (census evidence);
     happy-case photos purged server-side after the QA window (default 90
     days) once sampling passed.
  Bonus of 100%: full evidence trail, re-audit possible, training material if
  server OCR is ever reconsidered.
- **Office second look: adaptive sampling, never 100%.** Review all divergences
  + a random sample of field-confirmed picks; widen/narrow by what the sample
  finds.
- **OCR: on-device only (soft-check).** Colombian plates (painted, ceramic,
  faded, handwritten) give server OCR mediocre accuracy for real pipeline
  complexity — rejected for now. On-device OCR (e.g. ML Kit, offline) as an
  instant "lo que leo no coincide, ¿confirmas?" assist is cheap and catches the
  error at the only place it can be fixed. Revisit server OCR only if office
  sampling shows systematic transcription errors.

## Scope
**Includes**
- `GET /field/r1-directory` — the tenant's addressed R1 slice for the app.
- Capture push: optional `npn` per item → `npn_match_method='field_confirmed'`
  (server-validated against the R1).
- Media: schema extension + binary upload endpoint for placa evidence.
- App-side contract (CL decisions, co-designed with the mobile session).

**Does NOT include**
- Server-side OCR (rejected above, reasons recorded).
- Universal mandatory photo.
- Typeahead for rural/unaddressed units.
- Editing the R1 from the app or the office.
- The office sampling/QA screen (its own spec once evidence flows; TI.5 stub).

## Contract
### `GET /field/r1-directory` (field token)
The ESP's R1 rows that carry an address, for offline typeahead:
```json
{ "version": "1789…", "items": [
  { "npn": "41359…", "direccion": "C 5 2 06",
    "direccion_norm": "CALLE 5 # 2-06", "manzana": "41359010000000012" } ] }
```
- Tenant-scoped by the token; ~2K rows for Isnos (trivial for SQLite).
- **`version`** (app request, freeze round): an opaque tag of the slice's
  current state. The app may send `?version=<known>`; on match the server
  answers `{ "version": …, "unchanged": true }` without items — skips the
  download. Full snapshot otherwise; no `since`/delta (re-evaluate if the
  directory grows 10×).
- Refreshed by the app at its sync moments; capture NEVER blocks on a stale
  directory.
- **No coordinates** (as everywhere in the field contract).

### Capture push — item gains `npn` (optional)
```json
{ "client_id": "…", "posicion": 4, "placa": "C 5 2-08", "npn": "41359…" }
```
- `npn` present → the server validates it exists in the ESP's
  `cadastral_reference`; unknown → **per-item error** (the batch continues).
  Valid → unit stored with `npn` + `npn_match_method='field_confirmed'`,
  `npn_match_confidence=null`.
- `placa` keeps carrying what the surveyor SAW (raw, BR8 unchanged) — the pair
  is the record. `npn` omitted/null → today's path (matcher later).
- Full-replacement upsert semantics unchanged (BR5): re-push without `npn`
  clears the link back to unmatched.
- **Frame carries the link (blocking fix from the app's review — the ins_after
  lesson):** `GET /field/capture/route/{id}` items gain `npn` and
  `npn_match_method`, so a device that resumes a route re-carries the link on
  every push exactly like it re-carries `ins_after`. Without this, BR5 +
  resume-on-another-device silently erases field_confirmed links.
- Duplicate `npn` within a route is **allowed server-side** — PH units
  legitimately share the predio's NPN (they expand later). The app warns
  locally on a second selection and marks it divergence (CL-R3 trigger 5);
  the server never rejects it.
- The matcher runner already skips units with an `npn` set — `field_confirmed`
  is never clobbered (documented, covered by test).
- `resolve-npn` stays pendiente-only (BR1): correcting a field_confirmed link
  goes through the normal census-code edit, audited.

### Placa evidence (photo)
- Schema: `media_assets.observation_set_id` becomes **nullable**; new nullable
  `census_code_id` FK + CHECK (at least one parent). Migration.
- `POST /field/capture/evidence` (field token, multipart): fields `client_id`
  (the unit's capture key), `soporte` (`divergencia` | `rutina` — the retention
  class, set by the app per CL-R3 trigger) + `foto`. Stores the binary under
  server-local storage (`data/media/<tenant>/…`, MVP) and creates the
  `media_assets` row (`proposito='placa'` fixed, `referencia`=storage key,
  linked to the unit's census_code by client_id). Idempotent per
  (unit, proposito): re-upload replaces.
- **Limits, pinned (freeze round):** JPEG only → otherwise `415`; size cap
  **500 KB** → otherwise `413`. Both reject the whole request (it carries one
  photo), never partially store. Client-side compression (JPEG ~70, longest
  side ~1600px) is the app's job and comfortably fits the cap.
- The media row carries `soporte` = `divergencia` | `rutina` so the retention
  job can tell them apart. Retention (server): `divergencia` permanent;
  `rutina` purged after the QA window (default 90 days) — the purge job is
  part of TI.5 (QA screen + lifecycle), not of the upload ticket.
- Retrieval for office QA: out of this spec (TI.5).

## Normalization — pinned algorithm (both sides MUST implement exactly this)
Canonical source: `backend/reconciliation/address.py` (`normalize_address`).
The app replicates it for typeahead filtering and the OCR comparison:
```
clean(raw):
  1. Unicode NFKD → drop non-ASCII (strips accents/ñ→n), UPPERCASE.
  2. Replace each of  # - . , ; :  with a space.
  3. Collapse whitespace runs to single spaces; trim.

normalize(raw):
  s = clean(raw); tokens = split(s)
  VIA map (first token only):
    C|CL|CLL|CALLE→CALLE · K|KR|CR|CRA|CARRERA→CARRERA ·
    A|AV|AVE|AVENIDA→AVENIDA · D|DG|DIAG|DIAGONAL→DIAGONAL ·
    T|TV|TRANS|TRANSVERSAL→TRANSVERSAL
  If tokens[0] ∉ VIA → not a street address (rural name); no direccion_norm.
  Else, over the remaining tokens:
    a. Extract structural suffixes anywhere: IN|INT|INTERIOR → interior flag;
       LO|LOTE|LT <v> → lote; MZ|MZA|MANZANA <v> → mz. Removed from core.
    b. Strip TRAILING pure-alpha tokens → barrio (in reading order).
    c. Core remainder maps positionally: num_via, num_cruce, placa.
  direccion_norm = "<VIA> <num_via> # <num_cruce>-<placa>"  (only if all 3).
```
Examples: `K 2 4A 09` → `CARRERA 2 # 4A-09`; `CL 5 Nº 2-06` →
`CALLE 5 # 2-06`; `SAMARIA` → (no street address). Any change to this
algorithm is a **contract change**: version-bumped here and announced.

## App-side contract (CL — PINNED with the mobile session, freeze round)
- **CL-R1** The placa field is free text (the observed truth, always
  editable); the suggestion panel filters the directory beneath it, with
  **"No está en la lista" as a FIXED first row of the panel, same tap size as
  any suggestion**. Hard rule: selecting an NPN NEVER overwrites the typed
  placa — the pair is stored as the doctrine requires.
- **CL-R2** On-device OCR (ML Kit, offline) as soft-check only. No
  per-line confidence (ML Kit does not expose it usefully): the check is
  **edit-distance over the two normalized strings** (the pinned algorithm
  above); similarity under threshold → "¿confirmas?". OCR reads nothing
  plausible → total silence, never interrupt. No OCR text reaches the backend.
- **CL-R3** Photo policy (three tiers): the app captures the plate photo on
  EVERY unit (the OCR frame is reused; no extra gesture; camera per capture,
  no permanent viewfinder). **Divergence triggers (mandatory, `soporte=
  divergencia`)**: (1) "no está en la lista", (2) selected-R1 ≠ observed
  placa, (3) plate illegible/absent, **(4) no physical plate but an NPN was
  selected by context — the most fragile link of all**, **(5) second
  selection of an NPN already used in the route** (the app warns locally;
  the second unit is marked divergence; the server accepts duplicates — PH).
  Everything else: `soporte=rutina`. Local purge only after the endpoint's 2xx.
- **CL-R4** Full snapshot with `version` tag (no delta); refresh at sync
  moments; capture never blocks on a stale directory.
- **CL-R5** **Nothing travels alone** (the app's manual-only doctrine covers
  photos too): every upload happens on the surveyor's Enviar gesture.
  Divergence photos ship on any network (chained after the placa push so the
  census_code exists); routine photos are included in that same gesture ONLY
  if WiFi is available at that moment — otherwise they wait for the next
  Enviar under WiFi. Zero silent transfers.

## Edge cases
- Same R1 address on several NPNs (PH sharing base address): the typeahead
  shows all; if the surveyor can't tell, "no está en la lista" + photo → the
  divergence queue decides with evidence.
- npn valid but from another tenant's R1: invisible (tenant-scoped lookup) →
  per-item error, same as unknown.
- Evidence upload for a client_id whose placa push failed: 404-equivalent
  per-request error; the app holds the photo (CR3 hold-until-resolved applies).
- Directory row removed by an R1 reload between download and push: the npn
  validation catches it → per-item error → app falls back to raw capture.

## Acceptance criteria
- Directory returns only addressed rows of the ESP; no coordinates.
- Push with valid `npn` → field_confirmed + pair stored; unknown `npn` →
  per-item error, batch unaffected; omitted → classic path.
- Matcher never touches field_confirmed units; resolve-npn refuses them (409).
- Evidence upload stores binary + linked media row; re-upload replaces;
  oversized/wrong-type → 4xx.
- Full suite green (existing capture/matcher/resolution behavior unchanged
  when `npn` is absent).

## Suggested tickets
- **TI.1 — R1 directory endpoint** (field token, addressed slice). Gate: pytest.
- **TI.2 — field_confirmed capture**: `npn` item field + validation + method +
  frame carries `npn`/`npn_match_method` (blocking fix) + runner-skip and
  resolve-refusal tests. Gate: pytest.
- **TI.3 — Placa evidence**: media schema migration + multipart upload endpoint
  + storage + replace semantics. Gate: alembic + pytest.
- **TI.4 — App-side (separate repo)**: typeahead + "no está en la lista" +
  OCR soft-check + photo triggers + chained evidence upload (their specs).
- **TI.5 — Office QA sampling screen** (later, own spec): divergences with
  photo + adaptive sample of field_confirmed.
