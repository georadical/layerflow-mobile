import 'package:flutter/material.dart';

/// WIREFRAME + DESIGN — Spec 1, T1.3 "Resume route" view (read-only).
///
/// Layout was approved in the wireframe phase; this file now carries the
/// design pass on top of it. Structure and copy are unchanged: only
/// typography, colour and spacing come from the app theme.
///
/// Design intent — the screen is read outdoors, at arm's length, often in
/// sunlight: the address must win the page at a glance, and everything else
/// recedes to theme-muted secondary text.
///
/// Spec anchors (specs/open-and-resume-route.md):
/// - BR4 order is `loc` ascending (loc = orden * 5, assigned by the backend).
/// - BR5 the address (`placa`) is the protagonist; orden/loc are secondary
///   metadata. A null placa renders as "Sin dirección aún".
/// - Empty frame is a normal state, not an error.
/// - Local `pending`/`error` rows are preserved and marked as not-yet-sent.

/// Dummy row for the wireframe. Mirrors the shape of the merged local row.
class WireframeUnit {
  const WireframeUnit({
    required this.orden,
    required this.loc,
    this.placa,
    this.manzana,
    this.pending = false,
  });

  final int orden;
  final int loc;
  final String? placa;
  final String? manzana;
  final bool pending;
}

/// The four UI states the spec requires this screen to handle.
enum ResumeState { list, empty, loading, error }

class ResumeRouteWireframe extends StatelessWidget {
  const ResumeRouteWireframe({
    super.key,
    required this.state,
    this.routeCodigo = '10',
    this.units = const [],
  });

  final ResumeState state;
  final String routeCodigo;
  final List<WireframeUnit> units;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ruta $routeCodigo')),
      body: switch (state) {
        ResumeState.loading => const _Loading(),
        ResumeState.error => const _Error(),
        ResumeState.empty => const _Empty(),
        ResumeState.list => _UnitList(units: units),
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
            'Trayendo lo capturado…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Sin conexión con el backend.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Se muestra lo que haya guardado en el dispositivo.',
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Ruta sin capturas aún.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Empieza a capturar la primera dirección del recorrido.',
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

/// Read-only list, ordered by `loc` ascending (BR4).
class _UnitList extends StatelessWidget {
  const _UnitList({required this.units});

  final List<WireframeUnit> units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...units]..sort((a, b) => a.loc.compareTo(b.loc));

    return Column(
      children: [
        _FrameSummary(total: ordered.length),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            itemBuilder: (context, i) => _UnitTile(unit: ordered[i]),
          ),
        ),
      ],
    );
  }
}

/// Header: how much of the route is already captured.
class _FrameSummary extends StatelessWidget {
  const _FrameSummary({required this.total});

  final int total;

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
              '$total direcciones capturadas',
              style: theme.textTheme.titleSmall,
            ),
          ),
          // Quiet confirmation that the frame came back from the server.
          Text(
            'reanudado',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One captured unit. The address leads; orden/loc are secondary metadata.
class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit});

  final WireframeUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAddress = unit.placa != null && unit.placa!.trim().isNotEmpty;

    // Secondary metadata line: the code nobody speaks in the field.
    final meta = <String>[
      'orden ${unit.orden}',
      'loc ${unit.loc}',
      if (unit.manzana != null) 'mz ${unit.manzana}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Protagonist: the address in plain language (BR5). A missing
                // one keeps the same size but goes muted and italic, so the
                // gap reads as "pending", never as a shorter address.
                Text(
                  hasAddress ? unit.placa! : 'Sin dirección aún',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: hasAddress ? FontWeight.w600 : FontWeight.w400,
                    fontStyle: hasAddress ? FontStyle.normal : FontStyle.italic,
                    color: hasAddress
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Not an error: offline queueing is the normal field state, so the
          // badge informs without competing with the address.
          if (unit.pending) const _PendingBadge(),
        ],
      ),
    );
  }
}

/// Pill marking a row that still lives only on the device.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'sin enviar',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// Dummy frame: mixed addresses, a blank placa and a not-yet-sent row.
const wireframeDummyUnits = <WireframeUnit>[
  WireframeUnit(orden: 1, loc: 5, placa: 'Calle 5 # 12-34', manzana: '001'),
  WireframeUnit(orden: 2, loc: 10, placa: 'Calle 5 # 12-40', manzana: '001'),
  WireframeUnit(orden: 3, loc: 15, manzana: '001'),
  WireframeUnit(orden: 4, loc: 20, placa: 'Carrera 8 # 5-11', manzana: '002'),
  WireframeUnit(
    orden: 5,
    loc: 25,
    placa: 'Carrera 8 # 5-19',
    manzana: '002',
    pending: true,
  ),
];
