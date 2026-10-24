import 'package:flutter/material.dart';

/// Spec 12 amendment BR-C4 (+ BR-C4c): the soft "¿Te falta CON?" check before
/// saving a corner typed without the `CON` sentinel. Shared by capture and
/// editar unidad. True = [Guardar igual]; false (or dismissed) = [Corregir].
Future<bool> confirmMissingCon(BuildContext context) async {
  final saveAnyway = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('¿Te falta CON?'),
      content: const Text(
        'Parece una esquina escrita sin la palabra CON. Escríbela así: '
        'CALLE 13 CON CARRERA 3. Sin CON, la app la confunde con una '
        'dirección y desordena la parada.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('Guardar igual'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text('Corregir'),
        ),
      ],
    ),
  );
  return saveAnyway ?? false;
}
