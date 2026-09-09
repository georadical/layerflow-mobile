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
/// - BR4 order is `loc` ascending (loc = posicion * 5, assigned by the backend).
/// - BR5 the address (`placa`) is the protagonist; posicion/loc are secondary
///   metadata. A null placa renders as "Sin dirección aún".
/// - Empty frame is a normal state, not an error.
/// - Local `pending`/`error` rows are preserved and marked as not-yet-sent.

/// Sync state of a row. Spec 3 BR3: `pending` and `error` are different
/// things and must look different — a row the server refused is not a row
/// waiting its turn.
enum UnitSync { synced, pending, error }

/// Dummy row for the wireframe. Mirrors the shape of the merged local row.
class WireframeUnit {
  const WireframeUnit({
    required this.posicion,
    required this.loc,
    this.placa,
    this.manzana,
    this.sync = UnitSync.synced,
    this.syncError,
    this.insAfterAnchor,
  });

  final int posicion;
  final int loc;
  final String? placa;
  final String? manzana;
  final UnitSync sync;

  /// Reason the server gave. Shown on the row, never hidden in a log.
  final String? syncError;

  /// Label of the unit this one goes after, or "el inicio de la ruta".
  /// Null means no pending relocation. Spec 2.1: the worker points at a unit,
  /// never types the number that travels as `ins_after`.
  final String? insAfterAnchor;
}

/// Every UI state this screen has to handle, Spec 1 and Spec 3 together.
enum ResumeState {
  /// Everything sent: no queue, no send control.
  list,

  /// Rows waiting plus one the server refused.
  queued,

  /// A batch in flight.
  sending,

  /// Rows waiting but no connectivity: sending is not offered.
  offlineQueued,

  /// A unit captured at the end and marked to be moved elsewhere.
  relocation,
  empty,
  loading,
  error,
}

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
        ResumeState.queued => _UnitList(units: queuedUnits, send: state),
        ResumeState.sending => _UnitList(units: queuedUnits, send: state),
        ResumeState.offlineQueued => _UnitList(units: queuedUnits, send: state),
        ResumeState.relocation =>
          _UnitList(units: relocationUnits, send: state),
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

/// List ordered by `loc` ascending (BR4), with the queue bar on top when
/// something is waiting to be sent.
class _UnitList extends StatelessWidget {
  const _UnitList({required this.units, this.send});

  final List<WireframeUnit> units;

  /// Null when everything is synced: no queue, so no send control at all.
  final ResumeState? send;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...units]..sort((a, b) => a.loc.compareTo(b.loc));
    final waiting = ordered.where((u) => u.sync != UnitSync.synced).length;

    return Column(
      children: [
        _FrameSummary(total: ordered.length),
        if (send != null) _QueueBar(waiting: waiting, state: send!),
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

/// The queue, and the only way to send it (Spec 3 BR2).
///
/// It sits directly above the rows it refers to: the count and the action are
/// in the same place as the badges they act on. It appears only when there is
/// something waiting, so a fully synced route carries no dead control.
class _QueueBar extends StatelessWidget {
  const _QueueBar({required this.waiting, required this.state});

  final int waiting;
  final ResumeState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sending = state == ResumeState.sending;
    final offline = state == ResumeState.offlineQueued;

    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off : Icons.cloud_upload_outlined,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              offline
                  ? '$waiting sin enviar · sin conexión'
                  : '$waiting sin enviar',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            // Disabled offline rather than hidden: the worker should see the
            // action exists and why it cannot run.
            FilledButton(
              onPressed: offline ? null : () {},
              child: const Text('Enviar'),
            ),
        ],
      ),
    );
  }
}

/// One captured unit. The address leads; posicion/loc are secondary metadata.
class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit});

  final WireframeUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAddress = unit.placa != null && unit.placa!.trim().isNotEmpty;

    // Secondary metadata line: the code nobody speaks in the field.
    final meta = <String>[
      'posición ${unit.posicion}',
      'loc ${unit.loc}',
      if (unit.manzana != null) 'mz ${unit.manzana}',
    ].join(' · ');

    // Spec 1.1: the row is the way into the editor. Unstyled on purpose —
    // this tap and the dialog it opens are the wireframe delta.
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _EditorWireframe(unit: unit),
      ),
      child: Padding(
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
                      fontWeight:
                          hasAddress ? FontWeight.w600 : FontWeight.w400,
                      fontStyle:
                          hasAddress ? FontStyle.normal : FontStyle.italic,
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
                  // Pending relocation, naming the anchor. A line rather than
                  // a pill: the point is *which* unit it goes after, and that
                  // needs words.
                  if (unit.insAfterAnchor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.low_priority,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'tras ${unit.insAfterAnchor}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // The server's reason, on the row itself. A rejected unit is
                  // useless to the worker unless they can read why (BR3).
                  if (unit.sync == UnitSync.error && unit.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        unit.syncError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Queued is the normal field state and stays quiet; refused is a
            // problem and reads like one (BR3).
            if (unit.sync == UnitSync.pending) const _PendingBadge(),
            if (unit.sync == UnitSync.error) const _ErrorBadge(),
          ],
        ),
      ),
    );
  }
}

/// WIREFRAME — Spec 1.1 editor. Plain fields, no styling of its own.
///
/// `posicion` is shown but never editable (BR1): it is the walking order, and
/// letting it be typed would break the append-only sequence the backend turns
/// into `loc`.
class _EditorWireframe extends StatelessWidget {
  const _EditorWireframe({required this.unit});

