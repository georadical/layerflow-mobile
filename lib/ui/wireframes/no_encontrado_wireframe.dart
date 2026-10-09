import 'package:flutter/material.dart';

/// WIREFRAME — Spec 14, NE.1 "No encontrado en campo".
///
/// Layout only, dummy data, no wiring (specs/no-encontrado-en-campo.md). Reviews
/// where the **"No encontrada en campo"** action lives and how a not-found reads,
/// before touching the real prediction card / queue.
///
/// The shape this wireframe argues for:
/// - **On the prediction card.** Below "Coincide / No coincide" (there IS a predio,
///   matching or not), a third, subtler action **"No encontrada en campo"** — for
///   when there is NO predio and NO lot at all.
/// - **Guardrail confirm.** It is a consequential negative claim, so it confirms,
///   and the confirm **reminds** that a demolished predio / lot is "Sin construir",
///   so not-found is never a catch-all.
/// - **Advances the sweep.** After declaring, the card shows the NEXT expected
///   placa (BR4); the declared one is accounted for, not skipped.
/// - **Distinct in the resume.** A not-found row reads apart from captured placas
///   and pending ones, carries its observación, and can be undone.
enum NoEncontradoState {
  /// The prediction card with the "No encontrada en campo" action.
  card,

  /// The guardrail confirm over the card (faux dialog).
  confirm,

  /// After confirming → the card advances to the next expected placa.
  advanced,

  /// The resume list, with a distinct "no encontrada" row.
  resume,
}

class NoEncontradoWireframe extends StatelessWidget {
  const NoEncontradoWireframe({super.key, required this.state});

  final NoEncontradoState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state == NoEncontradoState.resume) return _resumeScaffold(theme);

    final body = _captureBody(theme);
    return Scaffold(
      appBar: _captureAppBar(theme),
      body: state == NoEncontradoState.confirm
          ? Stack(children: [body, _ConfirmDialog(theme: theme)])
          : body,
    );
  }

  PreferredSizeWidget _captureAppBar(ThemeData theme) => AppBar(
        title: const Text('Captura'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Parada 1 · Mz 327', style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      );

  Widget _captureBody(ThemeData theme) {
    // After the declaration, the sweep advanced from 3-20 → 3-22 (BR4).
    final advanced = state == NoEncontradoState.advanced;
    final expected = advanced ? 'CALLE 13 # 3-22' : 'CALLE 13 # 3-20';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LastCaptureCard(predio: advanced ? 1 : 1),
        const SizedBox(height: 16),
        if (advanced) ...[
          _NotFoundBanner(theme: theme),
          const SizedBox(height: 16),
        ],
        _PredictionCard(expected: expected),
        const SizedBox(height: 16),
        _placaField(),
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
    );
  }

  Widget _placaField() => const TextField(
        decoration: InputDecoration(
          labelText: 'Placa (dirección en la puerta)',
          hintText: 'CALLE 13 # 3-20',
          helperText: 'Escribe lo que VES. Se guarda tal cual, siempre.',
        ),
      );

  Widget _resumeScaffold(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parada 1 · Mz 327 · placas')),
      body: ListView(
        children: [
          // A normal captured placa.
          ListTile(
            leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            title: const Text('CALLE 13 # 3-18'),
            subtitle: const Text('predio 1 · loc 5'),
          ),
          const Divider(height: 1),
          // The not-found row — reads apart, carries the observación, undoable.
          ListTile(
            leading:
                Icon(Icons.search_off, color: theme.colorScheme.tertiary),
            title: const Text('CALLE 13 # 3-20'),
            subtitle: const Text(
                'No encontrada en campo · "demolido, hoy parqueadero"'),
            trailing: TextButton(
              onPressed: () {},
              child: const Text('Deshacer'),
            ),
          ),
          const Divider(height: 1),
          // The next captured placa (sweep continued past the not-found).
          ListTile(
            leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            title: const Text('CALLE 13 # 3-22'),
            subtitle: const Text('predio 2 · loc 10'),
          ),
        ],
      ),
    );
  }
}

/// The prediction card: the next expected placa + "Coincide / No coincide", and
/// below them the not-found action (NE.1 — the new element).
class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.expected});

  final String expected;

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
            Text(expected,
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
            Divider(height: 24, color: theme.colorScheme.outlineVariant),
            // NE.1 — the not-found action: subtler than Coincide/No coincide,
            // because it is the rarer, more consequential claim.
            Center(
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.search_off),
                label: const Text('No encontrada en campo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small banner after a declaration: the not-found was recorded and the sweep
/// moved on (BR4) — it is accounted for, not skipped.
class _NotFoundBanner extends StatelessWidget {
  const _NotFoundBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.search_off, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'CALLE 13 # 3-20 — marcada como no encontrada. Sigue 3-22.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
            TextButton(onPressed: () {}, child: const Text('Deshacer')),
          ],
        ),
      ),
    );
  }
}

/// The anchor context card at the top (mirrors the real screen): the last
/// captured predio drives the prediction.
class _LastCaptureCard extends StatelessWidget {
  const _LastCaptureCard({required this.predio});

  final int predio;

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
            Text('Última capturada · predio $predio',
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text('CALLE 13 # 3-18',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// The guardrail confirm (faux dialog for the wireframe): it reminds that a
/// demolished predio / lot is "Sin construir", and offers only Cancelar /
/// Confirmar — a deliberate two-way choice before a negative record.
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(color: Colors.black54),
        Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿CALLE 13 # 3-20 no existe en campo?',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const Text(
                      'Si está demolido o es un lote, usa "Sin construir".'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () {}, child: const Text('Cancelar')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () {},
                          child: const Text('Confirmar: no existe')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
