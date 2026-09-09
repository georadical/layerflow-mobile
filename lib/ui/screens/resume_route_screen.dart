import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
import '../../data/repositories/capture_repository.dart';
import '../providers.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';

/// Resume view — Spec 1, T1.6/T1.7. Read-only list of what the route already
/// has, with the address leading (BR5).
///
/// It reads the local captures rather than the server response directly, so
/// rows still queued on the device appear next to the synced ones instead of
/// vanishing when the frame arrives (BR3).
class ResumeRouteScreen extends ConsumerWidget {
  const ResumeRouteScreen({
    super.key,
    required this.routeId,
    this.codigo,
  });

  final String routeId;
  final String? codigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = ref.watch(routeFrameProvider(routeId));
    final captures = ref.watch(capturesProvider(routeId));
    final online = ref.watch(isOnlineProvider);

    // The selector knows the codigo already; the other entry paths recover it
    // from the device once the frame has been merged.
    final routeCodigo =
        codigo ?? ref.watch(routeCodigoProvider(routeId)).valueOrNull;
    final esp = ref.watch(espNameProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routeLabel(codigo: routeCodigo, esp: esp),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaptureScreen(routeId: routeId)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Capturar'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(routeFrameProvider(routeId).future),
        child: switch ((frame, captures)) {
          // A failed pull only blocks when there is nothing local to fall back
          // on; otherwise the captures already on the device are still useful.
          (AsyncError(:final error), _)
              when captures.valueOrNull?.isEmpty ?? true =>
            _errorView(context, error),
          (AsyncLoading(), AsyncData(value: final rows)) when rows.isEmpty =>
            const _Loading(),
          (_, AsyncLoading()) => const _Loading(),
          (_, AsyncError(:final error)) => _errorView(context, error),
          (_, AsyncData(value: final rows)) => rows.isEmpty
              ? const _Empty()
              : _UnitList(
                  rows: rows,
                  // Says plainly that nothing was pulled, instead of implying
                  // the list reflects the server.
                  stale: !online || frame is AsyncError,
                ),
          _ => const _Loading(),
        },
      ),
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    void openSettings() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );

    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
          return _Message(
            icon: Icons.lock_outline,
            title: 'Token vencido o inválido.',
            body: 'Renuévalo en Ajustes.',
            action: 'Ajustes',
            onAction: openSettings,
          );
        case 403:
          return _Message(
            icon: Icons.block,
            title: 'Ese token no es de campo.',
            body: 'Pide un field_token al operador.',
            action: 'Ajustes',
            onAction: openSettings,
          );
        case 404:
          return const _Message(
            icon: Icons.wrong_location,
            title: 'Esa ruta no existe o no es de tu ESP.',
            body: 'Vuelve a Mis rutas y elige otra.',
          );
      }
    }
    return const _Message(
      icon: Icons.cloud_off,
      title: 'Sin conexión con el backend.',
      body: 'Se muestra lo que haya guardado en el dispositivo.',
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const _Message(
      icon: Icons.location_off,
      title: 'Ruta sin capturas aún.',
      body: 'Empieza a capturar la primera dirección del recorrido.',
    );
  }
}

/// Shared shape for empty and error states, inside a scrollable so the pull
/// gesture keeps working when there is no list to pull on.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 40, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: onAction, child: Text(action!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitList extends StatelessWidget {
  const _UnitList({required this.rows, required this.stale});

  final List<Capture> rows;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // clears the FAB
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant,
      ),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            children: [
              _FrameSummary(total: rows.length, stale: stale),
              // Only when there is a queue: a fully sent route carries no
              // dead control (Spec 3, BR2).
              if (rows.any((r) => r.syncStatus != AppConfig.syncSynced))
                _QueueBar(routeId: rows.first.routeId),
            ],
          );
        }
        return _UnitTile(row: rows[i - 1], allRows: rows);
      },
    );
  }
}

class _FrameSummary extends StatelessWidget {
  const _FrameSummary({required this.total, required this.stale});

  final int total;
  final bool stale;

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
          Text(
            stale ? 'sin reanudar (offline)' : 'reanudado',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The queue and the only way to send it (Spec 3, BR2).
class _QueueBar extends ConsumerWidget {
  const _QueueBar({required this.routeId});

  final String routeId;

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(pushProvider(routeId).notifier).send();
      if (!context.mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Envío completo.')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // The queue is untouched by any of these: a credentials or network
      // problem must never cost captured work (BR6).
      final detail = switch (e.statusCode) {
        401 => 'Token vencido o inválido — renuévalo en Ajustes.',
        403 => 'Ese token no es de campo — pide un field_token al operador.',
        404 => 'Esa ruta no existe o no es de tu ESP.',
        _ => 'No se pudo enviar: ${e.message}',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final waiting = ref.watch(pendingCountProvider(routeId));
    final sending = ref.watch(pushProvider(routeId));
    final online = ref.watch(isOnlineProvider);

    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_upload_outlined : Icons.cloud_off,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? '$waiting sin enviar'
                  : '$waiting sin enviar · sin conexión',
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
            // Disabled offline rather than hidden: the action should be
            // visibly unavailable, not missing.
            FilledButton(
              onPressed: online ? () => _send(context, ref) : null,
              child: const Text('Enviar'),
            ),
        ],
      ),
    );
  }
}

