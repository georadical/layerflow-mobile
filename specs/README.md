# Specs — index and backlog

Every feature is born as a spec here before any code, and runs through
`Spec → Wireframe → Design → Implementation` (see CLAUDE.md). Each phase ends
with a verifiable gate, a commit and explicit approval.

| # | Spec | File | Status |
|---|------|------|--------|
| 1 | Open and resume route | [open-and-resume-route.md](open-and-resume-route.md) | In progress — spec, wireframes and design approved; wiring under way |
| 2 | Strict-order capture (local) | — | Not written |
| 3 | Batch push (`POST /field/capture/placas`) | — | Not written |
| 4 | Offline-first queue and retry | — | Not written |
| 5 | Field worker login | — | Backlog, see below |

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
