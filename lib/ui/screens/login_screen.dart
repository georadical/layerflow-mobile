import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dtos.dart';
import '../providers.dart';
import 'settings_screen.dart';

/// Field login (Spec 5, T5.2). Structure and copy match the approved
/// wireframe; the RootGate swaps screens on session changes, so this screen
/// navigates nowhere on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
      // Success: the RootGate takes it from here (choice or selector).
    } on ApiException catch (e) {
      setState(() {
        _error = switch (e.statusCode) {
          // A1 — deliberately indistinct: never says which half was wrong.
          401 => 'Correo o contraseña incorrectos.',
          // A2 — a provisioning gap; name the way out.
          403 => 'Tu cuenta no tiene acceso de campo activo. Pide al '
              'operador que te enlace como encuestador.',
          _ => 'No se pudo entrar: ${e.message}',
        };
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(isOnlineProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'LayerFlow Captura',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entra con tu correo y contraseña',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!online) ...[
                    const _Banner(
                      icon: Icons.cloud_off,
                      text: 'Sin conexión. Para entrar necesitas señal; '
                          'lo ya capturado en este teléfono no se pierde.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    _Banner(icon: Icons.error_outline, text: _error!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailCtrl,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      hintText: 'ana@ejemplo.com',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordCtrl,
                    enabled: !_sending,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      // No "forgot password" flow: the operator resets (the
                      // shared spec ships no email infrastructure).
                      helperText:
                          '¿La olvidaste? El operador puede restablecerla.',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => online ? _login() : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _sending || !online ? null : _login,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 24),
                  // CL1: the paste path exists but reads as the exception.
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Text(
                      'Tengo un token del operador (vía excepcional)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// CL5 — several ESPs came back: choose the active one, nothing else.
/// Switching later is Spec 6; this screen offers no management.
class EspChoiceScreen extends ConsumerWidget {
  const EspChoiceScreen({super.key, required this.session});

  final FieldSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Elige tu ESP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hola, ${session.workerNombre}. Trabajas en varias ESPs: '
            '¿con cuál empiezas hoy?',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Podrás cambiar de ESP más adelante.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final esp in session.esps)
            Card(
              child: ListTile(
                title: Text(esp.espNombre),
                subtitle: esp.rutasAsignadas == null
                    ? null
                    : Text('${esp.rutasAsignadas} rutas asignadas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    ref.read(sessionProvider.notifier).chooseEsp(esp.tenantId),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
