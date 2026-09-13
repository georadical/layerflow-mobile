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
| 7 | R1-assisted capture | [r1-assisted-capture.md](r1-assisted-capture.md) (shared) | App side built (T7.1–T7.5) — coordinated E2E pending |

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

## Field deployment (backlog — noted 2026-09-12, not scheduled)

The app is functionally field-ready (Specs 1–6 done, release APK builds
with network). What remains to actually go to the field is deployment
work, deliberately parked until the project decides to take that step:

1. **Backend reachable from the street, HTTPS only.** Today it runs on the
   dev laptop (`10.0.2.2`). Credentials and tokens must never travel over
   plain HTTP, and Android release blocks cleartext by default anyway.
   Needs the definitive base URL to configure in the app.
2. **Real provisioning** (backend/operator side): `field`-role credentials
   for the real surveyors and `verificada` routes of the real ESP.
3. **Brute-force rate limiting on login** — the shared spec left it out of
   the MVP "until any public deployment"; exposing the backend to the
   internet is that moment.
4. **Release APK on a physical phone** — never yet run outside the
   emulator or debug mode.
5. **Pilot before rollout**: one day, one surveyor, one real route, with
   the office watching what lands.

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
