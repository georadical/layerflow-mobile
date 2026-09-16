# Spec — Route-state locks (capture pass + survey pass gating)

Status: draft (awaiting approval to implement)
Type: App-side gating against backend-owned route/worker flags → pipeline:
Spec → Tickets → Implementation
Consumed by: the capture app (resume list, capture entry, survey entry)
Depends on: field-login (the login response carries per-ESP tokens),
field-capture-api (the placa push + the route frame), extended-survey-phpv.md
@ d2bb861 (CL-E8, the survey lock's contract)

## User story
As **the office**, I want to control WHEN and BY WHOM each census pass runs on
a route — close a route's placa sweep once it is done, and open the extended
survey only for surveyors who are cleared — so that an inexperienced worker
cannot run the survey before they are ready and a finished route is not swept
again. The app must **reflect** these locks before any fieldwork, offline, and
never let a locked write reach the backend by surprise.

## Why (doctrine, already settled with CL-E8)
An app-only lock is theatre: bypassable, and two devices cannot agree from a
local flag. The **backend is the authority** and enforces at the write. The
app's only job is to **reflect** the lock — gate the entry *before* work, so
the worker never fills a form only to be rejected at Enviar. Two failure
directions, chosen deliberately:
- **Authorization → fail-CLOSED.** A missing survey flag means locked. Better a
  surveyor who must ask the office than one who censes without being cleared.
- **The pre-existing function → fail-OPEN.** A missing placa flag means open.
  Capture is what the app has always done; a route or an offline cache from
  before the flag existed must keep working — only an explicit `cerrada`
  disables it.

## The two locks (backend contracts — pinned)
### Survey lock — CL-E8 (extended-survey-phpv.md @ d2bb861; deployed cd283e7)
- `can_survey`: boolean per ESP, echoed in `POST /field/login` beside the token.
  Absent → **false**.
- `route.survey_estado` ∈ {`bloqueada`, `abierta`}, in `GET /field/routes` and
  the frame `GET /field/capture/route/{id}`. Absent → **bloqueada**.
- **Effective unlock = assigned ∧ `can_survey` ∧ `survey_estado='abierta'`.**
  Assignment is the silent third factor (a route only appears if assigned); the
  app ANDs the two flags it can see.
- Enforcement: `/sync/push` visit-create when not authorized →
  `resultado="error"` + `codigo="survey_no_autorizado"` (already mapped
  defensively in T8.1).

### Placa lock (deployed da98366; the twin, for pass 1)
- `route.placas_estado` ∈ {`abierta`, `cerrada`}, in `GET /field/routes` and the
  frame. Absent → **abierta** (only an explicit `cerrada` disables capture).
- Enforcement: `POST /field/capture/placas` to a closed route → **409** with
  `detail.codigo="ruta_placas_cerrada"`, nothing written.

## App behavior
- **DTOs**: `LoginEsp.canSurvey`; `RouteSummary` and `RouteFrame` gain
  `surveyEstado` and `placasEstado`, parsed with the fail-closed/open defaults
  above.
- **Persistence**: store `surveyEstado` and `placasEstado` on the `Routes`
  table (schema bump), updated on the frame merge and from the assigned-routes
  list, so the gates work **offline** with the last-known value.
- **Survey gate**: in the resume list, the per-unit survey chip is **locked**
  (a lock affordance, disabled entry) unless the effective unlock holds.
  Tapping a locked chip explains why ("La oficina no ha habilitado la encuesta
  en esta ruta" / "…para este encuestador"), never opens the form.
- **Placa gate**: when `placas_estado='cerrada'`, disable the "Capturar" FAB
  and the capture entry, with the reason shown. The resume list stays fully
  readable — the worker can still see, resume-edit and SEND what is already
  captured; only NEW capture is blocked.
- **Error mapping (defense in depth)**: a placa push that still races a close
  and gets `409 ruta_placas_cerrada` shows a clear message and leaves the queue
  untouched (no-verdict-no-change, as always); the survey push's
  `survey_no_autorizado` is surfaced when T8.5c wires that send.

## UI states
- **Survey chip**: `sin encuesta` / `a medias` / `completa` (existing) **+ a new
  `bloqueada`** state (lock icon, muted, non-navigating with an explanation).
- **Capturar FAB**: enabled / **disabled-with-reason** when placas cerrada.
- The route label and the captured list never hide — a lock changes what you
  can DO, not what you can SEE.

## Out of scope
- The operator UI that flips these flags (backend/operator side).
- The locks' authority model — the backend owns and enforces it; the app only
  reflects.
- The survey push itself (T8.5c). This spec gates the ENTRY; the push's error
  mapping is only noted here.
- Any change to the placa or survey data contracts.

## Edge cases
- **Flag flips while a route is open**: the next frame pull updates the stored
  estado; the gate follows on the next build. A capture already queued before a
  close still sends (the queue is the worker's; the 409 only refuses NEW writes
  server-side, and the app maps it without losing the row).
- **Offline**: gates use the last-known stored estado; fail-closed/open defaults
  apply when nothing was ever stored.
- **Survey opened, then can_survey revoked**: fail-closed — the entry locks
  again on the next login/refresh; a half-done local survey is NOT deleted (it
  simply cannot be pushed until re-authorized — the server would refuse it).
- **A route closed for placas but open for survey** (or vice-versa): the two
  gates are independent; each pass is gated by its own flag.

## Tickets (all on feature/extended-survey — the locks share plumbing)
- **L.1 — Foundation**: DTOs (`can_survey`, `survey_estado`, `placas_estado`) +
  `Routes` columns (schema v12) + providers exposing the effective unlock and
  the placa gate, with the fail-closed/open defaults. Gate: unit tests
  (parsing + defaults) + `flutter analyze`.
- **L.2 — Survey gate**: the locked survey chip/entry in the resume list
  (CL-E8), with the reason on tap. Gate: on-device (locked on Ruta 10 today;
  unlocked once the operator sets `can_survey` + opens `survey_estado`).
- **L.3 — Placa gate**: disable "Capturar" when `placas_estado='cerrada'` and
  map the `409 ruta_placas_cerrada` on the push. Gate: on-device + a push-error
  mapping test.

## To verify the happy path
The operator must mark `can_survey` on the surveyor and set the route's
`survey_estado='abierta'` (and keep `placas_estado='abierta'` for capture).
Until then, Ruta 10 shows the survey locked — which is the fail-closed lock
working, not a bug.
