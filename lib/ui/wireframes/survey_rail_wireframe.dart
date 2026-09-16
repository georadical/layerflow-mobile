import 'package:flutter/material.dart';

/// WIREFRAME — Spec 8, T8.2 "Survey rail" (the census pass).
///
/// Layout only, dummy data, no wiring. Every state the shared spec
/// (specs/extended-survey-phpv.md) demands is reviewable from the gallery.
///
/// The shape this wireframe argues for:
/// - **Unifamiliar costs nothing.** The common predio is one home, so the
///   form opens with its four questions already visible and NO structure
///   to declare. Buttons appear below, for when reality needs them
///   (CL-E2: the first "agregar" turns the implicit unit into 01/01 —
///   nothing answered is lost, it simply becomes Unit 1's answers).
/// - **Codes are never digits.** "Piso 2 · Unidad 3", read off the group
///   header plus the card title; PH/PV exist only in the payload.
/// - **The rail does not trap.** Strict order is a suggestion of where to
///   go next (the progress line), never a lock: closing mid-building and
///   coming back lands exactly where it was (CL-E1, CL-E6).
/// - **One list per route, still.** The survey is the SECOND PASS over the
///   same units, not a parallel world: the resume list gains a survey
///   chip and a second line — it does not spawn a "survey list". Spec 1.1
///   converged two lists of one route once; re-splitting them here would
///   undo that lesson (state shown in one place, acted on in another).
/// - **The totalizador is a gesture apart** — never part of a level, and
///   it demands its photo (CL-E4).
enum SurveyState {
  /// The default: one implicit unit, its questions visible, nothing
  /// declared. This is what most predios ever see.
  unifamiliar,

  /// Structure declared: floors and units, one card expanded.
  multiUnidad,

  /// A totalizador exists physically and was declared (99/99 + photo).
  totalizador,

  /// CL-E7: the device refuses to send a convention violation — a 409
  /// must be impossible from a healthy app.
  validacion,

  /// The entry point: the route list gains a survey-state chip per unit.
  railLista,
}

/// CL-E3 — field wording, pinned verbatim in the shared spec.
const _preguntaAcceso =
    '¿Esta unidad tiene entrada propia, sin pasar por dentro de otra?';
const _preguntaPorDonde = '¿Por dónde se entra?';
const _preguntaMedicion =
    '¿El servicio se mide aparte para esta unidad o con el general '
    'del predio?';
const _preguntaUso = '¿Para qué se usa?';

