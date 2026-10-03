import 'package:flutter/material.dart';

/// WIREFRAME — Spec 12, LC.3 "Captura de lote (es_lote)".
///
/// Layout only, dummy data, no wiring (specs/captura-lote.md). Reviews the
/// "marcar como lote" toggle and how a lot reads in the list, before wiring.
///
/// The shape this wireframe argues for:
/// - **A toggle, not a separate flow.** "Marcar como lote" lives in the same
///   capture form; turning it on makes the placa/distance OPTIONAL and hides the
///   R1 suggestions (a lot has no address to link).
/// - **Photo follows the placa, not the toggle.** A plate-less lot (potrero) is
///   EXEMPT from foto_obligatoria (Jorge's carve-out); a lot WITH a placa
///   (demolición) still requires it.
/// - **The list marks "Lote".** A lot with a placa shows the composed address +
///   a "Lote" chip; a plate-less lot reads just "Lote". No "potrero" state.
enum LoteState {
  /// Normal capture — the toggle is off.
  formNormal,

  /// The lot toggle is ON: placa optional, R1 hidden, photo optional (plate-less).
  formLote,

  /// Resume list with a normal row, a lot WITH a placa, and a plate-less lot.
  listaResume,
}

class LoteCaptureWireframe extends StatelessWidget {
  const LoteCaptureWireframe({super.key, required this.state});

  final LoteState state;

  @override
  Widget build(BuildContext context) {
    if (state == LoteState.listaResume) return const _ResumeList();
    return _CaptureForm(lote: state == LoteState.formLote);
  }
}

/// A small "Lote" chip for the list + the form.
class _LoteChip extends StatelessWidget {
  const _LoteChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.crop_square,
              size: 13, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 3),
          Text('Lote',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
        ],
      ),
    );
  }
}

class _CaptureForm extends StatelessWidget {
  const _CaptureForm({required this.lote});

  final bool lote;

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
              child: Text('Parada 2 · ascendente',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Face card (Spec 11) — unchanged; a lot is one more parada.
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerLow,
            child: const ListTile(
              leading: Icon(Icons.grid_4x4),
              title: Text('Zona: Urbana · Mz 327 · parada 2'),
              subtitle: Text('La manzana la fija la parada — no se escribe.'),
            ),
          ),
          const SizedBox(height: 16),

          // Spec 12: built state — Construido (default) vs Sin construir (= lote).
          // Sin construir makes the placa optional and hides R1. M3 puts the ✓ on
          // the selected segment automatically.
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Construido'),
                  icon: Icon(Icons.home_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Sin construir'),
                  icon: Icon(Icons.crop_square),
                ),
              ],
              selected: {lote},
              onSelectionChanged: (_) {},
            ),
          ),
          if (lote) ...[
            const SizedBox(height: 8),
            Text('Lote baldío — la dirección es opcional.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.photo_camera),
            label: Text(lote
                ? 'Tomar foto del lote (opcional)'
                : 'Tomar foto de placa (requerida)'),
          ),
          const SizedBox(height: 16),

          TextField(
            decoration: InputDecoration(
              labelText: lote
                  ? 'Dirección del lote (opcional)'
                  : 'Placa (dirección en la puerta)',
              hintText: lote ? 'Vacío en potrero' : 'C 8 5-10',
              helperText: lote
                  ? 'Si lees la dirección, escríbela; si no, déjala vacía.'
                  : 'Escribe lo que VES. Se guarda tal cual, siempre.',
            ),
          ),
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
}

class _ResumeList extends StatelessWidget {
  const _ResumeList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // (direccion, esLote, parada, predio, loc)
    const rows = <(String, bool, int, int, int)>[
      ('CARRERA 4 # 2-03', false, 1, 1, 5),
      ('CALLE 13 # 3-30', true, 2, 1, 20), // lot WITH a placa (demolición)
      ('Lote', true, 2, 2, 25), // plate-less lot (potrero)
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Ruta 10 · ESP Isnos (muestra)')),
      body: ListView.separated(
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Container(
              color: theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('3 direcciones capturadas',
                  style: theme.textTheme.titleSmall),
            );
          }
          final (dir, esLote, parada, predio, loc) = rows[i - 1];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(dir,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (esLote) ...[
                      const SizedBox(width: 8),
                      const _LoteChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Parada $parada · predio $predio · loc $loc · Zona: Urbana · Mz 327',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
