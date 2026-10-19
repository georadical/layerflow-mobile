import 'package:flutter/material.dart';

/// WIREFRAME — Spec 18, SE.2 "Solo enlazar — no hay placa a la vista".
///
/// Layout only, dummy data, no wiring (specs/solo-enlazar.md). Reviews where the
/// button lives and how a capture linked to R1 WITHOUT an observed placa reads,
/// before touching the real capture form.
///
/// The shape this wireframe argues for:
/// - **In the link card.** The button sits inside "Enlazada a…" — the only place a
///   link exists (BR2) — so it can never be pressed without one.
/// - **On = cleared and locked.** The placa field empties and becomes read-only,
///   reading "Sin placa a la vista" (BR5); the photo stays "(requerida)" (BR6).
/// - **Same button after "Coincide".** Coincide also links (and today copies the
///   expected address into the field), so the card — and the button — appear there too.
/// - **Distinct in the list.** The row reads "Sin placa a la vista · enlazada a …"
///   (BR10), never as an observed placa.
enum SoloEnlazarState {
  /// An R1 suggestion was picked: link card with the button (off).
  linked,

  /// The mode is on: field cleared + locked, button shows the on state.
  sinPlaca,

  /// Mid-face, after "Coincide": the link card (and the button) appear too.
  coincide,

  /// The parada's capture list with a "sin placa a la vista" row.
  list,
}

class SoloEnlazarWireframe extends StatelessWidget {
  const SoloEnlazarWireframe({super.key, required this.state});

  final SoloEnlazarState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state == SoloEnlazarState.list) return _listScaffold(theme);

    final on = state == SoloEnlazarState.sinPlaca;
    final coincide = state == SoloEnlazarState.coincide;
    final address = coincide ? 'CALLE 20A # 3-11' : 'CALLE 20A # 3-03';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(coincide ? 'Parada 1 · ascendente' : 'Parada 1',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (coincide) ...[
            const _LastCaptureCard(),
            const SizedBox(height: 16),
          ],
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Construido')),
              ButtonSegment(value: true, label: Text('Sin construir')),
            ],
            selected: const {false},
            onSelectionChanged: (_) {},
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tomar foto de placa (requerida)'),
          ),
          const SizedBox(height: 16),
          _placaField(locked: on, typed: address),
          const SizedBox(height: 12),
          _LinkCard(address: address, on: on),
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

  /// The placa field: normal (holding the R1 address the pick copied in), or
  /// cleared + locked when the mode is on (BR5).
  Widget _placaField({required bool locked, required String typed}) {
    if (locked) {
      return const TextField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Placa (dirección en la puerta)',
          hintText: 'Sin placa a la vista',
          prefixIcon: Icon(Icons.lock_outline),
          helperText: 'Enlazada a R1 sin placa leída — la oficina la verifica.',
        ),
      );
    }
    return TextField(
      controller: TextEditingController(text: typed),
      decoration: const InputDecoration(
        labelText: 'Placa (dirección en la puerta)',
        helperText: 'Escribe lo que VES. Se guarda tal cual, siempre.',
      ),
    );
  }

  Widget _listScaffold(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parada 1 · Mz 5 · placas')),
      body: ListView(
        children: [
          // The corner, linked to R1 with no observed placa — reads apart (BR10).
          ListTile(
            leading:
                Icon(Icons.visibility_off, color: theme.colorScheme.tertiary),
            title: const Text('Sin placa a la vista'),
            subtitle: const Text('enlazada a CALLE 20A # 3-03 · predio 1'),
          ),
          const Divider(height: 1),
          // A normal captured placa.
          ListTile(
            leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            title: const Text('CALLE 20A # 3-11'),
            subtitle: const Text('predio 2'),
          ),
        ],
      ),
    );
  }
}

/// The link card ("Enlazada a…") with the SE button below the link line.
/// Off: an outlined invitation. On: a tonal, checked state that reads as a
/// toggle — tapping it again turns the mode off (BR5).
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.address, required this.on});

  final String address;
  final bool on;

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
              title: Text('Enlazada a: $address'),
              subtitle: Text(on
                  ? 'Sin placa a la vista — se verifica en oficina.'
                  : 'Tú escribiste: "$address" — se guardan las dos.'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quitar enlace',
                onPressed: () {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: on
                  ? FilledButton.tonalIcon(
                      onPressed: () {},
                      icon: const Icon(Icons.check),
                      label: const Text(
                          'Sin placa a la vista · toca para escribir la placa'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () {},
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

/// The anchor context card (mirrors the real screen) for the Coincide state.
class _LastCaptureCard extends StatelessWidget {
  const _LastCaptureCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Última capturada · predio 1',
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text('Sin placa a la vista · CALLE 20A # 3-03',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
