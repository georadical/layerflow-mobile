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

    return Scaffold(
      appBar: AppBar(
        title: Text(codigo == null ? 'Ruta' : 'Ruta $codigo'),
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

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.row});

  final Capture row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placa = row.placa?.trim();
    final hasAddress = placa != null && placa.isNotEmpty;
    final pending = row.syncStatus != AppConfig.syncSynced;

    final meta = <String>[
      'orden ${row.orden}',
      if (row.loc != null) 'loc ${row.loc}',
      if (row.manzanaCatastral != null) 'mz ${row.manzanaCatastral}',
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
                // The address in plain language leads. A missing one keeps the
                // size but goes muted and italic, so the gap reads as pending
                // rather than as a shorter address.
                Text(
                  hasAddress ? placa : 'Sin dirección aún',
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
          if (pending) const _PendingBadge(),
        ],
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