const _tipoAccesoLabels = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común',
  'otro': 'Otro',
};

class _UnitTile extends ConsumerWidget {
  const _UnitTile({required this.row, required this.allRows});

  final Capture row;

  /// The whole route, for naming this row's anchor and for the picker.
  final List<Capture> allRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placa = row.placa?.trim();
    final hasAddress = placa != null && placa.isNotEmpty;
    // Three distinct states, not two: a row the server refused is not a row
    // waiting its turn (Spec 3, BR3).
    final refused = row.syncStatus == AppConfig.syncError;
    final queued = row.syncStatus == AppConfig.syncPending;

    final meta = <String>[
      'posición ${row.posicion}',
      if (row.loc != null) 'loc ${row.loc}',
      if (row.manzanaCatastral != null) 'mz ${row.manzanaCatastral}',
    ].join(' · ');

    // Spec 1.1: this row is the only way into the editor. There is no second
    // list of the same route to hunt for.
    return InkWell(
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The address in plain language leads. A missing one keeps
                  // the size but goes muted and italic, so the gap reads as
                  // pending rather than as a shorter address.
                  Text(
                    hasAddress ? placa : 'Sin dirección aún',
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
                  // Pending relocation, naming the anchor (Spec 2.1). A line
                  // rather than a pill: the point is *which* unit it goes
                  // after, and that needs words.
                  if (row.insAfter != null)
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
                              'tras ${_anchorLabel(allRows, row.clientId, row.insAfter!)}',
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
                  // The server's reason, on the row. A refused unit is useless
                  // to the worker unless they can read why.
                  if (refused && row.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        row.syncError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (queued) const _PendingBadge(),
            if (refused) const _ErrorBadge(),
          ],
        ),
      ),
    );
  }

  /// Edits the unit's attributes. `posicion` is shown but never editable (BR1):
  /// it is the walking order the backend turns into `loc`.
  ///
  /// Saving marks the row `pending`; the push is idempotent by `client_id`, so
  /// a unit that came from the server is updated in place, not duplicated.
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final edit = await showDialog<_UnitEdit>(
      context: context,
      builder: (_) => _EditUnitDialog(row: row, allRows: allRows),
    );
    if (edit == null) return;

    final repo = ref.read(captureRepositoryProvider);
    // editCapture leaves insAfter alone (A3); the relocation change, if any,
    // is applied as its own step so cancelling one never loses the other.
    await repo.editCapture(
      clientId: row.clientId,
      placa: edit.placa,
      tipoAcceso: edit.tipoAcceso,
      manzanaCatastral: edit.manzana,
      observacion: edit.observacion,
    );
    if (edit.insAfterChanged) {
      if (edit.insAfter == null) {
        await repo.clearInsAfter(row.clientId);
      } else {
        await repo.setInsAfter(
            clientId: row.clientId, insAfter: edit.insAfter!);
      }
    }
  }
}

/// Human name for a row's anchor: the placa of the unit whose loc matches,
/// "el inicio de la ruta" for 0, or the bare loc when the anchor is not on
/// this device (set elsewhere, or dangling).
String _anchorLabel(List<Capture> rows, String excludeClientId, int target) {
  if (target == 0) return 'el inicio de la ruta';
  for (final r in rows) {
    if (r.clientId == excludeClientId) continue;
    if (CaptureRepository.anchorLoc(r) == target) {
      final placa = r.placa?.trim();
      return (placa == null || placa.isEmpty)
          ? 'la unidad ${r.posicion}'
          : placa;
    }
  }
  // Anchor not on this device: set elsewhere, or dangling after a rejection.
  return 'loc $target';
}

/// What the editor hands back. Null means the worker cancelled.
typedef _UnitEdit = ({
  String placa,
  String? tipoAcceso,
  String manzana,
  String observacion,
  bool insAfterChanged,
  int? insAfter,
});

/// Editor for one captured unit.
///
/// Stateful on purpose: it owns its TextEditingControllers and disposes them
/// with itself. Creating them in the caller and disposing right after
/// `await showDialog` looks equivalent but is not — the route keeps rebuilding
/// through its exit animation, and the rebuild hits controllers that were
/// already disposed.
class _EditUnitDialog extends StatefulWidget {
  const _EditUnitDialog({required this.row, required this.allRows});

  final Capture row;

  /// The whole route, for the anchor picker.
  final List<Capture> allRows;

  @override
  State<_EditUnitDialog> createState() => _EditUnitDialogState();
}

class _EditUnitDialogState extends State<_EditUnitDialog> {
  late final TextEditingController _placa;
  late final TextEditingController _manzana;
  late final TextEditingController _obs;
  String? _tipo;
  int? _insAfter;
  bool _insAfterChanged = false;

