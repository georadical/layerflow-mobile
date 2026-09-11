# Spec 4 — Offline-first queue and manual retry

Status: done — T4.1 verified on device (migration v3 ran live)
Type: Mobile app (Flutter). No backend work: the contract already gives the
queue everything it needs (idempotent upsert by `client_id`, partial batches).
Chain: Spec 1 → 1.1 → 3 → 2 → 2.1 → **4 (this one)**.

> **This spec is mostly a review.** The queue was built across Specs 1–3 and
> already ships. Writing it down is what closes the capture cycle: it makes
> the retry-safety argument explicit, records the three decisions taken on
> 2026-09-11 (last-attempt visibility, per-route scope, capture never blocks),
> and declares what the queue deliberately does not do.

## User story
**As** a field worker covering routes where signal is intermittent or absent,
**I want** everything I capture to live on the phone and leave only when I
decide, with retries that can never duplicate or lose a unit, **so that** I
can work a full day without the network and hand the server exactly what I
walked, in the order I walked it.

## Goal
Make the queue's guarantees explicit and verifiable — nothing sends itself,
nothing is lost by retrying, nothing is marked failed without a server
verdict — and give the worker one missing piece of visibility: what happened
on the last attempt.

## What already holds (verified in review)
- **Capture never touches the network.** Rows are written to the local drift
  database (`Captures`) and survive app restarts and device reboots.
- **Nothing sends itself.** Every push and every retry is the worker pressing
  the one send control in the resume view (Spec 3, BR1–BR2). Regaining signal
  does nothing on its own.
- **Retry is idempotent by construction.** `client_id` is a per-unit UUID,
  stable across retries; re-sending it updates, never duplicates. Each attempt
  gets a fresh `batch_id`.
- **The batch is not all-or-nothing.** Each item is marked from its own
  result: accepted rows become `synced` (storing `loc` and the remote id),
  refused rows become `error` with the server's reason, shown in the list.
  An item the response omits is treated as failed, never silently synced.
- **No verdict, no error.** A transport or auth failure marks nothing: the
  queue stays exactly as it was and the caller maps the status code. Only a
  server verdict on the item's merits can mark a row `error`.
- **Refused rows stay queued.** `pending` selects everything not `synced`, so
  an `error` row travels again on the next send, with whatever content it has
  then — including its `ins_after` mark (Spec 2.1, BR3).
- **The queue is visible where it grows and where it sends**: the pending
  count shows on the capture screen (Spec 2, T2.1) and the send bar in the
  resume view.
