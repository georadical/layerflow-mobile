import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../screens/settings_screen.dart';

/// Banner warning that the field_token is missing, expired or about to expire.
/// Shows nothing when the token is OK.
class TokenWarningBanner extends ConsumerWidget {
  const TokenWarningBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(tokenStatusProvider);
    return status.maybeWhen(
      data: (s) {
        final msg = _message(s);
        if (msg == null) return const SizedBox.shrink();
        final isError = s == TokenStatus.expired ||
            s == TokenStatus.missing ||
            s == TokenStatus.malformed;
        final color = isError ? Colors.red : Colors.orange;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(msg)),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: const Text('Ajustes'),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  String? _message(TokenStatus s) {
    switch (s) {
      case TokenStatus.missing:
        return 'Falta el field_token. Configúralo en Ajustes.';
      case TokenStatus.malformed:
        return 'El field_token no tiene formato válido. Revísalo en Ajustes.';
      case TokenStatus.expired:
        return 'El field_token venció. Pide uno nuevo al operador.';
      case TokenStatus.expiringSoon:
        return 'El field_token vence pronto. Renuévalo antes de salir a campo.';
      case TokenStatus.ok:
        return null;
    }
  }
}