  @override
  void initState() {
    super.initState();
    _placa = TextEditingController(text: widget.row.placa ?? '');
    _manzana = TextEditingController(text: widget.row.manzanaCatastral ?? '');
    _obs = TextEditingController(text: widget.row.observacion ?? '');
    _tipo = widget.row.tipoAcceso;
    _insAfter = widget.row.insAfter;
  }

  /// Opens the anchor picker. The worker points at a unit; the number that
  /// travels as `ins_after` is derived, never typed (Spec 2.1, BR1/BR2).
  Future<void> _pickAnchor() async {
    final choice = await showDialog<_AnchorChoice>(
      context: context,
      builder: (_) => _AnchorPicker(
        candidates: [
          for (final r in widget.allRows)
            if (r.clientId != widget.row.clientId) r,
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.loc > 9999) {
      // Cannot happen through normal routes (loc 9999 = posicion ~2000), but one
      // bad value would cost the whole batch a 422 (BR6).
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esa unidad queda fuera del rango permitido.')));
      return;
    }
    setState(() {
      _insAfter = choice.loc;
      _insAfterChanged = true;
    });
    if (choice.anchorRefused) {
      // A5: warn, never block — the intent is still information, but a
      // dangling anchor can hold up other relocations behind it.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ojo: esa unidad fue rechazada por el servidor. '
            'La oficina no podrá aplicar el movimiento hasta corregirla.'),
      ));
    }
  }

  @override
  void dispose() {
    _placa.dispose();
    _manzana.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // posicion is shown, never editable (BR1).
      title: Text('Unidad · posición ${widget.row.posicion}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _placa,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Placa (dirección en la puerta)',
                helperText: 'Opcional: puede quedar en blanco.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // Not migrated to `initialValue`: FormFieldState ignores it
              // after the first build, and this rebuilds on every selection.
              // ignore: deprecated_member_use
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de acceso (opcional)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final e in _tipoAccesoLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tipo = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manzana,
              decoration: const InputDecoration(
                labelText: 'Manzana catastral (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            // Spec 2.1: the answer to the question the append-only note
            // raises — "what if I put it in the wrong place?".
            _RelocateRow(
              anchorLabel: _insAfter == null
                  ? null
                  : _anchorLabel(
                      widget.allRows, widget.row.clientId, _insAfter!),
              onPick: _pickAnchor,
              onClear: () => setState(() {
                _insAfter = null;
                _insAfterChanged = true;
              }),
            ),
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
          onPressed: () => Navigator.pop(context, (
            placa: _placa.text,
            tipoAcceso: _tipo,
            manzana: _manzana.text,
            observacion: _obs.text,
            insAfterChanged: _insAfterChanged,
            insAfter: _insAfter,
          )),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// What the anchor picker hands back. [loc] is what travels as `ins_after`;
/// [anchorRefused] triggers the dangling-anchor warning (A5).
class _AnchorChoice {
  const _AnchorChoice({required this.loc, this.anchorRefused = false});
  final int loc;
  final bool anchorRefused;
}

/// Entry to "Mover localización" inside the editor: shows the current anchor
/// or invites setting one. "Quitar" appears only when there is a mark.
class _RelocateRow extends StatelessWidget {
  const _RelocateRow({
    required this.anchorLabel,
    required this.onPick,
    required this.onClear,
  });

  final String? anchorLabel;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = anchorLabel != null;

    return InkWell(
      onTap: onPick,
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
                    marked
                        ? 'Va tras $anchorLabel'
                        : 'Va al final del recorrido',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (marked)
              TextButton(onPressed: onClear, child: const Text('Quitar')),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Anchor picker. The worker points at a unit — placa and posicion on show —
/// and the loc that travels as `ins_after` is derived (BR1/BR2). There is no
/// numeric field anywhere.
class _AnchorPicker extends StatelessWidget {
  const _AnchorPicker({required this.candidates});

  /// The route's units, already excluding the one being moved.
  final List<Capture> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              onTap: () => Navigator.pop(context, const _AnchorChoice(loc: 0)),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            for (final r in candidates)
              ListTile(
                title: Text(
                  (r.placa?.trim().isNotEmpty ?? false)
                      ? r.placa!.trim()
                      : 'Sin dirección aún',
                  style: (r.placa?.trim().isNotEmpty ?? false)
                      ? null
                      : const TextStyle(fontStyle: FontStyle.italic),
                ),
                subtitle: Text('posición ${r.posicion}'),
                onTap: () => Navigator.pop(
                  context,
                  _AnchorChoice(
                    loc: CaptureRepository.anchorLoc(r),
                    anchorRefused: r.syncStatus == AppConfig.syncError,
                  ),
                ),
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

/// Marks a row the server refused. Uses the error colour because, unlike a
/// queued row, this one will not resolve by waiting.
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

/// Marks a row that still lives only on the device. Offline queueing is the
/// normal field state, so it informs without competing with the address.
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
