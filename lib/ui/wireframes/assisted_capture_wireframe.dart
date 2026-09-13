import 'package:flutter/material.dart';

/// WIREFRAME — Spec 7, T7.2 "R1-assisted capture" (typeahead).
///
/// Layout only, dummy data, no wiring, no camera, no OCR. Every state the
/// shared spec (specs/r1-assisted-capture.md) demands is representable and
/// reviewable from the gallery before anything is built.
///
/// Spec anchors:
/// - CL-R1: the placa field is FREE TEXT — the observed truth, stored raw,
///   always editable. The panel beneath filters the R1 directory, with
///   "No está en la lista" as a FIXED FIRST ROW, same tap size as any
///   suggestion. Selecting NEVER overwrites the typed placa: the linked
///   state shows the pair (typed text + linked address) side by side.
/// - The worker never sees an NPN — only addresses. The NPN rides hidden.
/// - CL-R3 trigger 5: picking an address already used in this route warns
///   and marks divergence; the server accepts it (PH share NPNs).
/// - CL-R2: the OCR soft-check only ever surfaces on mismatch, as a
///   confirm prompt over the pair; silence otherwise.
/// - Photo status is a passive chip: capture is 100% and gestureless
///   (CL-R3), so the UI only reports rutina/divergencia, never asks.
enum AssistState {
  /// Typing; the panel filters, nothing chosen yet.
  typing,

  /// An R1 address was tapped: the pair is on screen, both halves visible.
  linked,

  /// "No está en la lista" was tapped: divergence, first-class outcome.
  notInList,

  /// The tapped address was already used in this route (trigger 5).
  duplicateWarning,

  /// On-device OCR disagrees with the typed placa (CL-R2).
  ocrMismatch,
}

/// Dummy R1 rows (mirrors GET /field/r1-directory items, minus npn which
/// the UI never shows).
const wireframeDummyDirectory = [
  'CALLE 5 # 2-06',
  'CALLE 5 # 2-10',
  'CALLE 5 # 2-14',
  'CARRERA 2 # 4A-09',
  'CARRERA 2 # 5-33',
];

class AssistedCaptureWireframe extends StatelessWidget {
  const AssistedCaptureWireframe({super.key, required this.state});

  final AssistState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const typed = 'C 5 2 0'; // what the worker has typed so far (raw)

    return Scaffold(
      appBar: AppBar(title: const Text('Captura')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Anchor card, as in the real capture screen (unchanged).
          Card(
            color: theme.colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Última capturada · posición 6 · total 6'),
                  SizedBox(height: 4),
                  Text('K 2 1-40',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Chip(
                avatar: Icon(Icons.tag, size: 18),
                label: Text('Siguiente posición: 7'),
              ),
              const SizedBox(width: 8),
              // Photo status: passive, no gesture (CL-R3, capture is 100%).
              Chip(
                avatar: Icon(
                  Icons.photo_camera,
                  size: 18,
                  color: _isDivergence
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label:
                    Text(_isDivergence ? 'foto: divergencia' : 'foto: rutina'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // CL-R1: free text, the observed truth, always editable.
          TextField(
            controller: TextEditingController(text: typed),
            decoration: const InputDecoration(
              labelText: 'Placa (dirección en la puerta)',
              helperText: 'Escribe lo que VES. Se guarda tal cual, siempre.',
            ),
          ),
          const SizedBox(height: 8),

          if (state == AssistState.ocrMismatch) ...[
            const _OcrMismatchBanner(typed: typed),
            const SizedBox(height: 8),
          ],

          if (state == AssistState.linked)
            const _LinkedPair(typed: typed)
          else if (state == AssistState.notInList)
            _NotInListMark()
          else ...[
            if (state == AssistState.duplicateWarning) ...[
              _DuplicateBanner(),
              const SizedBox(height: 8),
            ],
            const _SuggestionPanel(typed: typed),
          ],

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {},
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.check),
            label: const Text('Guardar y siguiente'),
          ),
        ],
      ),
    );
  }

  bool get _isDivergence =>
      state == AssistState.notInList || state == AssistState.duplicateWarning;
}

/// The panel that filters the R1 directory as the worker types (CL-R1).
/// "No está en la lista" is a FIXED FIRST ROW with the same tap size as any
/// suggestion — never a small link, never at the bottom.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.typed});

  final String typed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: Text(
              'No está en la lista',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text('Lo que ves manda. Queda como hallazgo.'),
            onTap: () {},
          ),
          const Divider(height: 1),
          for (final dir in wireframeDummyDirectory)
            ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(dir),
              subtitle: const Text('R1 · manzana …012'),
              onTap: () {},
            ),
        ],
      ),
    );
  }
}

/// The pair, both halves visible (CL-R1 hard rule: selecting never
/// overwrites the typed placa).
class _LinkedPair extends StatelessWidget {
  const _LinkedPair({required this.typed});

  final String typed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: const Text('Enlazada a: CALLE 5 # 2-06'),
        subtitle: Text('Tú escribiste: "$typed" — se guardan las dos.'),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Quitar enlace',
          onPressed: () {},
        ),
      ),
    );
  }
}

/// First-class outcome, not an error state (doctrine).
class _NotInListMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.flag, color: theme.colorScheme.onErrorContainer),
        title: Text('No está en la lista',
            style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        subtitle: Text(
          'Se captura tal cual y queda como hallazgo del censo, '
          'con foto de evidencia.',
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.onErrorContainer),
          tooltip: 'Deshacer',
          onPressed: () {},
        ),
      ),
    );
  }
}

/// CL-R3 trigger 5: the address was already used in this route. Warns and
/// marks divergence; it does NOT block (PH legitimately share).
class _DuplicateBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.copy_all, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Esa dirección ya se usó en esta ruta (posición 3). Puedes '
                'continuar — varias unidades pueden compartirla (PH) — y '
                'esta quedará marcada como divergencia con foto.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CL-R2: only ever appears on mismatch; asks, never decides.
class _OcrMismatchBanner extends StatelessWidget {
  const _OcrMismatchBanner({required this.typed});

  final String typed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La cámara leyó "C 5 2-08" y tú escribiste "$typed". '
              '¿Confirmas lo escrito?',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(onPressed: () {}, child: const Text('Corregir')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: () {}, child: const Text('Confirmo lo escrito')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
