import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dtos.dart';
import '../providers.dart';
import '../widgets/token_warning_banner.dart';
import 'resume_route_screen.dart';
import 'settings_screen.dart';

/// CL4 — logout wipes tokens, never the queue. With unsent rows it warns
/// and, on confirmation, parks them bound to this person: they are invisible
/// to any other login and travel only when the same person returns.
Future<void> _logout(BuildContext context, WidgetRef ref) async {
  final owner = ref.read(queueOwnerProvider);
  final pending =
      await ref.read(captureRepositoryProvider).pendingCountForOwner(owner);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cerrar sesión'),
      content: Text(pending == 0
          ? 'Se borrarán tus accesos de este teléfono. '
              'Lo capturado ya enviado está a salvo en el servidor.'
          : 'Tienes $pending capturas sin enviar. Se quedan guardadas en '
              'este teléfono y viajan cuando vuelvas a entrar tú; nadie '
              'más puede verlas ni enviarlas.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(sessionProvider.notifier).logout();
  // The RootGate swaps to the login screen on its own.
}

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
    final hasSession = ref.watch(sessionProvider).valueOrNull != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => _openSettings(context),
          ),
          // Only a logged-in session can log out; the paste flow (CL1) has
          // nothing to close.
          if (hasSession)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
              onPressed: () => _logout(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          // This is the first screen of the day, so an expiring token has to
          // surface here: every request below it will fail without one.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TokenWarningBanner(),
          ),
          // The refresh gesture wraps every state: a worker who was just
          // assigned a route, or who just regained signal, can always retry.
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(assignedRoutesProvider.notifier).refresh(),
              child: async.when(
                loading: () => const _Loading(),
                error: (e, _) => _errorView(context, ref, e),
                data: (data) => data.routes.items.isEmpty
                    ? const _Message(
                        icon: Icons.inbox,
                        title: 'No tienes rutas asignadas en tu ESP.',
                        body:
                            'Si te acaban de asignar una, desliza para actualizar.',
                      )
                    : _RouteList(state: data),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Maps the failure to the copy that tells the worker what to actually
  /// do. With a session the way out is logging in again (BR-FRESH re-issues
  /// everything; the queue stays parked, CL4) — Ajustes only helps the
  /// paste flow.
  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final hasSession = ref.read(sessionProvider).valueOrNull != null;
    Future<void> relogin() =>
        ref.read(sessionProvider.notifier).logout(); // gate → login

    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
          return hasSession
              ? _Message(
                  icon: Icons.lock_outline,
                  title: 'Tu acceso venció.',
                  body: 'Entra de nuevo con tu correo y contraseña. '
                      'Lo capturado en este teléfono no se pierde.',
                  action: 'Entrar de nuevo',
                  onAction: relogin,
                )
              : _Message(
                  icon: Icons.lock_outline,
                  title: 'Token vencido o inválido.',
                  body: 'Renuévalo en Ajustes.',
                  action: 'Ajustes',
                  onAction: () => _openSettings(context),
                );
        case 403:
          // With a session this is revocation in THIS ESP; re-login returns
          // only the ESPs still active. Without one, it is a token of the
          // wrong kind: re-pasting the same one will not help.
          return hasSession
              ? _Message(
                  icon: Icons.block,
                  title: 'Tu acceso a esta ESP fue desactivado.',
                  body: 'Entra de nuevo para ver tus ESPs activas, o '
                      'consulta al operador.',
                  action: 'Entrar de nuevo',
                  onAction: relogin,
                )
              : _Message(
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

class _EspHeader extends ConsumerWidget {
  const _EspHeader({
    required this.esp,
    required this.total,
    required this.fromCache,
  });

  final String esp;
  final int total;
  final bool fromCache;

  /// Spec 6 (T6.2): the same choice UI as login, as a sheet. Picking calls
  /// `chooseEsp`, which swaps the mirrored token, clears the active route
  /// (BR5) and refetches the list — all local, works offline (BR2).
  Future<void> _switchEsp(
      BuildContext context, WidgetRef ref, FieldSession session) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('¿Con cuál ESP sigues?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in session.esps)
              ListTile(
                leading: Icon(e.tenantId == session.activeTenantId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(e.espNombre),
                subtitle: e.rutasAsignadas == null
                    ? null
                    : Text('${e.rutasAsignadas} rutas asignadas'),
                onTap: () => Navigator.of(context).pop(e.tenantId),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == session.activeTenantId) return;
    await ref.read(sessionProvider.notifier).chooseEsp(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).valueOrNull;
    // BR6: with one ESP (or the paste flow) there is nothing to switch and
    // nothing changes visually — zero friction for the exclusive case.
    final switchable = session != null && session.esps.length > 1;

    return InkWell(
      onTap: switchable ? () => _switchEsp(context, ref, session) : null,
      child: Container(
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
              // Says plainly that the list is stale rather than implying it
              // is current.
              fromCache ? 'sin sincronizar (offline)' : '$total rutas',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (switchable) ...[
              const SizedBox(width: 8),
              Icon(Icons.swap_horiz,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 2),
              Text('cambiar',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteTile extends ConsumerWidget {
  const _RouteTile({required this.route});

  final RouteSummary route;

  /// Marks the route active and hands over. Pulling the frame belongs to the
  /// resume view, which owns the loading and error states for it.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await ref.read(currentRouteIdProvider.notifier).setRoute(route.routeId);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResumeRouteScreen(
          routeId: route.routeId,
          codigo: route.codigo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _open(context, ref),
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
