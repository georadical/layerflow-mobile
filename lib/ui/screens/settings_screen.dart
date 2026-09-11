import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/jwt.dart';
import '../../data/api/api_client.dart';
import '../providers.dart';

/// Settings: backend URL and field_token (MVP: issued by the operator).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseUrlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _testRouteCtrl = TextEditingController();
  bool _loading = true;
  bool _obscureToken = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsStoreProvider);
    _baseUrlCtrl.text = await settings.getBaseUrl() ?? '';
    final token = await settings.getToken();
    _tokenCtrl.text = token ?? '';
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _testRouteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = ref.read(settingsStoreProvider);
    await settings.setBaseUrl(_baseUrlCtrl.text);
    await settings.setToken(_tokenCtrl.text);
    // Refresh the expiry warnings with the new token.
    ref.invalidate(fieldTokenInfoProvider);
    ref.invalidate(tokenStatusProvider);
    // Anything already fetched belongs to the previous credentials. Without
    // this, a worker who fixes a bad token still sees the stale 401 when they
    // walk back into the selector.
    ref.invalidate(assignedRoutesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ajustes guardados.')),
    );
    Navigator.of(context).pop();
  }

  /// Tests connectivity with a GET to the frame of a test route.
  /// Persists URL+token first (the ApiClient reads them from Settings).
  Future<void> _testConnection() async {
    final base = _baseUrlCtrl.text.trim();
    if (base.isEmpty) {
      _snack('Falta la URL del backend.');
      return;
    }
    final routeId = _testRouteCtrl.text.trim();
    if (routeId.isEmpty) {
      _snack('Ingresa un route_id de prueba.');
      return;
    }
    final settings = ref.read(settingsStoreProvider);
    await settings.setBaseUrl(base);
    await settings.setToken(_tokenCtrl.text);
    // Refresh the expiry/token warnings with what was just saved.
    ref.invalidate(fieldTokenInfoProvider);
    ref.invalidate(tokenStatusProvider);
    // "Probar conexión" also persists the credentials, so the selector must
    // forget whatever it fetched under the old ones.
    ref.invalidate(assignedRoutesProvider);

    setState(() => _testing = true);
    try {
      final frame = await ref.read(apiClientProvider).getRouteFrame(routeId);
      if (!mounted) return;
      _snack('✅ 200 — código ${frame.codigo ?? "?"}, '
          '${frame.items.length} capturas en la ruta.');
    } on ApiException catch (e) {
      if (!mounted) return;
      final hint = switch (e.statusCode) {
        401 => 'token ausente, inválido o expirado',
        404 => 'ruta de otra ESP o inexistente',
        400 => 'route_id inválido (¿es un UUID?)',
        _ => e.message,
      };
      _snack('❌ ${e.statusCode ?? ''} — $hint');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Shows the expiry read from the pasted JWT (signature not verified).
  Widget _expiryInfo() {
    final info = parseJwt(_tokenCtrl.text);
    if (_tokenCtrl.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    if (info.isMalformed) {
      return const Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red),
          SizedBox(width: 6),
          Expanded(child: Text('El token no tiene formato de JWT válido.')),
        ],
      );
    }
    if (info.expiresAt == null) {
      return const Text('Token sin fecha de expiración legible.',
          style: TextStyle(color: Colors.grey));
    }
    final fecha = DateFormat('yyyy-MM-dd HH:mm').format(info.expiresAt!);
    final Color color;
    final String texto;
    if (info.isExpired) {
      color = Colors.red;
      texto = 'Vencido el $fecha.';
    } else if (info.expiresSoon()) {
      color = Colors.orange;
      texto = 'Vence el $fecha (en ${info.daysLeft} días).';
    } else {
      color = Colors.green;
      texto = 'Válido hasta $fecha (${info.daysLeft} días).';
    }
    return Row(
      children: [
        Icon(Icons.schedule, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(texto, style: TextStyle(color: color))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _baseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL del backend',
                    hintText: 'http://192.168.1.10:8000',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'field_token (JWT)',
                    hintText: 'Bearer token emitido por el operador',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                  autocorrect: false,
                  maxLines: 1,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                _expiryInfo(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                ),
                const Divider(height: 40),
                const Text(
                  'Probar conexión',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _testRouteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'route_id de prueba',
                    hintText: 'UUID de una ruta de tu ESP',
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'Probando…' : 'Probar conexión'),
                ),
                const Divider(height: 40),
                OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Acerca de LayerFlow'),
                  onPressed: () => showAboutDialog(
                    context: context,
                    applicationName: 'LayerFlow — Captura',
                    applicationVersion: '0.1.0',
                    children: const [
                      Text(
                          'App de captura de placas (censo, coordinate-free).'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'El token se guarda en el almacenamiento seguro del sistema. '
                  'La URL no debe llevar barra final.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
    );
  }
}
