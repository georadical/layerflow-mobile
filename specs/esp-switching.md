# Spec 6 — ESP switching (multi-ESP field worker, app side)

Status: approved 2026-09-12 — in progress
Type: Mobile app (Flutter). Zero backend work: the contract side was decided
and shipped with [field-login.md](field-login.md) (identity per person, one
token per ESP, Path A, `rutas_asignadas`). This spec is the client half that
CL5 deliberately left out of Spec 5.
Chain: Spec 5 → **6 (this one)**. Closes the multi-ESP thread opened in the
backlog (2026-09; the operating-model reasoning lives in the README).

## User story
**As** a field worker serving more than one ESP, **I want** to switch which
ESP I am working for without logging out and back in, **so that** I can cover
routes of both in one day — even without signal — and never mix one ESP's
data with the other's.

## Goal
Make the active ESP a switchable, clearly visible fact of the session, with
every piece of per-tenant local state following the switch — and nothing
else. No re-login, no network required, no data crossing tenants.

## What already holds (built by Spec 5, verified)
- The session stores **every** ESP with its own token; `chooseEsp` switches
  the active one, rewrites the mirrored `field_token` and invalidates every
  provider derived from it. Switching is already a local, offline-safe act.
- The drift database keys routes and captures by **route UUID**, which is
  globally unique — rows of two ESPs can coexist without collision, and a
  route list never shows another tenant's routes (the server scopes by
  token).
- The queue is bound to the **person**, not the ESP (CL4): switching ESP
  neither hides nor releases anyone's parked rows. Pending rows of an ESP-A
  route simply wait until that route is opened again.
- The ESP-choice screen at login (CL5) already renders names and
  `rutas_asignadas`.

## The gap this spec closes
- There is **no way to switch** after the login choice: today the worker
  would have to log out (parking their queue) and log back in — with signal.
- The assigned-routes **cache is a single slot**: with ESPs A and B, an
  offline fallback could serve A's cached list while B is active. That is
  the one real tenant leak in the client today.
- The ESP name shown in the selector comes from that same single-slot cache,
  so it can lag the switch.

## Scope

**Includes**
- **T6.1 — Tenant-partitioned routes cache.** The assigned-routes cache is
  keyed by `tenant_id`; the offline fallback only ever serves the active
  tenant's copy. The ESP display name comes from the session when one
  exists (the cache stays as fallback for the paste flow).
- **T6.2 — The switcher.** In the selector, the ESP header row becomes
  tappable when the session has more than one ESP: it opens the same choice
  UI as login (names + `rutas_asignadas`), marking the active one. Picking
  another calls `chooseEsp`, clears the **active route** (it belonged to the
  previous ESP), and the route list refetches — or falls back to that
  tenant's own cache offline. With a single ESP nothing changes visually.
- **T6.3 — Manual check** against the live backend: switch Isnos ↔ Elías,
  each list matches its tenant, capture on both sides, queues intact.

**Does NOT include**
- Any backend change. `rutas_asignadas` refreshes only on login/refetch of
  the route list; the switcher may show the login-time count (labeled by
  its list, which is the source of truth after picking).
- Mixing tenants on one screen (a combined route list across ESPs). One
  active ESP at a time stands.
- Per-ESP visual theming.
- The web frontend (other repo, not assessed).

## Actors and permissions
Field worker with a login session holding ≥ 1 ESP. The paste flow (CL1) has
exactly one implicit ESP and never sees a switcher.

## Preconditions
Session active. For the switcher to appear: more than one ESP in it.

## Trigger
The worker taps the ESP header in "Mis rutas".

## Main flow (happy path)
1. The selector header shows the active ESP; with several ESPs it is visibly
   tappable ("cambiar").
2. The worker taps it and sees the ESPs with their route counts, the active
   one marked.
3. They pick the other ESP. The app: switches the mirrored token
   (`chooseEsp`), clears the active route, returns to "Mis rutas".
4. The list refetches under the new token and the header shows the new ESP.
5. Opening a route, capturing, sending — everything already works, because
   every request simply carries the mirrored token.

## Alternative flows (sad paths)
- **A1 — Switching offline**: the switch itself always works (tokens are
  local). The route list falls back to the NEW tenant's cached copy, marked
  stale as today; with no cache for that tenant, the normal network-error
  state. Never the other tenant's list.
- **A2 — Push in flight during a switch**: the request already left with the
  old token and settles normally against its own ESP; the switch only
  affects requests issued after it. No guard needed beyond what exists.
- **A3 — An ESP revoked mid-day** (backend deactivates the worker there):
  its requests answer 403; the worker switches to the other ESP and keeps
  working. Login/refresh flows already handle the session-wide cases.
- **A4 — Route open when the switch happens**: switching happens from the
  selector, so no route screen is alive underneath; the cleared active
  route prevents "Continuar" from resurrecting the other tenant's route.

## Business rules
- **BR1** One active ESP at a time; the active token is always the mirror.
  Never a multi-ESP token (contract non-goal).
- **BR2** Switching is local and works offline. It costs zero requests.
- **BR3** The offline routes fallback is per tenant: cache under the wrong
  tenant is never shown. This is the tenant-isolation rule on the client.
- **BR4** Switching never touches the queue (CL4 owns queue semantics) and
  never modifies capture data.
- **BR5** The active route is per ESP: a switch clears it.
- **BR6** With one ESP, the switcher is absent — zero friction for the
  exclusive case, which is the common one.

## Edge cases and error handling
- Session with ESPs whose names collide: the row also shows the route count;
  `tenant_id` disambiguates internally.
- A tenant with zero routes shows the normal empty state, not an error.
- The `rutas_asignadas` shown in the switcher is the login-time snapshot;
  the list after picking is the live truth. Acceptable and labeled by
  outcome (the picker is context, the list is data).

## Acceptance criteria
- With two ESPs, the worker switches from the selector and the list follows
  the tenant, online and offline (each from its own cache).
- With one ESP, no switcher is visible.
- The active route never survives a switch.
- No screen ever shows tenant-A data under tenant-B's header.
- Queues per person are untouched by any number of switches.
- `flutter test` green + the manual check (T6.3) on the live backend.

## Suggested tickets
- **T6.1 — Per-tenant routes cache** + ESP name from session. Tests: cache
  isolation (save A, switch, B's fallback never serves A's list).
- **T6.2 — Switcher UI** in the selector header + clear active route on
  switch. Reuses the login choice widgets.
- **T6.3 — Manual check** on the live backend (Isnos ↔ Elías).
