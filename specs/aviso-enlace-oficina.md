# Spec 21 — Adopt the office's current link ("enlace_cambiado_en_oficina")

> Status: **Draft** — spec phase. Branch `feature/aviso-enlace-oficina`.
> Pipeline note: no new screen — one extra line in the existing send summary.
> Wireframe/Design collapse into the implementation tickets; the gates are tests +
> a prod E2E with the backend (CLAUDE.md "Verificable").
> Relates to: **Spec 7** (R1 link), **Spec 15 v4** (placa-level link by
> `direccion_norm`), **Spec 18** (office review of "sin placa a la vista"), backend
> GD27 (contract §9, in production since 2026-10-21).

## User story
As a **field surveyor** who edits a predio already sent (e.g. from "Revisar /
editar") without refreshing the route, I want the app to **adopt the office's link**
when I send, if the office had already changed that predio's R1 link — so my phone
and the server do not diverge and I do not undo an office decision by mistake.

## Objective
Read the backend's additive `aviso` on a pushed item and mirror the office's link
locally, without re-sending anything.

## Background (backend relay 2026-10-21, GD27)
- If the phone sends **exactly the link the office replaced** (a local edit pending
  since before the refresh), the server **keeps the office's link** and stores
  everything else (placa, observación, tipo_acceso, es_lote). The item answers `ok`
  with three new fields: `{ …, aviso: "enlace_cambiado_en_oficina", npn,
  direccion_norm }` — one may be null (a multi-unit placa links by
  `direccion_norm` with `npn` null).
- Re-sending the office's link (taken from the frame) → no aviso. Choosing a
  **different, new** link → the field wins and the office reviews again.
- Additive: an app that ignores it loses nothing server-side.
- Today the app ignores it: `PlacaItemResult` does not read the fields, the row is
  marked synced, and the local link keeps the old value until the next frame merge.
  `setR1Link` (SE.9) re-queues the row, so it cannot be used to adopt.

## Scope
### Includes
- Parsing `aviso`, `npn`, `direccion_norm` on a pushed item.
- Adopting the returned link locally on `ok` + `enlace_cambiado_en_oficina`, without
  re-queuing.
- One line in the send summary.
- Tests + a prod E2E on Ruta 20 with the backend.

### Does NOT include
- Letting the surveyor dispute the office decision from the app (to propose another
  link they pick a different one; the office reviews it — backend rule).
- Any backend or contract change.
- The extended survey.
- Updating the R1 directory `capturada` flags immediately (next normal refresh).

## Actors and permissions
- **Surveyor** (field_token). No new permission.

## Preconditions
- A capture whose R1 link the office replaced, with a pending local change carrying
  the replaced link.

## Trigger
The surveyor taps **"Enviar"**.

## Main flow (happy path)
1. The office relinked loc 5 from `CALLE 20A # 3-03` to `CALLE 20A # 3-11`.
2. Before refreshing, the surveyor edits loc 5's observation and taps **"Enviar"**.
3. The server keeps `3-11`, stores the observation and answers `ok` with
   `aviso: "enlace_cambiado_en_oficina"`, `npn` of 3-11.
4. The app marks loc 5 synced and stores the npn of 3-11 locally (no re-send).
5. The send summary reads *"… La oficina cambió el enlace de 1 predio(s); se tomó el
   de la oficina."*
6. "Revisar / editar" shows loc 5 linked to `CALLE 20A # 3-11`.

## Alternative flows
- **A1 — Multi-unit placa.** The aviso carries `direccion_norm` and `npn` null: the
  app stores `direccion_norm`, clears `npn`.
- **A2 — Office removed the link.** Both null: the capture is left without link.
- **A3 — Unknown aviso value.** Ignored: synced as today, nothing adopted.
- **A4 — No aviso** (phone re-sent the office link, or chose a new one): unchanged
  behavior.
- **A5 — Several avisos in one send.** The summary counts them all (N).

## Business rules
- **BR1 — Adopt.** On `ok` + `aviso == "enlace_cambiado_en_oficina"`: mark synced
  (loc, secuencia_parada, remote_id as today) **and** write the returned `npn` and
  `direccion_norm` as they come. **Nothing is re-queued.**
- **BR2 — Unknown avisos are ignored.**
- **BR3 — Both null → no link.**
- **BR4 — Summary line:** *"La oficina cambió el enlace de N predio(s); se tomó el
  de la oficina."* appended to the send result; no dialog, no confirmation.
- **BR5 — No permanent badge**; lists show the adopted link naturally.
- **BR6 — Finding:** adopting a non-empty link clears "No está en la lista"
  (`sin_r1 = false`), as any link does; an empty adopted link leaves it untouched.
- **BR7 — Nothing else changes locally:** placa, observación, tipo_acceso, es_lote,
  photo, order.
- **BR8 — Directory flags** (`capturada`) update on the next normal refresh.
- **BR9 — Anchor and prediction** use the adopted link from then on (no extra logic).
- **BR10 — No contract change** (additive fields, already in production).

## Edge cases and error handling
- **Aviso on a row edited again meanwhile:** the adoption writes only the link
  fields and the sync state of the pushed row; a later local edit re-queues it as
  usual (it now carries the office link).
- **Missing `npn`/`direccion_norm` keys in an aviso item** (malformed): treated as
  null → BR3. Accepted: the backend contract always sends them.
- **`ok:false` with an aviso:** not possible per contract; the row follows the
  existing error path.

## Acceptance criteria
- **AC1.** An `ok` item with the aviso and an `npn` → row synced, local `npn` = the
  returned one, `direccion_norm` null, not pending.
- **AC2.** Same with `direccion_norm` and `npn` null → local link by
  `direccion_norm`.
- **AC3.** Both null → row synced without link.
- **AC4.** An unknown `aviso` → row synced, link unchanged.
- **AC5.** The send summary includes the N-predio line when N ≥ 1, and nothing new
  when N = 0.
- **AC6.** Placa, observación, tipo_acceso, es_lote unchanged after adoption.
- **AC7.** Prod E2E on Ruta 20: the office relinks, the phone sends a stale edit,
  the app ends linked to the office's row.

## BDD (Gherkin)
```gherkin
Feature: Adopt the office's current link

  Scenario: The office link is adopted without re-sending
    Given a capture linked to "CALLE 20A # 3-03" with a pending local edit
    And the office already relinked it to "CALLE 20A # 3-11"
    When the surveyor taps "Enviar"
    And the server answers ok with aviso "enlace_cambiado_en_oficina" and the npn of "CALLE 20A # 3-11"
    Then the capture is synced and linked to "CALLE 20A # 3-11"
    And it is not queued again
    And the send summary says the office changed the link of 1 predio

  Scenario: A multi-unit placa is adopted by its address
    Given the server answers the aviso with direccion_norm "CALLE 14 # 2-104" and npn null
    Then the capture is linked by direccion_norm "CALLE 14 # 2-104" with no npn

  Scenario: An unknown aviso is ignored
    Given the server answers ok with aviso "otro_aviso"
    Then the capture is synced and its link is unchanged
```

## Suggested tickets (each gated + committed + approved)
- **AO.1 — Spec** (this file). Gate: approved.
- **AO.2 — Data.** `PlacaItemResult` reads `aviso`, `npn`, `direccion_norm`;
  repository `adoptOfficeLink` (writes the link + `sin_r1` per BR6 without touching
  the sync state); tests AC1–AC4, AC6.
- **AO.3 — Sync + summary.** `_pushPlacas` adopts on the aviso and counts it; the
  send summary appends the BR4 line; tests AC5.
- **AO.4 — Prod E2E on Ruta 20** with the backend (needs Jorge's approval at the
  time), cross-cleanup.
