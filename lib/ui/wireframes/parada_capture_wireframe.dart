import 'package:flutter/material.dart';

/// WIREFRAME — Spec 10, PC.2 "Parada-scoped capture" (the guided sweep).
///
/// Layout only, dummy data, no wiring. Reviews the face-by-face flow before
/// anything is built (specs/parada-capture-app.md).
///
/// The shape this wireframe argues for:
/// - **The parada rail is the route in walk order.** Paradas by
///   `face_sequence`, the current one (es_actual) open, swept ones behind it,
///   later ones locked — the sweep gate made visible. Same "one list" spirit
///   as the resume view: state shown where it is acted on.
/// - **The manzana stops being a field.** Inside a parada it is authoritative
///   from the face (read-only); the worker never types it. Only rural /
///   unassisted capture keeps the manual field.
/// - **Confirm, don't type.** After the first placa, the app PREDICTS the next
///   one (locally, from the cached R1) and the worker just confirms — or taps
///   "No coincide" and it becomes a finding. Typing is the exception.
/// - **The photo is part of the gesture** (foto_obligatoria): a face cannot
///   close until every placa on it has its photo.
enum ParadaState {
  /// The route's paradas in `face_sequence` order (current / swept / locked).
  railParadas,

  /// First placa of a face: manzana-bounded R1, no prediction yet.
  capturaPrimera,

  /// Assisted: the predicted next placa to confirm (or "No coincide").
  capturaPredicha,

  /// End of the face: nothing left to predict → "cara barrida".
  finCara,

  /// Trying to close a face with photo-less placas (foto_obligatoria).
  fotoPendiente,
}

class ParadaCaptureWireframe extends StatelessWidget {
  const ParadaCaptureWireframe({super.key, required this.state});

  final ParadaState state;

  @override
  Widget build(BuildContext context) {
    if (state == ParadaState.railParadas) return const _ParadaRail();
    return _CaptureForm(state: state);
  }
}

enum _Estado { actual, barrida, bloqueada }

/// The paradas of the route, in `face_sequence`. The gate is visible: swept
/// behind, current open, later locked.
class _ParadaRail extends StatelessWidget {
  const _ParadaRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rows = [
      (1, 'Manzana 001 · cara 1', 'N', _Estado.barrida, '8 placas · barrida'),
      (2, 'Manzana 001 · cara 2', 'E', _Estado.actual, '3 capturadas · en curso'),
      (3, 'Manzana 001 · cara 3', 'S', _Estado.bloqueada, null),
      (4, 'Manzana 002 · cara 1', 'O', _Estado.bloqueada, null),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text('4 caras · 1 barrida',
                        style: theme.textTheme.titleSmall),
                  ),
                  Text('parada actual: cara 2',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            );
          }
          final (seq, titulo, orient, estado, detalle) = rows[i - 1];
          final locked = estado == _Estado.bloqueada;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // face_sequence leads — it is the walk order.
                CircleAvatar(
                  radius: 16,
                  backgroundColor: estado == _Estado.actual
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text('$seq',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: estado == _Estado.actual
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$titulo ($orient)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: locked
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          )),
                      if (detalle != null) ...[
                        const SizedBox(height: 4),
                        Text(detalle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ],
                      if (estado == _Estado.actual) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Capturar en esta cara'),
                        ),
                      ],
                    ],
                  ),
                ),
                _EstadoChip(estado: estado),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final _Estado estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg, icon) = switch (estado) {
      _Estado.barrida => (
          'barrida',
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
          Icons.check_circle_outline,
        ),
      _Estado.actual => (
          'actual',
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          Icons.my_location,
        ),
      _Estado.bloqueada => (
          'bloqueada',
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
          Icons.lock_outline,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _CaptureForm extends StatelessWidget {
  const _CaptureForm({required this.state});

  final ParadaState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              // The parada context: face + manzana (authoritative) + direction.
              child: Text(
                state == ParadaState.capturaPrimera
                    ? 'Cara 2 · Manzana 001'
                    : 'Cara 2 · Manzana 001 · ascendente',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state == ParadaState.fotoPendiente) ...[
            const _FotoPendienteBanner(),
            const SizedBox(height: 16),
          ],

          // The manzana is shown, never typed — it comes from the face.
          _FaceContext(theme: theme),
          const SizedBox(height: 16),

          if (state == ParadaState.finCara)
            _FinCara(theme: theme)
          else ...[
            if (state == ParadaState.capturaPredicha) ...[
              _ExpectedPlaca(theme: theme),
              const SizedBox(height: 16),
            ],
            // The photo is required (foto_obligatoria): part of the gesture.
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.photo_camera),
              label: const Text('Tomar foto de placa (requerida)'),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Placa (dirección en la puerta)',
                hintText: 'C 5 2-15',
                helperText: state == ParadaState.capturaPrimera
                    ? 'Elige la dirección R1 de esta manzana, o escribe la '
                        'que ves.'
                    : 'Confirma la esperada, o escribe lo que ves.',
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
        ],
      ),
    );
  }
}

/// The face's manzana, authoritative and read-only (never a field here).
class _FaceContext extends StatelessWidget {
  const _FaceContext({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: const Icon(Icons.grid_4x4),
        title: const Text('Manzana 001 · cara 2 (Este)'),
        subtitle: Text('La manzana la fija la parada — no se escribe.',
            style: theme.textTheme.bodySmall),
      ),
    );
  }
}

/// The predicted next placa: confirm, or record a finding.
class _ExpectedPlaca extends StatelessWidget {
  const _ExpectedPlaca({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Siguiente esperada',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                )),
            const SizedBox(height: 4),
            Text('CALLE 5 # 2-15',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check),
                    label: const Text('Coincide'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.report_gmailerrorred),
                    label: const Text('No coincide'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// End of the face — nothing left to predict; close it.
class _FinCara extends StatelessWidget {
  const _FinCara({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.secondaryContainer,
          child: ListTile(
            leading: Icon(Icons.done_all,
                color: theme.colorScheme.onSecondaryContainer),
            title: Text('Fin de la cara',
                style:
                    TextStyle(color: theme.colorScheme.onSecondaryContainer)),
            subtitle: Text('No hay más direcciones esperadas en esta cara.',
                style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer)),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {},
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.flag),
          label: const Text('Marcar cara barrida'),
        ),
        const SizedBox(height: 8),
        Text('Desbloquea la siguiente parada.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

/// CL-analogue: the face cannot close while placas lack their photo
/// (foto_obligatoria_pendiente → names the pending locs).
class _FotoPendienteBanner extends StatelessWidget {
  const _FotoPendienteBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.photo_camera_back,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No puedes cerrar la cara: faltan fotos en loc 15 y loc 20.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
