# Spec — Field login (surveyor credentials + multi-ESP tokens)

> **Shared spec, mirrored copy (2026-09-11).** The source of truth lives in
> the backend repo (`specs/field-login.md`); both repos build against this one
> document. Do not edit here — changes go through the backend session and get
> re-copied. App-side tickets derived from it: see [README.md](README.md),
> Spec 5.

Status: draft (awaiting approval to implement)
Type: Backend / API (no UI except the operator provisioning section) → pipeline:
Spec → Tickets → Implementation (TG.5 UI runs Wireframe → Design → Implementation)
Consumed by: the capture app (their Spec 5 login / Spec 6 multi-ESP), operator UI
Depends on: auth-and-roles (users, argon2, JWT), campaign-assignment (field_workers)

## Identity decision (DECIDED 2026-09 — conditions this spec and the app's 5/6)
- **Person = `users`** (globally unique email, argon2 password, `is_active`).
  Credentials are **per person**.
- **Person-in-ESP = `field_workers`** (tenant-scoped; `activo`). Capture
  attribution stays **per person-ESP** — that split is the multi-tenant
  isolation guarantee, not a defect.
- The bridge **already exists in the schema**: `field_workers.user_id` (nullable
  FK → `users.id`), until now unused by auth. The same person in N ESPs = one
  `users` row + N `field_worker` rows linked by `user_id`.
- **Never a multi-ESP token.** One `kind='field'` token per ESP, identical in
  scope and permissions to today's operator-issued token. Switching ESP is a
  client-local act (app Path A).

## User story
As **a surveyor**, I want to log in with email + password and receive my field
access for **every ESP I work in**, so I stop pasting a 500-character token and
can recover access in the field without calling the office.

