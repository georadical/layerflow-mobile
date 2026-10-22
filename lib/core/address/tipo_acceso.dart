/// Spec 20 — the access type (`tipo_acceso`): one option list for capture and
/// editar unidad, and the rule that makes it mandatory on a built corner.
/// The wire field and its keys are unchanged (no contract change, BR15).
library;

import 'address_normalizer.dart';

/// BR5/BR6/BR13: key → label, in display order. Shared by capture and editor so
/// both show the same four options with the same labels.
const tipoAccesoOptions = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común (hall/escalera/patio)',
  'sin_entrada_visible': 'Sin entrada visible',
  'otro': 'Otro',
};

/// BR9: the field label, telling the surveyor beforehand when it is required.
const tipoAccesoLabelOptional = 'Tipo de acceso (opcional)';
const tipoAccesoLabelRequired = 'Tipo de acceso (obligatorio en esquina)';

/// BR8: the inline error when a built corner is saved without it.
const tipoAccesoRequiredError = 'Elige el tipo de acceso: es una esquina';

/// BR1: a built corner — Construido (not a lot, BR4) and either the placa is a
/// cruce (the pinned detector: `CON` + a via, as in the backend's `address.py`)
/// or the capture is linked "sin placa a la vista" (Spec 18).
bool isBuiltCorner({
  required bool esLote,
  required String placa,
  required bool sinPlaca,
}) =>
    !esLote && (sinPlaca || normalizeAddress(placa).esCruce);

/// BR2/BR7: whether saving must be refused — a built corner with no access
/// type. Any option satisfies it, "Otro" included.
bool tipoAccesoMissing({required bool builtCorner, String? tipoAcceso}) =>
    builtCorner && (tipoAcceso == null || tipoAcceso.trim().isEmpty);
