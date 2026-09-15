import 'package:flutter/material.dart';

/// CL-R1 amendment: when the worker links an R1 address while the typed
/// placa is INCOMPLETE (it does not normalize to a full address), the app
/// asks whether the physical plate reads exactly the R1 text.
///
/// - true  → "Sí, es esa": the caller copies the R1 text into the placa
///   field. This is NOT the forbidden silent overwrite — it is an
///   observation affirmed by an explicit gesture, and the pair stays
///   honest (rutina).
/// - false → "No, difiere": the typed text stays; the capture will
///   classify as a legitimate divergence.
/// - null  → dismissed: no link happens; back to typing.
Future<bool?> confirmExactPlate(BuildContext context, String direccion) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿La placa dice exactamente…?'),
      content: Text('La placa física de la puerta, ¿dice exactamente '
          '"$direccion"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No, difiere'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sí, es esa'),
        ),
      ],
    ),
  );
}
