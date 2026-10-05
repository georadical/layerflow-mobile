import 'package:flutter/material.dart';

/// WIREFRAME — Spec 16, PL.1 "Parada list" (sequential, hard-locked navigator).
///
/// The route's paradas in `faceSequence` order, between route selection and
/// capture. Exactly one is **en curso** (the lowest unswept = `currentParada`);
/// earlier are **barridas**, later are **pendientes** and non-tappable. Closing
/// the current one unlocks the next. Hard lock: no skip, no "open anyway".
///
/// Spec anchors (specs/parada-list.md):
/// - BR1 one open parada at a time (the lowest unswept).
/// - BR2 closing is the only unlock; BR3 no skip/override.
/// - BR4 a parada may be closed with 0 placas (empty face).
/// - BR5 no user reopen in v1 (a done parada opens read-only).
/// - BR7 a route with no paradas falls back to the classic capture flow.
///
/// Same theme as the app so the design pass reviews what ships; structure and
/// copy are the wireframe delta.

/// State of one parada in the recorrido.
enum ParadaRowState {
  /// Already swept (closed). Opens read-only.
  done,

  /// The single current parada — the only one that opens for capture.
  current,

  /// Locked until its predecessor is closed. Not tappable.
  pending,
}

/// Dummy parada for the wireframe. Mirrors the shape the list reads from
/// `Paradas` + captures grouped by `stop_id`.
class WireframeParada {
  const WireframeParada({
    required this.faceSequence,
    required this.manzanaLabel,
    required this.state,
    this.placas = 0,
    this.sinEnviar = 0,
    this.ref,
  });

  final int faceSequence;
  final String manzanaLabel;
  final ParadaRowState state;

  /// How many placas captured in this parada so far.
  final int placas;

  /// Of those, how many are still queued (not yet sent).
  final int sinEnviar;

  /// Optional geographic reference hint (PC.6), when the manzana carries one.
  final String? ref;
}

/// Every UI state PL.1 has to handle.
enum ParadaListState {
  /// Stops being fetched / resumed.
  loading,

  /// The normal list: one current, some done, the rest pending.
  list,

  /// Every parada swept — the route is done.
  allDone,

  /// A route with zero paradas: falls back to the classic capture flow (BR7).
  emptyFallback,

  /// Stops pull failed and nothing is cached.
  networkError,
}

class ParadaListWireframe extends StatelessWidget {
  const ParadaListWireframe({
    super.key,
    required this.state,
    this.routeCodigo = '10',
    this.paradas = const [],
  });

  final ParadaListState state;
  final String routeCodigo;
  final List<WireframeParada> paradas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ruta $routeCodigo · ESP piloto-pitalito')),
      body: switch (state) {
        ParadaListState.loading => const _Loading(),
        ParadaListState.networkError => const _NetworkError(),
        ParadaListState.emptyFallback => const _EmptyFallback(),
        ParadaListState.list => _ParadaList(paradas: paradas),
        ParadaListState.allDone => const _ParadaList(paradas: allDoneParadas),
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Trayendo las paradas…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkError extends StatelessWidget {
  const _NetworkError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Sin conexión con el backend.',
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'No hay paradas guardadas en el dispositivo todavía.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const OutlinedButton(onPressed: null, child: Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// A route with no paradas: there is no list — the classic capture opens
/// instead (BR7 / D2). The wireframe names the fallback so it reads as
/// intended, not as a bug.
class _EmptyFallback extends StatelessWidget {
  const _EmptyFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Esta ruta no tiene paradas.',
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Se abre la captura clásica del recorrido.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const FilledButton(onPressed: null, child: Text('Capturar')),
          ],
        ),
      ),
    );
  }
}

/// The parada list with the route-progress header and (when anything is
/// queued) the Enviar bar on top. The list is the route home now (D1).
class _ParadaList extends StatelessWidget {
  const _ParadaList({required this.paradas});

  final List<WireframeParada> paradas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...paradas]
      ..sort((a, b) => a.faceSequence.compareTo(b.faceSequence));
    final total = ordered.length;
    final done = ordered.where((p) => p.state == ParadaRowState.done).length;
    final waiting = ordered.fold<int>(0, (n, p) => n + p.sinEnviar);
    final allDone = done == total;

    return Column(
      children: [
        _ProgressHeader(done: done, total: total, allDone: allDone),
        if (waiting > 0) _SendBar(waiting: waiting),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, i) => _ParadaTile(parada: ordered[i]),
          ),
        ),
      ],
    );
  }
}

