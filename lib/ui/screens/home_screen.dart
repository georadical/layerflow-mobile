import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/token_warning_banner.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';

/// Punto de entrada: abrir/reanudar una ruta.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _routeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Prellenar con la última ruta activa, si existe.
    Future.microtask(() {
      final current = ref.read(currentRouteIdProvider);
      if (current != null) _routeCtrl.text = current;
    });
  }

  @override
  void dispose() {
    _routeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openRoute() async {
    final routeId = _routeCtrl.text.trim();
    if (routeId.isEmpty) {
      _snack('Ingresa el route_id.');
      return;
    }

    setState(() => _busy = true);
    final online = ref.read(isOnlineProvider);
    var resumedMsg = 'Ruta abierta (sin reanudar: offline).';

    try {
      if (online) {
        // Reanudar: traer el frame y restaurar lo capturado.
        final frame = await ref.read(syncServiceProvider).pullFrame(routeId);
        resumedMsg = 'Ruta abierta. ${frame.items.length} capturas reanudadas.';
      }
      await ref.read(currentRouteIdProvider.notifier).setRoute(routeId);
      if (!mounted) return;
      _snack(resumedMsg);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CaptureScreen(routeId: routeId)),
      );
    } catch (e) {
      _snack('No se pudo reanudar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final current = ref.watch(currentRouteIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LayerFlow — Captura'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConnectivityBanner(online: online),
            const SizedBox(height: 16),
            const TokenWarningBanner(),
            const Text(
              'Abrir ruta',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ingresa el route_id (UUID) de la ruta congelada. Con conexión, '
              'se reanuda lo ya capturado.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _routeCtrl,
              decoration: const InputDecoration(
                labelText: 'route_id',
                hintText: 'p. ej. 3f2a…-uuid',
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _openRoute,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(online ? 'Abrir y reanudar' : 'Abrir (offline)'),
            ),
            if (current != null) ...[
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Continuar ruta activa'),
                  subtitle: Text(current),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CaptureScreen(routeId: current),
                            ),
                          ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.wifi : Icons.wifi_off, color: color, size: 20),
          const SizedBox(width: 8),
          Text(online ? 'En línea' : 'Sin conexión (offline)'),
        ],
      ),
    );
  }
}