## Objective
Replace token-pasting with credentialed login while keeping everything that
works: 30-day offline life, per-ESP scoping, the existing field endpoints
untouched. Add what today does not exist: silent renewal and **effective
revocation** (today `require_field` never touches the DB — a deactivated
worker's token lives until expiry).

## Scope
**Includes**
- `POST /field/login` — credentials → per-ESP field tokens (fresh, always).
- `POST /field/token/refresh` — silent renewal with a grace window.
- Revocation check in `require_field` (DB-backed).
- Role `field` in `users` + operator provisioning (create/link credentials).
- Operator UI section for provisioning (Encuestadores).

**Does NOT include**
- Self-registration or password recovery flows (the operator resets — no email
  infrastructure in the MVP).
- A multi-ESP token (explicit non-goal, agreed with the app).
- Dashboard access for `field` users (the role gets no pages).
- Brute-force lockout/rate limiting (MVP accepts the same exposure as the
  dashboard login; revisit before any public deployment).
- Changes to `/field/capture/*`, `/field/routes`, `/sync/*` payloads (they only
  gain the revocation check via `require_field`).
- Retiring `POST /field-workers/{id}/field-token` — it stays as the operator
  path (workers without credentials yet, emergencies). Its retirement is a later
  phase, together with the app's manual paste fallback (CL1).
- ESP switching and per-tenant local-state partition in the app — Spec 6 (CL5).

## Contract
### `POST /field/login`
Request: `{ "email": "...", "password": "..." }`
Response `200`:
```json
{
  "worker": { "nombre": "Ana", "documento": "123" },
  "esps": [
    { "tenant_id": 3, "esp_nombre": "ESP Isnos", "field_worker_id": "uuid",
      "field_token": "<jwt kind='field', 30 días>" }
  ]
}
```
- **BR-FRESH:** login **always** issues fresh 30-day tokens — for every ESP, on
  every login, unconditionally. The grace window is a refresh-only concept;
  login authenticates with credentials, so it is the final recovery path and
  never returns stale or shortened tokens.
- `esps` carries one entry per **active** linked `field_worker` (`activo` true,
  user `is_active` true). All tokens travel in this one response; no follow-up
  round-trips.
- `401` bad credentials (indistinct message for unknown email vs wrong
  password); `403` valid credentials but no active linked field_worker.

### `POST /field/token/refresh`
- Auth: `Authorization: Bearer <field_token>` — the current token, which may be
  **expired up to 7 days** (the grace window applies HERE and only here; every
  data endpoint stays strictly 401 on expiry).
- Response `200`: `{ "field_token": "<fresh 30-day token, same worker+ESP>" }`.
- Runs the same revocation check as `require_field` — a deactivated worker or
  person cannot refresh.
- Beyond grace → `401` (recovery = login).
- Recovery hierarchy the app can rely on: connectivity → refresh (no
  credentials, within grace) → login (credentials, always available).

### Revocation (`require_field`, all field endpoints + refresh)
- After decoding the JWT: load the worker; `404`-equivalent `403` if missing,
  `403` if `worker.activo` is false, and — when `worker.user_id` is set —
  `403` if the linked `user.is_active` is false.
- Effect: deactivating a `field_worker` revokes that person **in that ESP**;
  deactivating the `user` revokes the person **everywhere**, both effective on
  the next request. Cost: one indexed PK read per request (acceptable).

### Provisioning (operator)
- `POST /field-workers/{worker_id}/credentials` `{ "email", "password" }` —
  operator-only (`require_operator`). Creates the `users` row with role
  `field` (or updates the password if the email already belongs to a `field`
  user) and links `field_workers.user_id`. Linking the SAME email from a
  second ESP's worker links to the same person — that is exactly the multi-ESP
  case. Refuses emails belonging to non-`field` users.
- Role `field` is a valid `users.role`; the dashboard login and role guards
  give it no pages/permissions.

## App-side decisions (client contract — proposed by the app, pinned here)
- **CL1 — Token paste is the exception, login is the norm.** Manual token paste
  in Ajustes survives as an **emergency fallback** (credentials not yet
  provisioned, contingency) and is retired in a later phase, together with a
  review of the operator-issued token path. The app should visually mark the
  paste path as excepcional.
- **CL2 — Silent refresh runs automatically** on app open (and opportunistically
  with signal) when the token is near expiry or within grace. This does NOT
  contradict the app's manual-only doctrine: that doctrine governs **capture
  data**; refresh moves no data — it only renews the credential. Pinned so no
  one reads it as a contradiction.
- **CL3 — The password is never stored on the device.** Used at login, then
  discarded; only tokens are stored (encrypted, never displayed, never logged —
  the app's BR7 already in force). Backend agrees; invariant of this spec.
- **CL4 — Logout wipes tokens, NEVER the local capture queue.** Chosen over the
  harder alternative (blocking logout with pendings): blocking is hostile in
  the field (shared devices, end of contract, battery swaps). On logout with
  pendings the app warns "tienes N sin enviar"; the queue stays parked **bound
  to the person who captured it** and resumes only when the SAME person logs
  back in. If a DIFFERENT person logs in on the device, the parked queue is
  neither merged nor pushed under the new identity — attribution is part of
  the data. (The server would not catch this swap: push auth is by token, so
  the queue-identity binding is a client responsibility.)
- **CL5 — Active ESP at login only.** When login returns several ESPs, the app
  picks one as active in that moment. ESP **switching** and the per-tenant
  partition of local state are **Spec 6 scope**, explicitly out of this spec.

## Alternative flows (sad paths)
- **A1 — wrong password / unknown email** → `401`, one indistinct message.
- **A2 — credentials OK, no linked active worker** → `403` "sin acceso de campo".
- **A3 — refresh beyond grace** → `401`; the app falls back to login.
- **A4 — worker deactivated mid-campaign** → next request (data or refresh)
  `403`; the local queue stays intact on the device; reactivating restores.
- **A5 — user deactivated** → same as A4 but across all ESPs.
- **A6 — credentials on a non-field email** (operator error) → `409` on the
  provisioning endpoint, nothing created.

## Edge cases
- A worker with credentials AND an operator-issued token: both are valid
  `kind='field'` JWTs; revocation governs both equally (the check is by worker,
  not by token).
- Same person, two ESPs, one deactivated: login returns only the active ESP;
  the other ESP's old token dies at the revocation check.
- Grace window vs offline weeks: a queue older than 30+7 days requires login —
  credentials are on the person, so still no office round-trip.
- Password change: old tokens keep working until expiry/refresh (JWTs are
  stateless); immediate cutoff = deactivate the user. Documented, accepted for
  MVP.

## Acceptance criteria
- Login returns one fresh 30-day token per active linked ESP; repeated logins
  always return fresh tokens (BR-FRESH).
- Refresh renews within grace (including expired ≤ 7 days) and refuses beyond.
- All field endpoints reject a deactivated worker/user on the next request.
- Provisioning links the same email across ESPs to one person; non-field email
  is refused; `field` role reaches no dashboard page.
- Existing app flows (capture, sync, routes) work unchanged with login-issued
  tokens.

## BDD (Gherkin)
```gherkin
Feature: Field login

  Scenario: Multi-ESP login returns one fresh token per ESP
    Given persona P linked to active workers in ESP A and ESP B
    When P logs in with valid credentials
    Then the response carries 2 esps entries, each with a fresh 30-day field token

  Scenario: Login is always fresh
    Given P logged in yesterday
    When P logs in again
    Then the returned tokens are newly issued 30-day tokens

  Scenario: Silent refresh within grace
    Given a field token expired 3 days ago
    When the app calls /field/token/refresh with it
    Then it receives a fresh 30-day token without credentials

  Scenario: Refresh beyond grace requires login
    Given a field token expired 10 days ago
    When the app calls /field/token/refresh
    Then the API responds 401

  Scenario: Deactivation revokes on the next request
    Given a valid token for worker W in ESP A
    When the operator sets W.activo = false
    Then W's next push/pull/refresh responds 403

  Scenario: Person-level deactivation revokes everywhere
    Given persona P with workers in ESP A and B and is_active = false
    When either token hits any field endpoint
    Then the API responds 403
```

## Suggested tickets
- **TG.1 — Role `field` + provisioning**: accept `field` in users; `POST
  /field-workers/{id}/credentials` (create-or-link by email, refuse non-field
  emails); dashboard guards give the role nothing. Gate: pytest.
- **TG.2 — `POST /field/login`**: credentials → per-ESP fresh tokens (BR-FRESH),
  401/403 paths. Gate: pytest.
- **TG.3 — `POST /field/token/refresh`**: grace window (7 días, refresh-only),
  revocation-checked. Gate: pytest.
- **TG.4 — Revocation in `require_field`**: DB check worker.activo +
  user.is_active; applies to every field endpoint. Gate: pytest (existing field
  tests keep passing + new revocation tests).
- **TG.5 — Operator UI (Encuestadores)**: credentials form (crear/enlazar email
  + reset password) in the Campañas section. Wireframe → design → wiring.
  Gate: renders, then manual round-trip.

### Downstream (separate)
- The app's Spec 5 (login screen, token store per ESP, refresh scheduling) and
  Spec 6 (ESP switcher) — their repo, against this contract.
