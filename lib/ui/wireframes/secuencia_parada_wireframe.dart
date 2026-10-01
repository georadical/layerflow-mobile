import 'package:flutter/material.dart';

import '../theme.dart';

/// WIREFRAME — Spec 11, SP.3 "Per-parada sequence (predio M)".
///
/// Layout only, dummy data, no wiring (specs/secuencia-parada.md). Reviews WHERE
/// the per-parada number sits and HOW the two states read, before anything is
/// wired.
///
/// The shape this wireframe argues for:
/// - **The surveyor-global `posicion` is gone.** Every row/header that said
///   "posición N" now says the per-parada number instead. `loc` STAYS (it is
///   normativa/methodology), and the route "total N" count STAYS.
/// - **Context-aware label.** The resume list carries its own parada anchor
///   ("Parada N · predio M") because rows span paradas; the capture screen shows
///   only "predio M" (the parada is already named as "cara N" above).
/// - **Two states, cheap and redundant cues.** Provisional (pre-sync) = tilde +
///   muted/gray + a pending symbol ("⏳ predio ~3"); definitive (post-sync) =
///   no tilde, bold, green ("predio 3"). The exact gray/green tokens and the
///   pending glyph are the DESIGN phase's job — here they are only approximated.
/// - **Restart at 1 per parada, gaps verbatim, legacy → "predio —".**
enum SecuenciaState {
  /// The resume list: definitive rows, a gap, a restart-at-1, a provisional
  /// row, and a legacy (no stop_id) fallback.
  listaResume,

  /// Capture screen, last capture still PROVISIONAL (not synced).
  capturaProvisional,

  /// Capture screen, last capture DEFINITIVE (synced, server value).
  capturaDefinitiva,
}

class SecuenciaParadaWireframe extends StatelessWidget {
  const SecuenciaParadaWireframe({super.key, required this.state});

  final SecuenciaState state;

  @override
  Widget build(BuildContext context) {
    if (state == SecuenciaState.listaResume) return const _ResumeList();
    return _CaptureForm(state: state);
  }
}

/// How a per-parada number reads. The color/weight here is only an
/// APPROXIMATION of the Design intent (gray provisional / green definitive).
class _PredioNumber extends StatelessWidget {
  const _PredioNumber({
    required this.numero,
    required this.provisional,
    this.legacy = false,
    this.withParada,
  });

  /// The predio's per-parada number (ignored when [legacy]).
  final int numero;

  /// Pre-sync local count (tilde + gray + pending symbol) vs the synced value.
  final bool provisional;

  /// No stop_id / legacy capture → neutral "predio —", no color.
  final bool legacy;

  /// When set, prefixes "Parada N · " (resume list); null omits it (capture).
  final int? withParada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gray = theme.colorScheme.onSurfaceVariant;
    final base = theme.textTheme.bodyMedium;
    final prefix = withParada == null ? '' : 'Parada $withParada · ';

    if (legacy) {
      return Text('${prefix}predio —', style: base?.copyWith(color: gray));
    }

    if (provisional) {
      // Provisional: medium gray + the pending glyph (right before "predio",
      // never before "Parada N ·") + the tilde — all three cues (Spec 11, BR8).
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty)
            Text(prefix, style: base?.copyWith(color: gray)),
          Icon(Icons.cloud_upload, size: 15, color: gray),
          const SizedBox(width: 3),
          Text('predio ~$numero', style: base?.copyWith(color: gray)),
        ],
      );
    }

    // Definitive: only the NUMBER carries the state color (bold + green token);
    // the "Parada N ·" anchor stays neutral so the confirmed number pops.
    return Text.rich(
      TextSpan(children: [
        if (prefix.isNotEmpty)
          TextSpan(text: prefix, style: base?.copyWith(color: gray)),
        TextSpan(
          text: 'predio $numero',
          style: base?.copyWith(
            color: kPredioDefinitivo,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }
}

/// Resume list — rows span paradas, so each carries "Parada N ·". Shows the
/// restart-at-1, a real gap, a provisional row, and a legacy fallback. No
/// `posicion` anywhere; `loc` stays.
class _ResumeList extends StatelessWidget {
  const _ResumeList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // (parada, numero, provisional, legacy, loc, direccion)
    const rows = <(int, int, bool, bool, int, String)>[
      (1, 1, false, false, 5, 'CARRERA 4 # 2-03'),
      (1, 2, false, false, 10, 'CARRERA 4 # 2-09'),
      (1, 4, false, false, 15, 'CARRERA 4 # 2-17'), // gap: predio 3 deleted
      (2, 1, false, false, 20, 'CARRERA 8 # 5-02'), // restart at 1
      (2, 2, true, false, 25, 'CARRERA 8 # 5-10'), // just captured, provisional
      (0, 0, false, true, 30, 'FINCA LA ESPERANZA'), // legacy / no stop_id
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Ruta 10 · ESP Isnos (muestra)')),
      body: ListView.separated(
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Container(
              color: theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('6 direcciones capturadas',
                  style: theme.textTheme.titleSmall),
            );
          }
          final (parada, numero, prov, legacy, loc, dir) = rows[i - 1];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dir, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Per-parada number — replaces the old "posición N".
                    _PredioNumber(
                      numero: numero,
                      provisional: prov,
                      legacy: legacy,
                      withParada: legacy ? null : parada,
                    ),
                    const SizedBox(width: 8),
                    // loc STAYS (normativa) and the manzana context remains.
                    Text('· loc $loc · Zona: Urbana · Mz 111',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Capture screen — the per-parada number in the header and the "siguiente"
/// chip, in both states. Only "predio M" here (no "Parada N ·"): the parada is
/// already named as "cara N" in the strip.
class _CaptureForm extends StatelessWidget {
  const _CaptureForm({required this.state});

  final SecuenciaState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provisional = state == SecuenciaState.capturaProvisional;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              // The parada is named here as "cara N" — so the number below is
              // just "predio M", no "Parada N ·".
              child: Text('Cara 2 · ascendente',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // "Última capturada" card — "predio N" replaces "posición N";
          // "total N" and "loc" stay.
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Última capturada · ',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                      _PredioNumber(numero: 2, provisional: provisional),
                      Text(' · total 2',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('C 8 5 10', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        provisional ? Icons.cloud_upload : Icons.cloud_done,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        provisional
                            ? 'sin sincronizar · loc 25'
                            : 'sincronizada · loc 25',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Queue-status chip only — a non-actionable status pill (queue
          // visibility). The "Siguiente posición" chip is REMOVED: the
          // prediction card ("Siguiente esperada" + Coincide, Spec 10) already
          // guides what's next. The send control lives in the resume view
          // (Spec 3, BR2).
          const Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: Icon(Icons.cloud_done, size: 18),
              label: Text('Todo enviado'),
            ),
          ),
          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tomar foto de placa (requerida)'),
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Placa (dirección en la puerta)',
              hintText: 'C 8 5-10',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {},
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.check),
            label: const Text('Guardar y siguiente'),
          ),
        ],
      ),
    );
  }
}
