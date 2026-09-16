import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/survey/survey_pyramid.dart';
import '../providers.dart';

/// The real extended-survey form (Spec 8, T8.5), wired to the survey
/// controller. It is the SECOND pass over a captured unit: the surveyor
/// declares the building's structure with buttons and answers the four CL-E3
/// questions per unit. Every gesture auto-saves to drift (CL-E6), so leaving
/// mid-building loses nothing; the survey travels later on Enviar (CL-E5).
///
/// Not here yet: the totalizador photo (T8.4, needs the camera) and the
/// CL-E8 lock gate on the entry (needs the backend's TJ.5 flags). The push
/// itself is T8.5c.
class SurveyScreen extends ConsumerWidget {
  const SurveyScreen({
    super.key,
    required this.anchorClientId,
    required this.routeId,
    required this.posicion,
    this.placa,
  });

  final String anchorClientId;
  final String routeId;
  final int posicion;
  final String? placa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final args = SurveyArgs(anchorClientId: anchorClientId, routeId: routeId);
    final survey = ref.watch(surveyControllerProvider(args));

    final header = [
      'Posición $posicion',
      if (placa != null && placa!.trim().isNotEmpty) placa!.trim(),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encuesta'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(header, style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      body: switch (survey) {
        AsyncData(:final value) => _SurveyBody(args: args, structure: value),
        AsyncError(:final error) => Center(child: Text('Error: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SurveyBody extends ConsumerWidget {
  const _SurveyBody({required this.args, required this.structure});

  final SurveyArgs args;
  final SurveyStructure structure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(surveyControllerProvider(args).notifier);
    final unifamiliar = structure.isUnifamiliar;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (unifamiliar) ...[
          Text('La vivienda', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Si detrás de esta puerta hay más de una unidad, agrégalas abajo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _QuestionSet(
            answers: structure.answersAt(0, 0),
            onChanged: (a) => ctrl.setAnswers(0, 0, a),
          ),
        ] else
          for (var f = 0; f < structure.floorCount; f++)
            _FloorSection(args: args, structure: structure, floor: f),

        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => ctrl.addUnit(0),
          icon: const Icon(Icons.add),
          label: Text(unifamiliar
              ? 'Agregar otra unidad en este piso'
              : 'Agregar unidad en el piso 1'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ctrl.addFloor,
          icon: const Icon(Icons.layers),
          label: const Text('Agregar piso'),
        ),

        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            // Auto-saved on every gesture; this only confirms and returns.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Encuesta guardada en el teléfono.')),
            );
            Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.check),
          label: const Text('Guardar encuesta'),
        ),
        const SizedBox(height: 8),
        Text(
          'Se guarda en el teléfono. Viaja cuando presiones Enviar.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// A floor and its units (multi-unit predio). The header plus each card title
/// read as "Piso 2 · Unidad 3" — PH/PV digits appear nowhere (CL-E2).
class _FloorSection extends ConsumerWidget {
  const _FloorSection({
    required this.args,
    required this.structure,
    required this.floor,
  });

  final SurveyArgs args;
  final SurveyStructure structure;
  final int floor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(surveyControllerProvider(args).notifier);
    final units = structure.unitsInFloor(floor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (floor > 0) const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Piso ${floor + 1}',
                  style: theme.textTheme.titleMedium),
            ),
            if (floor > 0)
              TextButton.icon(
                onPressed: () => ctrl.removeFloor(floor),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar piso'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var u = 0; u < units; u++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              initiallyExpanded: !structure.answersAt(floor, u).isComplete,
              title: Text('Unidad ${u + 1}'),
              subtitle: Text(
                structure.answersAt(floor, u).isComplete ? 'completa' : 'a medias',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _QuestionSet(
                  answers: structure.answersAt(floor, u),
                  onChanged: (a) => ctrl.setAnswers(floor, u, a),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => ctrl.removeUnit(floor, u),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Quitar unidad'),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => ctrl.addUnit(floor),
            icon: const Icon(Icons.add),
            label: Text('Agregar unidad en el piso ${floor + 1}'),
          ),
        ),
      ],
    );
  }
}

/// The four CL-E3 questions (wording pinned verbatim). The independent-access
/// question decides the classification, so it leads and is emphasised; the
/// meter question informs without being the criterion.
class _QuestionSet extends StatelessWidget {
  const _QuestionSet({required this.answers, required this.onChanged});

  final SurveyAnswers answers;
  final ValueChanged<SurveyAnswers> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChoiceRow<AccesoIndependiente>(
          pregunta:
              '¿Esta unidad tiene entrada propia, sin pasar por dentro de otra?',
          decisiva: true,
          options: const [
            (AccesoIndependiente.si, 'Sí'),
            (AccesoIndependiente.no, 'No'),
          ],
          selected: answers.acceso,
          onSelected: (v) => onChanged(answers.copyWith(acceso: v)),
        ),
        const SizedBox(height: 16),
        _ChoiceRow<TipoAcceso>(
          pregunta: '¿Por dónde se entra?',
          options: const [
            (TipoAcceso.calle, 'Calle'),
            (TipoAcceso.zonaComun, 'Zona común'),
          ],
          selected: answers.tipoAcceso,
          onSelected: (v) => onChanged(answers.copyWith(tipoAcceso: v)),
        ),
        const SizedBox(height: 16),
        _ChoiceRow<Medicion>(
          pregunta: '¿El servicio se mide aparte para esta unidad o con el '
              'general del predio?',
          options: const [
            (Medicion.individual, 'Individual'),
            (Medicion.general, 'General'),
          ],
          selected: answers.medicion,
          onSelected: (v) => onChanged(answers.copyWith(medicion: v)),
        ),
        const SizedBox(height: 16),
        _ChoiceRow<Uso>(
          pregunta: '¿Para qué se usa?',
          options: const [
            (Uso.vivienda, 'Vivienda'),
            (Uso.local, 'Local'),
            (Uso.oficina, 'Oficina'),
            (Uso.otro, 'Otro'),
          ],
          selected: answers.uso,
          onSelected: (v) => onChanged(answers.copyWith(uso: v)),
        ),
      ],
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.pregunta,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.decisiva = false,
  });

  final String pregunta;
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelected;
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
            for (final (value, label) in options)
              ChoiceChip(
                label: Text(label),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}
