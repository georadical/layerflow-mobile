# Road to production — backlog (not scheduled)

Status: backlog. This is not a feature spec; it is the ordered list of what
stands between "functionally complete" and "real rollout". Each track below
becomes its own spec when it is scheduled. The guiding decision:
**run the pilot first** (Track D) — a real field day orders everything else
better than any plan on paper.

## Where we are (done, verified)
Specs 1–9 are complete and E2E-verified against the backend:
- Login + multi-ESP (5, 6), open/resume route (1, 1.1), strict-order placa
  capture + relocate + batch push + offline queue (2, 2.1, 3, 4),
  R1-assisted capture with photo evidence (7), extended survey PH/PV with
  the totalizador and the /sync/push chain (8), and route-state locks (9).
- The two-pass census flow works end to end and was proven live (Isnos /
  Ruta 10, 9/9 aplicada both sides).

What the app does NOT yet do, and the infra it does not yet have, is below.

## Track A — Field deployment infra
The app runs against the dev laptop (`10.0.2.2`) and the emulator. To reach
a real surveyor:
1. **Backend reachable from the street, HTTPS only.** Tokens must never cross
   plain HTTP; Android release blocks cleartext anyway. Needs the definitive
   base URL to configure in the app.
2. **Real provisioning (operator side):** `field`-role credentials for the
   real surveyors and `verificada` routes of the real ESP.
3. **Brute-force rate-limiting on login** — deliberately left out of the MVP
   "until any public deployment"; exposing the backend is that moment.
4. **Release APK on a physical phone** — never run outside the emulator /
   debug mode. Camera, storage, battery over a full day are unproven on real
   hardware.
5. **Signing / distribution** — release keystore, how the APK reaches the
   surveyors' phones (sideload vs store vs MDM).

## Track B — Rich census data (depth the app does not capture yet)
Today the survey emits ONLY `entidad_objetivo='unidad'`: the PH/PV structure
plus the four CL-E3 access/use answers. The full census needs the per-unit
sub-entities the contract already whitelists but the app never fills:
`hogar`, `connection`, `service_point`, `meter`, `meter_inspection` (each
riding its unit's instancia N; `premise` is predio-level, derived by the
backend). This is a real feature — new question sets, new field_responses,
and the promotion mapping for each — and should be its own spec, scoped by
what the pilot shows the office actually needs first.

## Track C — Backend / office dependencies (not app code)
- **Promotion / expansion engine (TJ.2)** — turns the declared structure into
  sibling census_codes at promotion. Office-side; the survey rows live in the
  observation layer (`estado=enviada`) until it runs. Tracked so the app team
  knows when a full round-trip (capture → survey → promotion → published
  census) can be demonstrated.
- **Reconciliation / office review UI** for unidad-aware sets, beyond what
  increment 5 renders.

## Track D — Pilot (do this FIRST)
One day, one surveyor, one real route, with the office watching what lands.
Goals: prove real hardware + real network + a real worker's day; surface the
edge cases short E2E cannot (many rows, big R1 directory, battery, spotty
signal, camera in the field). Its findings re-order Tracks A and B — build to
what the pilot proves, not to a guess.

## Notes carried over
- The old "Field deployment" backlog (README, noted 2026-09-12) is folded
  into Track A here.
- Ruta 10 (Isnos, a sample route) is left with `survey_estado=abierta` +
  `can_survey=true` for reusable E2E/regression testing.
