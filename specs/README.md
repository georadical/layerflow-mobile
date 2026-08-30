# Specs — index and backlog

Every feature is born as a spec here before any code, and runs through
`Spec → Wireframe → Design → Implementation` (see CLAUDE.md). Each phase ends
with a verifiable gate, a commit and explicit approval.

| # | Spec | File | Status |
|---|------|------|--------|
| 1 | Open and resume route | [open-and-resume-route.md](open-and-resume-route.md) | Done — verified against the backend |
| 1.1 | One editable list per route | [one-editable-route-list.md](one-editable-route-list.md) | Done — verified against the backend |
| 2 | Strict-order capture (local) | — | Not written |
| 3 | Batch push (`POST /field/capture/placas`) | [push-captured-batch.md](push-captured-batch.md) | Done — verified against the backend |
| 4 | Offline-first queue and retry | — | Not written |
| 5 | Field worker login | — | Backlog, see below |
| 6 | Field worker across several ESPs | — | Backlog, see below |

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

## Spec 5 — Field worker login (backlog)

**Problem.** Today the operator issues a `field_token` and the worker pastes a
~500-character JWT into Ajustes. That is fragile and unpleasant on a phone in
the field.

**What login would and would not change.** Login does **not** remove tokens: it
replaces manual pasting with an exchange of credentials for the same kind of
token, which the app still stores. Any stateless HTTP API needs a credential
per request; the alternative is session cookies, which are worse on mobile.

**Gains**
- The worker types a username and a password instead of handling a JWT.
- The app can renew silently rather than the operator re-issuing.
- Revocation and audit per worker rather than per issued token.

**Costs and open questions — resolve before writing this spec**
- **Backend dependency**: there is no endpoint where a field worker
  authenticates and receives a `kind='field'` token.
  `POST /field-workers/{id}/field-token` is operator-driven.
- **Session lifetime versus offline work.** The current token lasts 30 days,
  which suits a worker with no signal for long stretches. A short session that
  forces reauthentication with connectivity would make field work *worse*. Any
  login design has to answer this first.
- Where the credential lives, and what happens when a session expires
  mid-route with pending captures in the local queue.

**Priority.** It does not block Specs 1–4. The current pain is UX, not
architecture. Do not fold it into Spec 1.

## Spec 6 — Field worker across several ESPs (backlog)

**Why it is coming.** Two operating models have to coexist:

1. **LayerFlow as consultant.** Our own staff runs the survey and the
   onboarding, so one person works across one *or several* ESPs.
2. **The ESP surveys itself.** Its surveyors are exclusive to that ESP.

So multi-ESP is an option to support, not the default. Whatever is built must
not add friction for the exclusive case, which is the simpler and probably the
more common one.

**Today.** A `field_token` is pinned to one ESP and `GET /field/routes`
answers with a single `esp` for the whole list, so two routes with the same
`codigo` from different ESPs can never collide on screen. The app stores one
token, so serving a second ESP means re-pasting a token in Ajustes.

**Answer this before estimating anything.** Is a field worker *a person*, or
*a person per ESP*? If `field_workers` carries a `tenant_id`, then the same
human is already two different workers, and identity, audit and "who captured
this" are split across ESPs. Every estimate depends on that answer.

### Path A — one token per ESP, switching in the client (recommended)
- Backend: little to nothing, at most an endpoint listing the worker's ESPs.
- Auth is untouched, so the tenant scoping that protects the data is untouched.
- Mobile: store `ESP → token`, add a switcher, and — the real work, not the
  dropdown — **partition local state by tenant**. The active route, the route
  cache and the drift database all assume a single ESP today.

### Path B — one token spanning several ESPs
- Every field endpoint currently trusts that the token carries exactly one
  tenant. Loosening that forces the tenant to travel per request and every
  query to be revisited.
- In a multi-tenant system this is the most security-sensitive change
  available: a mistake leaks data between ESPs. It needs adversarial review,
  and it belongs with Spec 5 rather than on its own.

**Web frontend:** not assessed. It lives in another repo and was not reviewed;
any estimate here would be invented.

**Priority.** Does not block Specs 1–4.