class SurveyRailWireframe extends StatelessWidget {
  const SurveyRailWireframe({super.key, required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    if (state == SurveyState.railLista) return const _RailList();
    return _SurveyForm(state: state);
  }
}

/// CL-E1 — the SAME resume list of Spec 1.1, with the survey grafted on:
/// one extra line per row and a state chip. Tapping still opens that
/// unit; the survey is simply what that unit owes on the second pass.
///
/// Deliberately NOT a separate screen: two lists of one route is the very
/// split Spec 1.1 removed.
class _RailList extends StatelessWidget {
  const _RailList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rows = [
      ('CALLE 7 3-21', 1, 5, _Estado.completa, '3 unidades declaradas'),
      ('C 5 2-99', 2, 10, _Estado.aMedias, 'Piso 2 · Unidad 1 pendiente'),
      ('CARRERA 4 12-08', 3, 15, _Estado.sinEncuesta, null),
      ('K 9 9-77', 4, 20, _Estado.sinEncuesta, null),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Ruta 10 · ESP Isnos (muestra)')),
      body: ListView.separated(
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
        itemBuilder: (context, i) {
          if (i == 0) {
            // The existing frame summary line, now also carrying the
            // second pass's progress.
            return Container(
              color: theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('4 direcciones · 1 encuestada',
                        style: theme.textTheme.titleSmall),
                  ),
                  Text('reanudado',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            );
          }
          final (placa, pos, loc, estado, detalle) = rows[i - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The address still leads — the placa pass's row is
                      // untouched.
                      Text(placa,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('posición $pos · loc $loc',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                      // The second pass adds ONE line, and only when it
                      // has something to say.
                      if (detalle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.apartment,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(detalle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _EstadoChip(estado: estado),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Capturar'),
      ),
    );
  }
}

enum _Estado { sinEncuesta, aMedias, completa }

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final _Estado estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg) = switch (estado) {
      _Estado.completa => (
          'completa',
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer
        ),
      _Estado.aMedias => (
          'a medias',
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer
        ),
      _Estado.sinEncuesta => (
          'sin encuesta',
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child:
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}

class _SurveyForm extends StatelessWidget {
  const _SurveyForm({required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unifamiliar = state == SurveyState.unifamiliar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encuesta'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Posición 3 · CALLE 7 3-21',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state == SurveyState.validacion) ...[
            const _ValidacionBanner(),
            const SizedBox(height: 16),
          ],

          if (unifamiliar) ...[
            // The common case: no structure to declare, questions right
            // here. Nothing to press before answering.
            Text('La vivienda', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Si detrás de esta puerta hay más de una unidad, agrégalas '
              'abajo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _Preguntas(),
          ] else ...[
            const _Nivel(
              piso: 'Piso 1',
              unidades: [
                ('Unidad 1', _Estado.completa, false),
                ('Unidad 2', _Estado.aMedias, true),
              ],
            ),
            const SizedBox(height: 16),
            const _Nivel(
              piso: 'Piso 2',
              unidades: [('Unidad 1', _Estado.sinEncuesta, false)],
            ),
          ],

          const SizedBox(height: 24),
          // CL-E2: incremental per level. Never a count typed in.
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: Text(unifamiliar
                ? 'Agregar otra unidad en este piso'
                : 'Agregar unidad en este piso'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.layers),
            label: const Text('Agregar piso'),
          ),

          const Divider(height: 40),
          // CL-E4: a gesture apart — never part of a level, and it demands
          // its photo. Declared ONLY if it physically exists.
          if (state == SurveyState.totalizador)
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('Totalizador declarado'),
                subtitle: const Text('Foto tomada · viaja como evidencia'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar',
                  onPressed: () {},
                ),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.speed),
              label: const Text('Hay totalizador (pide foto)'),
            ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: state == SurveyState.validacion ? null : () {},
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.check),
            label: const Text('Guardar encuesta'),
          ),
          const SizedBox(height: 8),
          Text(
            // CL-E5 + CL-E6: saving is local; travelling is the one Enviar
            // gesture, and a half-done survey survives closing the app.
            'Se guarda en el teléfono. Viaja cuando presiones Enviar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A floor and its units. The header plus the card title read as the
/// spec's "Piso 2 · Unidad 3" without repeating the word on every row —
/// and the PH/PV digits appear nowhere (CL-E2).
class _Nivel extends StatelessWidget {
  const _Nivel({required this.piso, required this.unidades});

  final String piso;
  final List<(String, _Estado, bool)> unidades;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(piso, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (nombre, estado, expandida) in unidades)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                ListTile(
                  title: Text(nombre),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EstadoChip(estado: estado),
                      const SizedBox(width: 4),
                      Icon(expandida ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                  onTap: () {},
                ),
                if (expandida)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _Preguntas(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// CL-E3 — the four questions, wording pinned verbatim. The first one is
/// the decisive test for "is this a separate unit"; the meter question
/// informs without being the criterion.
class _Preguntas extends StatelessWidget {
  const _Preguntas();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Opcion(
          pregunta: _preguntaAcceso,
          opciones: ['Sí', 'No'],
          decisiva: true,
        ),
        SizedBox(height: 16),
        _Opcion(
          pregunta: _preguntaPorDonde,
          opciones: ['Calle', 'Zona común'],
        ),
        SizedBox(height: 16),
        _Opcion(
          pregunta: _preguntaMedicion,
          opciones: ['Individual', 'General'],
        ),
        SizedBox(height: 16),
        _Opcion(
          pregunta: _preguntaUso,
          opciones: ['Vivienda', 'Local', 'Oficina', 'Otro'],
        ),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.pregunta,
    required this.opciones,
    this.decisiva = false,
  });

  final String pregunta;
  final List<String> opciones;

  /// The independent-access question decides the whole classification, so
  /// it is not visually one more row.
  final bool decisiva;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pregunta,
          style: decisiva
              ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
              : theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final o in opciones)
              ChoiceChip(label: Text(o), selected: false, onSelected: (_) {}),
          ],
        ),
      ],
    );
  }
}

/// CL-E7: the convention is checked HERE, before anything travels — a
/// convention 409 must be impossible from a healthy app.
class _ValidacionBanner extends StatelessWidget {
  const _ValidacionBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Declaraste el totalizador pero falta su foto. Sin ella la '
                'oficina no puede confirmarlo.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
