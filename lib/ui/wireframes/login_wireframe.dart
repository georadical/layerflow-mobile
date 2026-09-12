import 'package:flutter/material.dart';

/// WIREFRAME — Spec 5, T5.2 "Field login".
///
/// Layout only, dummy data, no wiring. Every state the shared spec
/// (specs/field-login.md) demands from this screen is representable and
/// reviewable from the gallery before anything is connected.
///
/// Spec anchors:
/// - A1: bad credentials → 401 with ONE indistinct message. The copy must not
///   reveal whether the email exists.
/// - A2: valid credentials, no active linked field_worker → 403 "sin acceso
///   de campo". Different problem, different copy: these workers exist but
///   the operator has not linked them yet.
/// - CL1: manual token paste survives as an EMERGENCY fallback and must look
///   exceptional — a quiet text link, never a peer of the login button.
/// - CL5: when login returns several ESPs, the worker picks ONE as active
///   here and now. Switching later is Spec 6, so this screen offers no
///   "manage" affordances — just the choice.
/// - CL3: nothing on this screen ever displays a token.
/// - Login needs the network (unlike capture): offline gets its own state
///   instead of a dead button with no explanation.
enum LoginState {
  /// Email + password, ready.
  form,

  /// Request in flight.
  sending,

  /// A1 — 401, indistinct copy.
  badCredentials,

  /// A2 — 403, credentials fine but no active field access.
  noFieldAccess,

  /// No connectivity: login cannot work, capture is unaffected.
  offline,

  /// CL5 — several ESPs came back; pick the active one.
  espChoice,
}

/// Dummy ESP entry, mirroring one item of the login response's `esps` list
/// (minus the token, which the UI never shows — CL3).
class WireframeEsp {
  const WireframeEsp({required this.nombre, required this.rutas});

  final String nombre;

  /// `rutas_asignadas` from the login response (backend f371076): distinct
  /// routes in state 'verificada' assigned to that field_worker as titular
  /// or pareja — the same criterion that filters GET /field/routes, so this
  /// number always matches the list the worker sees after choosing.
  final int rutas;
}

const wireframeDummyEsps = [
  WireframeEsp(nombre: 'ESP Isnos (muestra)', rutas: 1),
  WireframeEsp(nombre: 'ESP Pitalito', rutas: 3),
];

class LoginWireframe extends StatelessWidget {
  const LoginWireframe({
    super.key,
    required this.state,
    this.esps = wireframeDummyEsps,
    this.workerNombre = 'Ana',
  });

  final LoginState state;
  final List<WireframeEsp> esps;
  final String workerNombre;

  @override
  Widget build(BuildContext context) {
    if (state == LoginState.espChoice) {
      return _EspChoice(esps: esps, workerNombre: workerNombre);
    }
    return _LoginForm(state: state);
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.state});

  final LoginState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sending = state == LoginState.sending;
    final offline = state == LoginState.offline;

    final error = switch (state) {
      // A1 — deliberately indistinct: never says which half was wrong.
      LoginState.badCredentials => 'Correo o contraseña incorrectos.',
      // A2 — a provisioning gap, not the worker's fault; name the way out.
      LoginState.noFieldAccess =>
        'Tu cuenta no tiene acceso de campo activo. Pide al operador que '
            'te enlace como encuestador.',
      _ => null,
    };

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
                  if (offline) ...[
                    const _Banner(
                      icon: Icons.cloud_off,
                      text: 'Sin conexión. Para entrar necesitas señal; '
                          'lo ya capturado en este teléfono no se pierde.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (error != null) ...[
                    _Banner(icon: Icons.error_outline, text: error),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    enabled: !sending,
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
                    enabled: !sending,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      // No "forgot password" link: recovery is operator-run
                      // in the MVP (spec: no email infrastructure).
                      helperText:
                          '¿La olvidaste? El operador puede restablecerla.',
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: sending || offline ? null : () {},
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 24),
                  // CL1: the paste path exists but reads as the exception —
                  // a quiet link, physically apart from the primary action.
                  TextButton(
                    onPressed: () {},
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

/// CL5 — the response brought several ESPs: choose the active one, nothing
/// else. One tap continues; there is no multi-select and no "manage".
class _EspChoice extends StatelessWidget {
  const _EspChoice({required this.esps, required this.workerNombre});

  final List<WireframeEsp> esps;
  final String workerNombre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Elige tu ESP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hola, $workerNombre. Trabajas en varias ESPs: '
            '¿con cuál empiezas hoy?',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Podrás cambiar de ESP más adelante.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final esp in esps)
            Card(
              child: ListTile(
                title: Text(esp.nombre),
                subtitle: Text('${esp.rutas} rutas asignadas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
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
