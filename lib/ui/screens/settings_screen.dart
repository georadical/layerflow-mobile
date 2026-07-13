import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/jwt.dart';
import '../providers.dart';

/// Ajustes: URL del backend y field_token (MVP: emitido por operador).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseUrlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = true;
  bool _obscureToken = true;

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
    super.dispose();
  }

  Future<void> _save() async {
    final settings = ref.read(settingsStoreProvider);
    await settings.setBaseUrl(_baseUrlCtrl.text);
    await settings.setToken(_tokenCtrl.text);
    // Refrescar los avisos de expiración con el token nuevo.
    ref.invalidate(fieldTokenInfoProvider);
    ref.invalidate(tokenStatusProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ajustes guardados.')),
    );
    Navigator.of(context).pop();
  }

  /// Muestra la expiración leída del JWT pegado (sin verificar la firma).
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
