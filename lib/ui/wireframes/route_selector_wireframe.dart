import 'package:flutter/material.dart';

/// WIREFRAME — Spec 1, T1.1 "Route selector" (read-only entry point).
///
/// Layout only: plain widgets, dummy data, no styling of its own. It validates
/// element placement and the state matrix, not looks. Styling is T1.2.
///
/// Spec anchors (specs/open-and-resume-route.md):
/// - The wire returns routes assigned to THIS worker, already ordered by
///   `codigo` and already filtered to state `verificada`. The app renders what
///   it is given; it never filters or reorders (BR1).
/// - BR2 the state vocabulary is `borrador | verificada`. Never "congelada".
/// - `items: []` is a legitimate empty state, not an error (A1).
/// - A3 pull-to-refresh re-issues the request, and stays available on the
///   empty state too — otherwise a worker who just got assigned a route would
///   be stuck on a dead screen.
/// - 401 and 403 are different problems and get different copy (B, C).

/// Dummy row for the wireframe. Mirrors one item of `GET /field/routes`.
class WireframeRoute {
  const WireframeRoute({
    required this.routeId,
    required this.codigo,
    required this.estado,
    this.nombre,
    this.totalCapturado,
  });

  final String routeId;
  final String codigo;
  final String estado;
  final String? nombre;
  final int? totalCapturado;
}

/// Every UI state the spec requires this screen to handle.
enum SelectorState {
  loading,
  list,
  empty,
  networkError,
  unauthorized,
  forbidden
}

class RouteSelectorWireframe extends StatelessWidget {
  const RouteSelectorWireframe({
    super.key,
    required this.state,
    this.esp = 'ESP Isnos (muestra)',
    this.routes = const [],
  });

  final SelectorState state;
  final String esp;
  final List<WireframeRoute> routes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () {},
          ),
        ],
      ),
      // The refresh gesture wraps every state, so a worker can always retry
      // by pulling — including from the empty and error screens.
      body: RefreshIndicator(
        onRefresh: () async {},
        child: switch (state) {
          SelectorState.loading => const _Loading(),
          SelectorState.list => _RouteList(esp: esp, routes: routes),
          SelectorState.empty => const _Message(
              icon: Icons.inbox,
              title: 'No tienes rutas asignadas en tu ESP.',
              body: 'Si te acaban de asignar una, desliza para actualizar.',
            ),
          SelectorState.networkError => const _Message(
              icon: Icons.cloud_off,
              title: 'Sin conexión con el backend.',
              body: 'Revisa la red y vuelve a intentarlo.',
              action: 'Reintentar',
            ),
          SelectorState.unauthorized => const _Message(
              icon: Icons.lock_outline,
              title: 'Token vencido o inválido.',
              body: 'Renuévalo en Ajustes.',
              action: 'Ajustes',
            ),
          SelectorState.forbidden => const _Message(
              icon: Icons.block,
              title: 'Ese token no es de campo.',
              body: 'Pide un field_token al operador.',
              action: 'Ajustes',
            ),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Buscando tus rutas…'),
        ],
      ),
    );
  }
}

/// Empty and error states share one shape: icon, title, explanation, optional
/// action. It lives inside a scrollable so the refresh gesture still works.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;

  @override
  Widget build(BuildContext context) {
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
                  Icon(icon, size: 40),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(body, textAlign: TextAlign.center),
                  if (action != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: () {}, child: Text(action!)),
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
  const _RouteList({required this.esp, required this.routes});

  final String esp;
  final List<WireframeRoute> routes;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // +1 for the ESP header: the worker should be able to tell at a glance
      // which tenant the pasted token belongs to.
      itemCount: routes.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) return _EspHeader(esp: esp, total: routes.length);
        return _RouteTile(route: routes[i - 1]);
      },
    );
  }
}

class _EspHeader extends StatelessWidget {
  const _EspHeader({required this.esp, required this.total});

  final String esp;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(esp)),
          Text('$total rutas'),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route});

  final WireframeRoute route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The code is what the worker actually says out loud.
                  Text('Ruta ${route.codigo}',
                      style: const TextStyle(fontSize: 20)),
                  // `nombre` is nullable: when absent the code stands alone,
                  // with no placeholder and no empty parentheses.
                  if (route.nombre != null) ...[
                    const SizedBox(height: 2),
                    Text(route.nombre!),
                  ],
                  const SizedBox(height: 4),
                  Text(route.estado, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            // A missing count hides the badge; a zero count still shows, so
            // "assigned but untouched" reads differently from "no data".
            if (route.totalCapturado != null)
              Text('${route.totalCapturado} capturadas'),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Dummy list: a null `nombre`, a zero badge and a longer route.
const wireframeDummyRoutes = <WireframeRoute>[
  WireframeRoute(
    routeId: '405ca862-e116-4a12-a920-a520c0d063ee',
    codigo: '10',
    estado: 'verificada',
    totalCapturado: 2,
  ),
  WireframeRoute(
    routeId: '7b1e0f22-0000-4a12-a920-a520c0d06400',
    codigo: '40',
    nombre: 'Vía al centro',
    estado: 'verificada',
    totalCapturado: 0,
  ),
  WireframeRoute(
    routeId: '9c2f1133-0000-4a12-a920-a520c0d06500',
    codigo: '50',
    estado: 'verificada',
    totalCapturado: 17,
  ),
];
