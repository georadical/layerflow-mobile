import 'package:flutter/material.dart';

/// The R1 link card ("Enlazada a…") under the placa field (Spec 7): the pair,
/// both halves visible (CL-R1 hard rule: selecting never overwrites the typed
/// placa). The NPN itself is never shown. Carries the Spec 18 toggle
/// "Solo enlazar — no hay placa a la vista".
///
/// It only exists while the capture is linked — after an R1 pick or after
/// "Coincide" — so the toggle can never be pressed without a link (BR2).
/// Off: an outlined invitation. On: a filled, checked state that reads as a toggle;
/// tapping it again turns the mode off (BR5).
class LinkedCard extends StatelessWidget {
  const LinkedCard({
    super.key,
    required this.direccion,
    required this.typed,
    required this.onUnlink,
    required this.sinPlaca,
    required this.onToggleSinPlaca,
    this.offSubtitle,
  });

  /// The linked R1 address.
  final String direccion;

  /// What the worker typed (the observed placa) — shown only while the mode is off.
  final String typed;

  final VoidCallback onUnlink;

  /// Spec 18: the capture is linked with NO placa read on the door.
  final bool sinPlaca;
  final VoidCallback onToggleSinPlaca;

  /// Replaces the "Tú escribiste…" line while the mode is off (editar unidad
  /// keeps its own note about unlinking being a field decision).
  final String? offSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text('Enlazada a: $direccion'),
              subtitle: Text(sinPlaca
                  ? 'Sin placa a la vista — se verifica en oficina.'
                  : offSubtitle ??
                      'Tú escribiste: "$typed" — se guardan las dos.'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quitar enlace',
                onPressed: onUnlink,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: sinPlaca
                  // Solid, not tonal: a tonal button is the card's own
                  // secondaryContainer and vanished into it (SE.7 emulator).
                  ? FilledButton.icon(
                      onPressed: onToggleSinPlaca,
                      icon: const Icon(Icons.check),
                      label: const Text(
                          'Sin placa a la vista · toca para escribir la placa'),
                    )
                  : OutlinedButton.icon(
                      onPressed: onToggleSinPlaca,
                      icon: const Icon(Icons.visibility_off),
                      label:
                          const Text('Solo enlazar — no hay placa a la vista'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