  final WireframeUnit unit;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Posición ${unit.posicion} · Loc ${unit.loc}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: TextEditingController(text: unit.placa ?? ''),
              decoration: const InputDecoration(
                labelText: 'Placa (dirección en la puerta)',
                helperText: 'Opcional: puede quedar en blanco.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: null,
              decoration: const InputDecoration(
                labelText: 'Tipo de acceso (opcional)',
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('—')),
                DropdownMenuItem(
                    value: 'puerta_calle', child: Text('Puerta a la calle')),
                DropdownMenuItem(
                    value: 'area_comun', child: Text('Área común')),
                DropdownMenuItem(value: 'otro', child: Text('Otro')),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Observación (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            // Spec 2.1: the way to fix a missed house is to say where this one
            // belongs, never to renumber. Sits next to the append-only note
            // because it is the answer to the question that note raises.
            _RelocateRow(anchor: unit.insAfterAnchor),
            const SizedBox(height: 12),
            const Text('La posición no se puede cambiar (append-only).'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Entry point to "Mover localización" from inside the editor: shows the
/// current anchor, or invites setting one.
class _RelocateRow extends StatelessWidget {
  const _RelocateRow({this.anchor});

  final String? anchor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = anchor != null;

    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _AnchorPickerWireframe(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.low_priority,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mover localización', style: theme.textTheme.bodyLarge),
                  Text(
                    marked ? 'Va tras $anchor' : 'Va al final del recorrido',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Clearing the mark is offered only when there is one to clear.
            if (marked)
              TextButton(onPressed: () {}, child: const Text('Quitar')),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// WIREFRAME — anchor picker. The worker points at a unit; the app derives the
/// number that travels as `ins_after` (Spec 2.1, BR1/BR2). There is no numeric
/// field anywhere.
class _AnchorPickerWireframe extends StatelessWidget {
  const _AnchorPickerWireframe();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The unit being moved is excluded from its own picker.
    final candidates = relocationUnits.where((u) => u.posicion != 6).toList();

    return AlertDialog(
      title: const Text('¿Después de cuál va?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('Al inicio de la ruta'),
              onTap: () => Navigator.pop(context),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            for (final u in candidates)
              ListTile(
                title: Text(
                  u.placa ?? 'Sin dirección aún',
                  style: u.placa == null
                      ? const TextStyle(fontStyle: FontStyle.italic)
                      : null,
                ),
                subtitle: Text('posición ${u.posicion} · loc ${u.loc}'),
                onTap: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Pill marking a row the server refused. Uses the error colour because,
/// unlike a queued row, this one will not resolve by waiting.
class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'rechazada',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
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

/// Dummy frame with everything already sent: mixed addresses and a blank
/// placa, so the address hierarchy can be judged on its own.
const wireframeDummyUnits = <WireframeUnit>[
  WireframeUnit(posicion: 1, loc: 5, placa: 'Calle 5 # 12-34', manzana: '001'),
  WireframeUnit(posicion: 2, loc: 10, placa: 'Calle 5 # 12-40', manzana: '001'),
  WireframeUnit(posicion: 3, loc: 15, manzana: '001'),
  WireframeUnit(
      posicion: 4, loc: 20, placa: 'Carrera 8 # 5-11', manzana: '002'),
  WireframeUnit(
      posicion: 5, loc: 25, placa: 'Carrera 8 # 5-19', manzana: '002'),
];

/// Dummy frame for Spec 2.1: a house captured last (posicion 6) and marked to go
/// after the first one — the missed-house case, with the walk order untouched.
const relocationUnits = <WireframeUnit>[
  WireframeUnit(posicion: 1, loc: 5, placa: 'Calle 5 # 12-34', manzana: '001'),
  WireframeUnit(posicion: 2, loc: 10, placa: 'Calle 5 # 12-40', manzana: '001'),
  WireframeUnit(posicion: 3, loc: 15, manzana: '001'),
  WireframeUnit(
      posicion: 4, loc: 20, placa: 'Carrera 8 # 5-11', manzana: '002'),
  WireframeUnit(
      posicion: 5, loc: 25, placa: 'Carrera 8 # 5-19', manzana: '002'),
  WireframeUnit(
    posicion: 6,
    loc: 30,
    placa: 'Calle 5 # 12-36',
    manzana: '001',
    sync: UnitSync.pending,
    insAfterAnchor: 'Calle 5 # 12-34',
  ),
];

/// Dummy frame with a queue: two rows waiting and one the server refused, the
/// partial-success case Spec 3 treats as normal (A1, A2).
const queuedUnits = <WireframeUnit>[
  WireframeUnit(posicion: 1, loc: 5, placa: 'Calle 5 # 12-34', manzana: '001'),
  WireframeUnit(posicion: 2, loc: 10, placa: 'Calle 5 # 12-40', manzana: '001'),
  WireframeUnit(
    posicion: 3,
    loc: 15,
    placa: 'Calle 5 # 12-48',
    manzana: '001',
    sync: UnitSync.pending,
  ),
  WireframeUnit(
    posicion: 4,
    loc: 20,
    manzana: '002',
    sync: UnitSync.pending,
  ),
  WireframeUnit(
    posicion: 5,
    loc: 25,
    placa: 'Carrera 8 # 5-19',
    manzana: '002',
    sync: UnitSync.error,
    syncError: 'Ya existe una unidad en esa posición de la ruta.',
  ),
];
