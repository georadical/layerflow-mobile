import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dtos.dart';
import '../providers.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';

/// Route selector — Spec 1, T1.5. Wires the approved design to
/// `GET /field/routes`.
///
/// The backend already scopes the list to this worker and to state
/// `verificada`, and already orders it by `codigo`, so this screen renders
/// what it receives without filtering or sorting (BR1).
class RouteSelectorScreen extends ConsumerWidget {
  const RouteSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assignedRoutesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      // Wraps every state: a worker who was just assigned a route, or who just
      // regained signal, can always pull to retry.
      body: RefreshIndicator(
        onRefresh: () => ref.read(assignedRoutesProvider.notifier).refresh(),
        child: async.when(
          loading: () => const _Loading(),
          error: (e, _) => _errorView(context, e),
          data: (data) => data.routes.items.isEmpty
              ? const _Message(
                  icon: Icons.inbox,
                  title: 'No tienes rutas asignadas en tu ESP.',
                  body: 'Si te acaban de asignar una, desliza para actualizar.',
                )
              : _RouteList(state: data),
        ),
      ),
    );
  }

  /// Maps the failure to the copy that tells the worker what to actually do.
  Widget _errorView(BuildContext context, Object error) {
    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
          return _Message(
            icon: Icons.lock_outline,
            title: 'Token vencido o inválido.',
            body: 'Renuévalo en Ajustes.',
            action: 'Ajustes',
            onAction: () => _openSettings(context),
          );
        case 403:
          // Valid token of the wrong kind: re-pasting the same one will not
          // help, so the copy asks for a different token instead.
          return _Message(
            icon: Icons.block,
            title: 'Ese token no es de campo.',
            body: 'Pide un field_token al operador.',
            action: 'Ajustes',
            onAction: () => _openSettings(context),
          );
      }
    }
    return const _Message(
      icon: Icons.cloud_off,
      title: 'Sin conexión con el backend.',
      body: 'Revisa la red y desliza para reintentar.',
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
            'Buscando tus rutas…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty and error states share one shape. It sits inside a scrollable so the
/// refresh gesture keeps working when there is no list to pull on.
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

class _RouteList extends StatelessWidget {
  const _RouteList({required this.state});

  final AssignedRoutesState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routes = state.routes.items;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // +1 for the ESP header.
      itemCount: routes.length + 1,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant,
      ),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _EspHeader(
            esp: state.routes.esp,
            total: routes.length,
            fromCache: state.fromCache,
          );
        }
        return _RouteTile(route: routes[i - 1]);
      },
    );
  }
}

class _EspHeader extends StatelessWidget {
  const _EspHeader({
    required this.esp,
    required this.total,
    required this.fromCache,
  });

  final String esp;
  final int total;
  final bool fromCache;

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
              esp,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            // Says plainly that the list is stale rather than implying it is
            // current.
            fromCache ? 'sin sincronizar (offline)' : '$total rutas',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends ConsumerStatefulWidget {
  const _RouteTile({required this.route});

  final RouteSummary route;

  @override
  ConsumerState<_RouteTile> createState() => _RouteTileState();
}

class _RouteTileState extends ConsumerState<_RouteTile> {
  bool _opening = false;

  /// Pulls the frame, merges it locally and moves on to capture. Offline it
  /// still opens, on whatever is already on the device (A4).
  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);

    final route = widget.route;
    final online = ref.read(isOnlineProvider);
    var message = 'Ruta abierta (sin reanudar: offline).';

    try {
      if (online) {
        final frame =
            await ref.read(syncServiceProvider).pullFrame(route.routeId);
        message = 'Ruta abierta. ${frame.items.length} capturas reanudadas.';
      }
      await ref.read(currentRouteIdProvider.notifier).setRoute(route.routeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CaptureScreen(routeId: route.routeId),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final detail = switch (e.statusCode) {
        401 => 'Token vencido o inválido — renuévalo en Ajustes.',
        403 => 'Ese token no es de campo.',
        404 => 'Esa ruta no existe o no es de tu ESP.',
        _ => e.message,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.route;

    return InkWell(
      onTap: _opening ? null : _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ruta ${route.codigo}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (route.nombre != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      route.nombre!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    route.estado,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (route.totalCapturado != null)
              _ProgressBadge(total: route.totalCapturado!),
            const SizedBox(width: 8),
            if (_opening)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
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

/// Progress badge. An untouched route (zero) stays muted so the eye lands on
/// the routes already under way.
class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = total > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: started
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$total capturadas',
        style: theme.textTheme.labelMedium?.copyWith(
          color: started
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
