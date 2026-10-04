import 'package:flutter/material.dart';

/// WIREFRAME — Spec 13, AM.2 "Anchor by manzana".
///
/// Layout only, dummy data, no wiring (specs/ancla-por-manzana.md). Reviews the
/// shape of the assisted anchor on a parada that has a **manzana but no terna** —
/// the Pitalito pilot case — before touching the real gates.
///
/// The shape this wireframe argues for:
/// - **Assisted by manzana, not terna.** A parada with a manzana shows the
///   full-placa field "Placa (dirección en la puerta)" and, as the worker types,
///   a dropdown of R1 rows **restricted to that manzana** + "No está en la lista".
/// - **The anchor seeds prediction.** Once an R1 row is linked, the next placa
///   shows "Siguiente esperada" (Coincide / No coincide) — no terna required.
/// - **Rural = no manzana.** A parada with no manzana keeps free-text
///   "Nombre del predio", no dropdown, no prediction (topónimo verbatim).
enum AnclaState {
  /// Manzana parada, no text yet — full-placa field, no panel, no prediction.
  anchorEmpty,

  /// Typing the anchor → manzana-scoped dropdown + "No está en la lista".
  anchorTyping,

  /// An R1 row was tapped → linked card (NPN hidden; typed text kept).
  anchorLinked,

  /// After the anchor → "Siguiente esperada" prediction card.
  predicted,

  /// Parada with NO manzana → free text, no dropdown, no prediction.
  ruralNoManzana,
}

class AnclaManzanaWireframe extends StatelessWidget {
  const AnclaManzanaWireframe({super.key, required this.state});

  final AnclaState state;

  bool get _rural => state == AnclaState.ruralNoManzana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_rural ? 'Parada 1' : 'Parada 1 · Mz 5',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LastCaptureCard(predicted: state == AnclaState.predicted),
          const SizedBox(height: 16),
          _faceCard(theme),
          const SizedBox(height: 16),
          // Prediction sits ABOVE the field (mirrors the real screen order).
          if (state == AnclaState.predicted) ...[
            const _ExpectedCard(),
            const SizedBox(height: 16),
          ],
          _placaField(),
          // Panel / linked card sit BELOW the field.
          if (state == AnclaState.anchorTyping) ...[
            const SizedBox(height: 8),
            const _SuggestionPanel(),
          ] else if (state == AnclaState.anchorLinked) ...[
            const SizedBox(height: 8),
            const _LinkedCard(),
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

  Widget _faceCard(ThemeData theme) {
    if (_rural) {
      return Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: const Icon(Icons.cottage_outlined),
          title: const Text('Parada 1 · predio rural'),
          subtitle: Text('Sin manzana catastral — escribe el nombre del predio.',
              style: theme.textTheme.bodySmall),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: const Icon(Icons.grid_4x4),
        title: const Text('Zona: Urbana · Mz 5 · parada 1'),
        subtitle: Text('La manzana la fija la parada — no se escribe.',
            style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _placaField() {
    // Dummy "typed" text per state — a wireframe fixes the field content.
    final typed = switch (state) {
      AnclaState.anchorTyping => 'CALLE 14 # 2',
      AnclaState.anchorLinked => 'CALLE 14 # 2-104',
      _ => '',
    };
    return TextFormField(
      key: ValueKey(state), // re-seed initialValue when the state switches
      initialValue: typed,
      decoration: InputDecoration(
        labelText: _rural ? 'Nombre del predio' : 'Placa (dirección en la puerta)',
        hintText: _rural ? 'FINCA CANAÁN' : 'CALLE 14 # 2-104',
        helperText: _rural
            ? 'Se guarda tal cual, siempre.'
            : 'Escribe lo que VES. Se guarda tal cual, siempre.',
      ),
    );
  }
}

/// The anchor context card at the top: empty before the first predio, or the
/// last captured predio once the anchor exists (drives prediction).
class _LastCaptureCard extends StatelessWidget {
  const _LastCaptureCard({required this.predicted});

  final bool predicted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!predicted) {
      return Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aún no hay capturas en esta ruta. '
              'El primer predio será el 1.'),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Última capturada · predio 1 · total 1',
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text('CALLE 14 # 2-104',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// The manzana-scoped dropdown as the worker types (mirrors the real
/// _SuggestionPanel): "No está en la lista" is a fixed first row.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const hits = <String>[
      'CALLE 14 # 2-104',
      'CALLE 14 # 2-112',
      'CALLE 14 # 2-118',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: Text('No está en la lista',
                style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold)),
            subtitle: const Text('Lo que ves manda. Queda como hallazgo.'),
            onTap: () {},
          ),
          const Divider(height: 1),
          for (final h in hits)
            ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(h),
              subtitle: const Text('R1 · manzana …005'),
              onTap: () {},
            ),
        ],
      ),
    );
  }
}

/// The pair, both halves visible — selecting never overwrites the typed placa;
/// the NPN rides hidden.
class _LinkedCard extends StatelessWidget {
  const _LinkedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: const Text('Enlazada a: CALLE 14 # 2-104'),
        subtitle: const Text('Tú escribiste: "CALLE 14 # 2-104" — se guardan las dos.'),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Quitar enlace',
          onPressed: () {},
        ),
      ),
    );
  }
}

/// Spec 10 prediction, now reachable without a terna: the next expected placa,
/// derived from the anchor's R1 row.
class _ExpectedCard extends StatelessWidget {
  const _ExpectedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Siguiente esperada',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
            const SizedBox(height: 4),
            Text('CALLE 14 # 2-112',
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check),
                    label: const Text('Coincide'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.report_gmailerrorred),
                    label: const Text('No coincide'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
