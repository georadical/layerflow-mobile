import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../screens/capture_screen.dart';

/// Spec 10 PC.5 — the reconciliation surface for a sweep the server rejected.
///
/// Because the sweep is optimistic-local, by the time the 409 lands the worker
/// has walked on to the next parada, so the capture screen for the rejected
/// parada is no longer showing — this names the parada, the reason (e.g.
/// barrido_fuera_de_orden / foto_obligatoria_pendiente), and offers to REOPEN
/// it (`swept:false`, the ungated correction path) so the worker can fix and
/// re-sweep. This is the ONE backend-driven reopen (Spec 16/BR5 — there is no
/// user-initiated reopen). Renders nothing when no sweep was rejected. Shared by
/// the parada list (the route home) and the demoted resume screen.
class SweepRejectedBanner extends ConsumerWidget {
  const SweepRejectedBanner({super.key, required this.routeId});

  final String routeId;

  Future<void> _reopen(
    BuildContext context,
    WidgetRef ref,
    String stopId,
  ) async {
    // Ungated correction path: reopen makes the parada current again (lowest
    // unswept), clears its rejection, and queues the swept:false for the next
    // Enviar. Then jump straight into it so the worker fixes it now.
    await ref.read(paradaRepositoryProvider).markSwept(stopId, swept: false);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CaptureScreen(routeId: routeId)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejected = ref.watch(sweepRejectionsProvider(routeId));
    if (rejected.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in rejected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.sync_problem,
                      size: 20, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parada ${p.faceSequence} no cerró en el servidor',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        Text(
                          p.sweepError ?? 'El servidor rechazó el barrido.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => _reopen(context, ref, p.stopId),
                    child: const Text('Reabrir'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