- **Server truth merges without clobbering.** On resume, `posicion`/`loc`
  follow the frame even for queued rows; unsent content stays the worker's
  ("position belongs to the server; content belongs to the worker until
  sent").

## Scope

**Includes**
- The queue and retry behaviour as it stands, specified rather than rewritten.
- **Last-attempt visibility (the one new piece).** Today a failed send shows a
  momentary message; a worker who missed it sees only "pendiente" and cannot
  tell "never tried" from "tried an hour ago, no signal". The send bar should
  remember and show the route's last attempt: when, and how it ended.

**Does NOT include** — each one decided, not forgotten
- **Any automatic sending or retrying** (background sync, retry timers,
  sending on connectivity regained). Manual-only is doctrine, decided in
  Spec 3 and reaffirmed here.
- **A global queue view** across all routes on the device. The queue belongs
  to the route; sending happens from the open route. Decided 2026-09-11.
- **Blocking capture on an expired token.** Capture is offline-first and
  never gates on credentials; only the send needs the token. The banner warns,
  the push answers 401 with a clear message, and the queue waits intact for
  the new token. Decided 2026-09-11.
- **Deleting or discarding queued captures.** Append-only stands; there is no
  "drop this row" in the field.
- **The observation layer** (`/sync/push`, `/sync/pull`) — a different flow.

## Actors and permissions
Field worker with a `field_token`, on a route of their ESP. An expired token
still captures; it only cannot send.

## Preconditions
A route is open. For sending: at least one row not `synced`.

## Trigger
Capturing (grows the queue, always works) and pressing Enviar (drains it,
needs network and a valid token).

## Main flow (happy path)
1. The worker captures all day; every row lands in the local queue as
   `pending`. The count is visible while capturing and in the resume view.
2. When they decide — signal, wifi at the office, end of day — they press
   Enviar once.
3. The whole queue for that route goes as one batch with a fresh `batch_id`.
4. Each accepted item becomes `synced` with its `loc`. The bar reports the
   outcome and records the attempt.

## Alternative flows (sad paths)
- **A1 — No signal / transport failure**: the request never got a verdict, so
  the queue is untouched — every row still `pending`. The bar records the
  attempt ("último intento", when and why it failed) so the worker knows it
  was tried even if they missed the message. Retrying later is one tap, and
  safe (BR2).
- **A2 — 401/403 (token expired or wrong)**: same as A1 — nothing marked,
  queue intact — plus a message that sends the worker to Ajustes. Capture
  keeps working meanwhile.
- **A3 — Partial batch**: accepted items sync; refused ones turn `error` with
  the server's reason on the row. They stay queued and travel on the next
  send, so fixing the placa and re-sending is the whole repair procedure.
- **A4 — App killed mid-send**: the response was lost, so accepted items were
  never marked `synced` locally. The next send re-sends them; the server
  upserts by `client_id` and answers `updated` — no duplicates, and the rows
  sync then. This is exactly why the queue may only trust a verdict it saw.
- **A5 — Send with an empty queue**: a no-op with a friendly message; no
  request is made.

## Business rules
- **BR1** Capture works fully offline and is never blocked — not by signal,
  not by an expired token, not by a failed send.
- **BR2** Retrying is always safe: same `client_id` per unit, new `batch_id`
  per attempt. The server upserts; duplicates are impossible by contract.
- **BR3** Only a server verdict on the item's merits marks a row `error`.
  Transport and auth failures mark nothing.
- **BR4** A row leaves the queue only by becoming `synced` — and only when
  this device saw the verdict. Refused rows stay queued with their reason.
- **BR5** All sending is manual and per route, from the single send control
  (Spec 3, BR2).
- **BR6** The queue survives restarts: it lives in the database, not in
  memory.
- **BR7** The last attempt per route is remembered and shown: when it
  happened and how it ended. Recorded for failures at least; a success is its
  own record ("todo enviado").
- **BR8** Coordinate-free, as everywhere.

## Edge cases and error handling
- Double tap on Enviar: guarded; one batch in flight per route.
- Queue with only `error` rows: Enviar still sends them (they are pending by
  definition, BR4).
- Device clock is what timestamps the attempt; "hace X min" is best-effort
  and needs no server time.
- A route reopened on another device sees the server's rows via the frame;
  the local queue of *this* device never migrates.

## Acceptance criteria
- Rows captured with no network survive app restart and appear queued.
- A send with no signal leaves every row `pending` and records the attempt;
  the bar shows it after the message is gone.
- A send with an expired token does the same and points to Ajustes; capture
  still works.
- A partial batch syncs the accepted rows and leaves the refused ones queued,
  each showing the server's reason.
- Re-sending after any failure produces no duplicates on the server.
- `flutter test` green, plus a manual check on route 10: capture offline,
  send offline (attempt recorded), restore signal, send, verify.

## BDD (Gherkin)
```gherkin
Feature: Offline-first queue and manual retry

  Scenario: A day with no signal
    Given the device has no connectivity
    When the worker captures units and restarts the app
    Then every unit is still queued as pending
    And nothing was sent

  Scenario: Send attempt with no signal
    Given a queue with pending units
    When the worker presses Enviar and the request cannot reach the server
    Then every unit remains pending
    And the send bar shows when the attempt happened and that it failed

  Scenario: Retry cannot duplicate
    Given a send whose response was lost
    When the worker sends again
    Then the same client_ids travel with a new batch_id
    And the server updates instead of duplicating

  Scenario: Expired token
    Given the field token expired with units in the queue
    When the worker presses Enviar
    Then the queue is untouched and the message points to Ajustes
    And capturing more units still works

  Scenario: Partial batch
    Given a queue where one unit has an invalid value
    When the batch is sent
    Then the valid units become synced
    And the refused one stays queued showing the server's reason
```

## Suggested tickets
- **T4.1 — Last attempt record**: persist per route (when, outcome) and show
  it in the send bar. Note: if it lands in the `Routes` table it needs
  `schemaVersion` 3 and a migration step.
- **T4.2 — Tests**: attempt recording; the retry-safety and
  transport-failure tests already exist and stay.
- **T4.3 — Manual check** on route 10: the offline day, the failed attempt,
  the recovery. Leave the shared route clean afterwards.
