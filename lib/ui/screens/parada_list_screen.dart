import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address/manzana_label.dart';
import '../../core/config/app_config.dart';
import '../../data/db/database.dart';
import '../../data/repositories/capture_repository.dart';
import '../providers.dart';
import '../widgets/send_bar.dart';
import 'capture_screen.dart';
import 'resume_route_screen.dart';

/// Spec 16 (PL.2) — the parada list, READ-ONLY render.
///
/// Paradas in `face_sequence` order, each marked **barrida / en curso /
/// pendiente** (BR1): the current one is the lowest unswept
/// ([currentParadaProvider]); earlier are swept, later are locked. Per-parada
/// placa counts come from [capturesProvider] grouped by `stop_id`.
///
/// This ticket only proves the states render from real data. Navigation (PL.3),
/// the Enviar/send header, and replacing the resume screen as the route home
/// (PL.4, D1) come next. Rows are inert here on purpose.
class ParadaListScreen extends ConsumerWidget {
  const ParadaListScreen({super.key, required this.routeId, this.codigo});

  final String routeId;
  final String? codigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opening a route is the sync moment (CL-R4): pull the frame + refresh the
    // R1 directory and the paradas. Fire-and-forget — the list renders from the
    // local cache and never blocks on it. The list is the route home now
    // (Spec 16/D1), so this fires here instead of on the demoted resume view.
    ref.watch(routeFrameProvider(routeId));

    final stopsAsync = ref.watch(routeStopsProvider(routeId));
    final routeCodigo =
        codigo ?? ref.watch(routeCodigoProvider(routeId)).valueOrNull;
    final esp = ref.watch(espNameProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routeLabel(codigo: routeCodigo, esp: esp),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // The full-route captures view + the placa editor live on the
          // demoted resume screen (Spec 16/D1, option A): reachable from here,
          // no longer the route home.
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Revisar / editar placas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ResumeRouteScreen(routeId: routeId, codigo: codigo),
              ),
            ),
          ),
        ],
      ),
      body: switch (stopsAsync) {
        AsyncError(:final error) => _ErrorView(error: error),
        AsyncData(:final value) => value.isEmpty
            ? _EmptyFallback(routeId: routeId)
            : _ParadaListView(routeId: routeId, stops: value),
        _ => const _Loading(),
      },
    );
  }
}

/// State of one parada row, derived from `swept` + the current parada.
enum _RowState { done, current, pending }

class _ParadaListView extends ConsumerWidget {
  const _ParadaListView({required this.routeId, required this.stops});

  final String routeId;
  final List<Parada> stops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final caps = ref.watch(capturesProvider(routeId)).valueOrNull ?? const [];
    final current = ref.watch(currentParadaProvider(routeId));

    final ordered = [...stops]
      ..sort((a, b) => a.faceSequence.compareTo(b.faceSequence));
    final total = ordered.length;
    final done = ordered.where((p) => p.swept).length;