/// Header: how much of the route is swept. "Ruta barrida" when all done.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.done,
    required this.total,
    required this.allDone,
  });

  final int done;
  final int total;
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              allDone ? 'Ruta barrida' : 'Recorrido por paradas',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            '$done / $total barridas',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The route-level Enviar, shared with the resume view it replaces (D1).
/// Appears only when something is waiting.
class _SendBar extends StatelessWidget {
  const _SendBar({required this.waiting});

  final int waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$waiting sin enviar',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          FilledButton(onPressed: () {}, child: const Text('Enviar')),
        ],
      ),
    );
  }
}

/// One parada row. The state (barrida / en curso / pendiente) leads, then the
/// parada number and its block. Only the current row opens for capture; a
/// pending row is inert (BR3), a done row opens read-only (BR5).
class _ParadaTile extends StatelessWidget {
  const _ParadaTile({required this.parada});

  final WireframeParada parada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = parada.state == ParadaRowState.current;
    final pending = parada.state == ParadaRowState.pending;
    final done = parada.state == ParadaRowState.done;

    // Placa count line: "— sin barrer" before, "0 placas" for an empty swept
    // face, "N placas" otherwise, "· J sin enviar" when queued.
    final placaLine = StringBuffer();
    if (pending) {
      placaLine.write('pendiente');
    } else {
      placaLine.write('${parada.placas} placa${parada.placas == 1 ? '' : 's'}');
      if (parada.sinEnviar > 0) placaLine.write(' · ${parada.sinEnviar} sin enviar');
    }

    final (icon, iconColor) = switch (parada.state) {
      ParadaRowState.done => (Icons.check_circle, theme.colorScheme.primary),
      ParadaRowState.current => (
          Icons.radio_button_checked,
          theme.colorScheme.primary
        ),
      ParadaRowState.pending => (
          Icons.lock_outline,
          theme.colorScheme.onSurfaceVariant
        ),
    };

    // The current parada is the protagonist: a filled container pulls the eye
    // to the only row that acts. Pending rows recede (muted, locked).
    return Material(
      color: current
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        // Hard lock: pending rows do nothing (BR3). A tap shows why.
        onTap: pending
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Se desbloquea al cerrar la parada anterior.'),
                  ),
                )
            : () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Parada ${parada.faceSequence}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: pending
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (current) const _StateChip(label: 'en curso'),
                        if (done)
                          const _StateChip(
                            label: 'barrida',
                            muted: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${parada.manzanaLabel} · ${placaLine.toString()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (parada.ref != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '📍 ${parada.ref}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Only actionable rows show the chevron; a pending row does not
              // invite a tap.
              if (!pending)
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = muted
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primary;
    final fg = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

/// Dummy route mid-recorrido: three paradas swept (one with a queued placa),
/// one en curso, two still locked — across two manzanas.
const wireframeDummyParadas = <WireframeParada>[
  WireframeParada(
    faceSequence: 1,
    manzanaLabel: 'Mz 5',
    state: ParadaRowState.done,
    placas: 3,
  ),
  WireframeParada(
    faceSequence: 2,
    manzanaLabel: 'Mz 5',
    state: ParadaRowState.done,
    placas: 2,
  ),
  WireframeParada(
    faceSequence: 3,
    manzanaLabel: 'Mz 5',
    state: ParadaRowState.done,
    placas: 5,
    sinEnviar: 2,
  ),
  WireframeParada(
    faceSequence: 4,
    manzanaLabel: 'Mz 27',
    state: ParadaRowState.current,
    placas: 1,
    sinEnviar: 1,
    ref: 'PARTE',
  ),
  WireframeParada(
    faceSequence: 5,
    manzanaLabel: 'Mz 27',
    state: ParadaRowState.pending,
  ),
  WireframeParada(
    faceSequence: 6,
    manzanaLabel: 'Mz 27',
    state: ParadaRowState.pending,
  ),
];

/// Dummy route fully swept — including one empty face closed with 0 placas.
const allDoneParadas = <WireframeParada>[
  WireframeParada(
    faceSequence: 1,
    manzanaLabel: 'Mz 5',
    state: ParadaRowState.done,
    placas: 3,
  ),
  WireframeParada(
    faceSequence: 2,
    manzanaLabel: 'Mz 5',
    state: ParadaRowState.done,
    placas: 2,
  ),
  WireframeParada(
    faceSequence: 3,
    manzanaLabel: 'Mz 27',
    state: ParadaRowState.done,
    placas: 0, // empty face closed with 0 placas (BR4)
  ),
];
