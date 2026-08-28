import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
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
    final label = codigo ?? ref.watch(routeCodigoProvider(routeId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(label == null ? 'Ruta' : 'Ruta $label'),
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
        if (i == 0) return _FrameSummary(total: rows.length, stale: stale);
        return _UnitTile(row: rows[i - 1]);
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

const _tipoAccesoLabels = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común',
  'otro': 'Otro',
};

class _UnitTile extends ConsumerWidget {
  const _UnitTile({required this.row});

  final Capture row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placa = row.placa?.trim();
    final hasAddress = placa != null && placa.isNotEmpty;
    final pending = row.syncStatus != AppConfig.syncSynced;

    final meta = <String>[
      'orden ${row.orden}',
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
                ],
              ),
            ),
            if (pending) const _PendingBadge(),
          ],
        ),
      ),
    );
  }

  /// Edits the unit's attributes. `orden` is shown but never editable (BR1):
  /// it is the walking order the backend turns into `loc`.
  ///
  /// Saving marks the row `pending`; the push is idempotent by `client_id`, so
  /// a unit that came from the server is updated in place, not duplicated.
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final edit = await showDialog<_UnitEdit>(
      context: context,
      builder: (_) => _EditUnitDialog(row: row),
    );
    if (edit == null) return;

    await ref.read(captureRepositoryProvider).editCapture(
          clientId: row.clientId,
          placa: edit.placa,
          tipoAcceso: edit.tipoAcceso,
          manzanaCatastral: edit.manzana,
          observacion: edit.observacion,
        );
  }
}

/// What the editor hands back. Null means the worker cancelled.
typedef _UnitEdit = ({
  String placa,
  String? tipoAcceso,
  String manzana,
  String observacion,
});

/// Editor for one captured unit.
///
/// Stateful on purpose: it owns its TextEditingControllers and disposes them
/// with itself. Creating them in the caller and disposing right after
/// `await showDialog` looks equivalent but is not — the route keeps rebuilding
/// through its exit animation, and the rebuild hits controllers that were
/// already disposed.
class _EditUnitDialog extends StatefulWidget {
  const _EditUnitDialog({required this.row});

  final Capture row;

  @override
  State<_EditUnitDialog> createState() => _EditUnitDialogState();
}

class _EditUnitDialogState extends State<_EditUnitDialog> {
  late final TextEditingController _placa;
  late final TextEditingController _manzana;
  late final TextEditingController _obs;
  String? _tipo;

  @override
  void initState() {
    super.initState();
    _placa = TextEditingController(text: widget.row.placa ?? '');
    _manzana = TextEditingController(text: widget.row.manzanaCatastral ?? '');
    _obs = TextEditingController(text: widget.row.observacion ?? '');
    _tipo = widget.row.tipoAcceso;
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
      // orden is shown, never editable (BR1).
      title: Text('Unidad · orden ${widget.row.orden}'),
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
            const Text('El orden no se puede cambiar (append-only).'),
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
          )),
          child: const Text('Guardar'),
        ),
      ],
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
