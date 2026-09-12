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
| 6 | Field worker across several ESPs | [field-login.md](field-login.md) (shared) | Defined — Path A confirmed; app work after Spec 5 |

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