    return Column(
      children: [
        // The route's queue + Enviar, shared with the demoted resume view.
        // Renders nothing when there is nothing to send.
        SendBar(routeId: routeId),
        _ProgressHeader(done: done, total: total),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, i) {
              final p = ordered[i];
              final state = p.swept
                  ? _RowState.done
                  : (current?.stopId == p.stopId
                      ? _RowState.current
                      : _RowState.pending);
              final onStop = caps.where((c) => c.stopId == p.stopId);
              final placas = onStop.length;
              final sinEnviar = onStop
                  .where((c) => c.syncStatus != AppConfig.syncSynced)
                  .length;
              // Hard lock (BR3): only the current parada opens for capture; a
              // done parada opens read-only (BR5); a locked one is inert and
              // explains why. There is NO path to capture a non-current parada.
              final onTap = switch (state) {
                _RowState.current => () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CaptureScreen(routeId: routeId),
                      ),
                    ),
                _RowState.done => () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _ParadaCapturesScreen(routeId: routeId, parada: p),
                      ),
                    ),
                _RowState.pending => () =>
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Se desbloquea al cerrar la parada anterior.'),
                      ),
                    ),
              };
              return _ParadaTile(
                parada: p,
                state: state,
                placas: placas,
                sinEnviar: sinEnviar,
                onTap: onTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Read-only captures of a swept parada (PL.3, BR5). A done parada opens here,
/// never back into capture — the route is swept in strict order and a closed
/// parada is not re-entered for new placas (reopen/reinsertion is a future spec).
class _ParadaCapturesScreen extends ConsumerWidget {
  const _ParadaCapturesScreen({required this.routeId, required this.parada});

  final String routeId;
  final Parada parada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final caps = [
      for (final c
          in ref.watch(capturesProvider(routeId)).valueOrNull ?? const [])
        if (c.stopId == parada.stopId) c
    ]..sort((a, b) => CaptureRepository.anchorLoc(a)
        .compareTo(CaptureRepository.anchorLoc(b)));

    return Scaffold(
      appBar: AppBar(title: Text('Parada ${parada.faceSequence} · barrida')),
      body: caps.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Parada barrida sin placas.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              itemCount: caps.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              itemBuilder: (context, i) {
                final c = caps[i];
                final hasAddress =
                    c.placa != null && c.placa!.trim().isNotEmpty;
                return ListTile(
                  title: Text(
                    hasAddress ? c.placa! : 'Sin dirección aún',
                    style: TextStyle(
                      fontStyle:
                          hasAddress ? FontStyle.normal : FontStyle.italic,
                      color: hasAddress
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  subtitle: Text('loc ${CaptureRepository.anchorLoc(c)}'),
                );
              },
            ),
    );
  }
}

/// Header: how much of the route is swept. "Ruta barrida" once all are done.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDone = total > 0 && done == total;
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

/// One parada row. State leads (barrida / en curso / pendiente), then the parada
/// number and its block + placa count. Inert in PL.2 (PL.3 wires the taps).
class _ParadaTile extends StatelessWidget {
  const _ParadaTile({
    required this.parada,
    required this.state,
    required this.placas,
    required this.sinEnviar,
    this.onTap,
  });

  final Parada parada;
  final _RowState state;
  final int placas;
  final int sinEnviar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = state == _RowState.pending;
    final current = state == _RowState.current;
    final done = state == _RowState.done;

    final mz = parada.manzana != null ? manzanaLabel(parada.manzana!) : 'rural';
    final placaLine = StringBuffer(mz)..write(' · ');
    if (pending) {
      placaLine.write('pendiente');
    } else {
      placaLine.write('$placas placa${placas == 1 ? '' : 's'}');
      if (sinEnviar > 0) placaLine.write(' · $sinEnviar sin enviar');
    }

    final (icon, iconColor) = switch (state) {
      _RowState.done => (Icons.check_circle, theme.colorScheme.primary),
      _RowState.current => (
          Icons.radio_button_checked,
          theme.colorScheme.primary
        ),
      _RowState.pending => (
          Icons.lock_outline,
          theme.colorScheme.onSurfaceVariant
        ),
    };

    return Material(
      color:
          current ? theme.colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                          const _StateChip(label: 'barrida', muted: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placaLine.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // A locked parada does not invite a tap; the actionable rows do.
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
    final fg =
        muted ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
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

/// A route with no paradas: PL.7 will route it to the classic capture flow
/// (BR7/D2). Here it only names the fallback so the state reads as intended.
class _EmptyFallback extends StatelessWidget {
  const _EmptyFallback({required this.routeId});

  final String routeId;

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
              'Se captura en el flujo clásico del recorrido.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // PL.7 will route a no-paradas route straight to the classic flow;
            // for now the fallback is a plain entry into it.
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CaptureScreen(routeId: routeId),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Capturar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

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
            Text('No se pudieron cargar las paradas.',
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Se mostrará lo que haya guardado en el dispositivo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
