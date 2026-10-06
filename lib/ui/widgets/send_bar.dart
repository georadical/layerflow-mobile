import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/api/api_client.dart';
import '../providers.dart';

/// The route's send bar (Spec 3/4) — the single way to push the queue (BR2).
///
/// Shows what is waiting (captures / photos / surveys / sweeps), the last
/// attempt and its outcome, and the Enviar action; disabled (not hidden)
/// offline. Renders nothing when there is nothing to send. Shared by the parada
/// list (the route home, Spec 16/D1) and the demoted resume screen.
class SendBar extends ConsumerWidget {
  const SendBar({super.key, required this.routeId});

  final String routeId;

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(pushProvider(routeId).notifier).send();
      if (!context.mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Envío completo.')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // The queue is untouched by any of these: a credentials or network
      // problem must never cost captured work (BR6).
      final detail = e.codigo == AppConfig.codeRutaPlacasCerrada
          // Spec 9: the route closed for placas between opening it and sending.
          // Nothing was written server-side; the queue stays as it was.
          ? 'La oficina cerró la captura de placas en esta ruta; nada se envió.'
          : switch (e.statusCode) {
              401 => 'Token vencido o inválido — renuévalo en Ajustes.',
              403 =>
                'Ese token no es de campo — pide un field_token al operador.',
              404 => 'Esa ruta no existe o no es de tu ESP.',
              _ => 'No se pudo enviar: ${e.message}',
            };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail)));
    }
  }

  /// "hace X" from the device clock; best-effort, needs no server time.
  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  static const _outcomeLabels = <String, String>{
    AppConfig.pushOk: 'todo enviado',
    AppConfig.pushPartial: 'algunas rechazadas',
    AppConfig.pushNetwork: 'sin señal',
    AppConfig.pushAuth: 'token rechazado',
    AppConfig.pushHttp: 'error del servidor',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final waiting = ref.watch(pendingCountProvider(routeId));
    final photos =
        ref.watch(pendingEvidenceCountProvider(routeId)).valueOrNull ?? 0;
    final surveys =
        ref.watch(pendingSurveyCountProvider(routeId)).valueOrNull ?? 0;
    // Spec 10 PC.5: a face closed offline queues a sweep to push; count it, or
    // a sweep with everything else synced would have no "Enviar" to ride.
    final sweeps = ref.watch(pendingSweepCountProvider(routeId));
    if (waiting == 0 && photos == 0 && surveys == 0 && sweeps == 0) {
      return const SizedBox.shrink();
    }
    final sending = ref.watch(pushProvider(routeId));
    final online = ref.watch(isOnlineProvider);
    final onWifi = ref.watch(isOnWifiProvider);
    final route = ref.watch(routeRowProvider(routeId)).valueOrNull;
    final lastAt = route?.lastPushAt;
    final lastOutcome = route?.lastPushOutcome;

    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_upload_outlined : Icons.cloud_off,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (waiting > 0) '$waiting sin enviar',
                    // Photos and surveys are named apart: with the capture
                    // queue empty, one of these may be the only reason the
                    // bar is here.
                    if (photos > 0) '$photos ${photos == 1 ? 'foto' : 'fotos'}',
                    if (surveys > 0)
                      '$surveys ${surveys == 1 ? 'encuesta' : 'encuestas'}',
                    if (sweeps > 0)
                      '$sweeps ${sweeps == 1 ? 'parada por cerrar' : 'paradas por cerrar'}',
                    if (!online) 'sin conexión',
                  ].join(' · '),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                // CL-R5: routine photos only travel under WiFi. Say so,
                // rather than letting the worker press Enviar and wonder
                // why the count did not move.
                if (waiting == 0 && photos > 0 && online && !onWifi)
                  Text(
                    'Las fotos de rutina esperan WiFi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                // "Tried, and when": tells never-tried from tried-and-failed
                // even if the momentary message was missed (Spec 4, BR7).
                if (lastAt != null)
                  Text(
                    'Último intento ${_ago(lastAt)}'
                    '${_outcomeLabels[lastOutcome] != null ? ' · ${_outcomeLabels[lastOutcome]}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          if (sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            // Disabled offline rather than hidden: the action should be
            // visibly unavailable, not missing.
            FilledButton(
              onPressed: online ? () => _send(context, ref) : null,
              child: const Text('Enviar'),
            ),
        ],
      ),
    );
  }
}
