/// Local survey pyramid, the pinned PH/PV generator and the CL-E7
/// device-side convention validator (Spec 8,
/// specs/extended-survey-phpv.md §"PH/PV generation" and CL-E7).
///
/// Pure domain: no Flutter, no drift, no network. Persistence (drift) and
/// the /sync/push payload (DTOs) are built on top of this at T8.5 / T8.1;
/// this file is only the structure, the generation and the local guard.
///
/// The doctrine it encodes, straight from the pinned algorithm:
/// - **Codes are a function of the declared structure, never typed.**
///   PH = floor index (street = 01, upward); PV = declaration (walk) order
///   within the floor; `instancia` = a flat 1..98 declaration order over the
///   whole predio; 99/99/99 is the totalizador alone.
/// - **Deletion before sending compacts for free.** Because ph/pv/instancia
///   are DERIVED from position, removing a unit closes the gap in its floor
///   and removing a floor renumbers the floors above — there is no stored
///   code to fix, so the "compact renumber" the spec demands is automatic.
/// - **The app ALWAYS emits a unidad instance (Q1=(B), backend d2bb861).**
///   Every predio has at least one unit, so a unifamiliar predio emits ONE
///   `unidad` instancia=1 with ph/pv 01/01 and its four answers; the
///   00/00-vs-expand decision belongs to the backend at promotion (it keeps
///   the anchor at 00/00 when there is a single real unit, ignoring the
///   declared 01/01, and promotes the answers onto premise/hogar). The
///   census's atomic object is the unit, so the four answers, ph/pv and the
///   sub-entities always have ONE uniform home — no branch in the generator.
///   Adding structure appends 01/02, 02/01, …; deleting back to a single
///   unit returns to that lone 01/01, keeping the survivor's answers.
/// - **The convention is checked HERE, before anything travels** — a 409
///   must be impossible from a healthy app (CL-E7), the same philosophy as
///   the ins_after guard.
library;

/// PV/PH strings are always two digits ("01".."98", "99").
String _pad2(int n) => n.toString().padLeft(2, '0');

/// Real units live in 01..98; 99 is reserved for the totalizador
/// (§"PH/PV generation" + Instancia semantics).
const int maxRealCode = 98;
const int totalizadorCode = 99;
const String totalizadorPh = '99';
const String totalizadorPv = '99';
const int totalizadorInstancia = 99;

/// CL-E3 — the decisive question. Independent access classifies a unit; the
/// own-meter answer informs without being the criterion.
enum AccesoIndependiente {
  si('si'),
  no('no');

  const AccesoIndependiente(this.wire);

  /// Contract value pinned in the shared spec's model.
  final String wire;
}

enum TipoAcceso {
  calle('calle'),
  zonaComun('zona_comun');

  const TipoAcceso(this.wire);

  final String wire;
}

enum Medicion {
  individual('individual'),
  general('general');

  const Medicion(this.wire);

  final String wire;
}

enum Uso {
  vivienda('vivienda'),
  local('local'),
  oficina('oficina'),
  otro('otro');

  const Uso(this.wire);

  final String wire;
}

/// The four CL-E3 answers of one unit. All nullable: a unit is declared by a
/// gesture and answered afterwards, so a half-answered unit is a normal,
/// resumable state (CL-E6). Answer completeness is NOT a convention
/// violation — it gates SAVE in the UI, never a 409.
class SurveyAnswers {
  const SurveyAnswers({
    this.acceso,
    this.tipoAcceso,
    this.medicion,
    this.uso,
  });

  final AccesoIndependiente? acceso;
  final TipoAcceso? tipoAcceso;
  final Medicion? medicion;
  final Uso? uso;

  bool get isComplete =>
      acceso != null && tipoAcceso != null && medicion != null && uso != null;

  bool get isBlank =>
      acceso == null && tipoAcceso == null && medicion == null && uso == null;

  SurveyAnswers copyWith({
    AccesoIndependiente? acceso,
    TipoAcceso? tipoAcceso,
    Medicion? medicion,
    Uso? uso,
  }) =>
      SurveyAnswers(
        acceso: acceso ?? this.acceso,
        tipoAcceso: tipoAcceso ?? this.tipoAcceso,
        medicion: medicion ?? this.medicion,
        uso: uso ?? this.uso,
      );

  @override
  bool operator ==(Object other) =>
      other is SurveyAnswers &&
      other.acceso == acceso &&
      other.tipoAcceso == tipoAcceso &&
      other.medicion == medicion &&
      other.uso == uso;

  @override
  int get hashCode => Object.hash(acceso, tipoAcceso, medicion, uso);
}

/// One generated row of the survey pass: an `entidad=unidad` instancia with
/// its ph/pv, or the 99/99 totalizador. The output the DTO layer (T8.1)
/// turns into field_responses; a sub-entity (hogar/…) rides the same
/// `instancia`.
class GeneratedUnit {
  const GeneratedUnit({
    required this.instancia,
    required this.ph,
    required this.pv,
    required this.answers,
    required this.isTotalizador,
  });

  final int instancia;
  final String ph;
  final String pv;
  final SurveyAnswers answers;
  final bool isTotalizador;

  @override
  bool operator ==(Object other) =>
      other is GeneratedUnit &&
      other.instancia == instancia &&
      other.ph == ph &&
      other.pv == pv &&
      other.answers == answers &&
      other.isTotalizador == isTotalizador;

  @override
  int get hashCode => Object.hash(instancia, ph, pv, answers, isTotalizador);

  @override
  String toString() =>
      'GeneratedUnit(inst=$instancia, $ph/$pv${isTotalizador ? ' T' : ''})';
}

/// The kinds of convention breach the device refuses to send (CL-E7). The
/// codes the app can only ever hit by construction (00 mixed with 01+,
/// duplicate ph/pv) cannot arise here — the generator derives codes from
/// position, so they are impossible, not merely unlikely. What CAN go wrong
/// at runtime is a declared totalizador with no photo, an anchor that is a
/// lote, or an implausibly huge structure spilling past 98.
enum SurveyViolation {
  /// 99/99 declared but its photo is missing (doctrine: totalizador is
  /// evidence-only). Matches the validation banner in the wireframe.
  totalizadorSinFoto,

  /// A real unit's code (or instancia) spilled past 98 into the totalizador
  /// reservation — only reachable with an absurd number of units.
  fueraDeRango,

  /// Unidad instances were declared but the anchor is a lote (es_lote): a
  /// lote cannot hold PH/PV units.
  ancoraEsLote,
}

/// A single CL-E7 finding, with the field-facing message the UI shows.
class ConventionViolation {
  const ConventionViolation(this.kind, this.message);

  final SurveyViolation kind;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ConventionViolation &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'ConventionViolation($kind)';
}

/// The declared structure of one predio, as an immutable value: a list of
/// floors, each a list of units (their answers), plus the optional
/// totalizador. Every gesture returns a NEW structure; ph/pv/instancia are
/// never stored, only generated, so there is nothing to keep in sync.
///
/// Invariant: there is always at least one floor with at least one unit,
/// so [generate] never returns empty — the app always emits a unidad
/// (Q1=(B)). `isUnifamiliar` (one unit) is informational for the UI, not a
/// gate on generation: a lone unit still emits its 01/01.
class SurveyStructure {
  const SurveyStructure._(this._floors, this.totalizador, this.totalizadorPhoto);

  /// The common predio: one implicit unit, no structure declared. Its
  /// answers are captured directly and, if structure is ever added, become
  /// unit 01/01's answers (CL-E2).
  factory SurveyStructure.unifamiliar([
    SurveyAnswers single = const SurveyAnswers(),
  ]) =>
      SurveyStructure._([
        [single],
      ], false, null);

  final List<List<SurveyAnswers>> _floors;

  /// Whether a physical totalizador was declared (99/99). Declaring it does
  /// not require the photo up front — the photo can arrive after — but
  /// [validate] refuses to send until it is present (CL-E4/CL-E7).
  final bool totalizador;

  /// Local path of the totalizador photo, once taken.
  final String? totalizadorPhoto;

  int get floorCount => _floors.length;

  int unitsInFloor(int floor) => _floors[floor].length;

  int get totalUnits => _floors.fold(0, (n, f) => n + f.length);

  /// One unit only. Informational — the UI shows the simplified single-unit
  /// form — but it does NOT suppress the unidad instance: under Q1=(B) even
  /// a lone unit emits its 01/01, and the backend decides 00/00-vs-expand.
  bool get isUnifamiliar => totalUnits <= 1;

  SurveyAnswers answersAt(int floor, int unit) => _floors[floor][unit];

  /// The single implicit unit's answers (only meaningful while unifamiliar,
  /// but always the first unit of the first floor).
  SurveyAnswers get single => _floors[0][0];

  List<List<SurveyAnswers>> _clone() => [
        for (final f in _floors) [...f],
      ];

  /// "agregar piso": a new floor above, with its first unit (PV 01). Called
  /// from unifamiliar it materialises the implicit unit as 01/01 (it is
  /// already floor 0, unit 0) and this becomes floor 02.
  SurveyStructure addFloor() {
    final floors = _clone()..add([const SurveyAnswers()]);
    return SurveyStructure._(floors, totalizador, totalizadorPhoto);
  }

  /// "agregar unidad en este piso": one more unit at the end of [floor].
  /// Called on floor 0 from unifamiliar, the implicit unit stays 01/01 and
  /// the new one is 01/02 — its answers preserved because it never moved.
  SurveyStructure addUnit(int floor) {
    final floors = _clone();
    floors[floor].add(const SurveyAnswers());
    return SurveyStructure._(floors, totalizador, totalizadorPhoto);
  }

  /// Overwrite one unit's answers.
  SurveyStructure setAnswers(int floor, int unit, SurveyAnswers answers) {
    final floors = _clone();
    floors[floor][unit] = answers;
    return SurveyStructure._(floors, totalizador, totalizadorPhoto);
  }

  /// Remove a unit before sending. The floor closes the gap; an emptied
  /// floor drops (renumbering the floors above); removing the very last unit
  /// collapses back to an empty unifamiliar, keeping the survivor's answers.
  SurveyStructure removeUnit(int floor, int unit) {
    final floors = _clone();
    floors[floor].removeAt(unit);
    if (floors[floor].isEmpty) floors.removeAt(floor);
    if (floors.isEmpty) {
      return SurveyStructure._([
        [const SurveyAnswers()],
      ], totalizador, totalizadorPhoto);
    }
    return SurveyStructure._(floors, totalizador, totalizadorPhoto);
  }

  /// Remove a whole floor before sending; the floors above renumber down.
  SurveyStructure removeFloor(int floor) {
    final floors = _clone()..removeAt(floor);
    if (floors.isEmpty) {
      return SurveyStructure._([
        [const SurveyAnswers()],
      ], totalizador, totalizadorPhoto);
    }
    return SurveyStructure._(floors, totalizador, totalizadorPhoto);
  }

  /// Declare (or re-declare) the totalizador. Photo optional here; required
  /// to send.
  SurveyStructure declareTotalizador({String? photo}) =>
      SurveyStructure._(_floors, true, photo);

  /// Attach the totalizador photo once taken (keeps it declared).
  SurveyStructure attachTotalizadorPhoto(String photo) =>
      SurveyStructure._(_floors, true, photo);

  /// Undeclare the totalizador (no 99/99 instance, no photo).
  SurveyStructure clearTotalizador() =>
      SurveyStructure._(_floors, false, null);

  /// The pinned generator (§"PH/PV generation"). Always emits one instancia
  /// per unit in walk order (Q1=(B): a lone unit is still 01/01), then the
  /// 99/99 totalizador if declared.
  List<GeneratedUnit> generate() {
    final out = <GeneratedUnit>[];
    var instancia = 0;
    for (var f = 0; f < _floors.length; f++) {
      final ph = _pad2(f + 1);
      for (var u = 0; u < _floors[f].length; u++) {
        instancia += 1;
        out.add(GeneratedUnit(
          instancia: instancia,
          ph: ph,
          pv: _pad2(u + 1),
          answers: _floors[f][u],
          isTotalizador: false,
        ));
      }
    }
    if (totalizador) {
      out.add(const GeneratedUnit(
        instancia: totalizadorInstancia,
        ph: totalizadorPh,
        pv: totalizadorPv,
        answers: SurveyAnswers(),
        isTotalizador: true,
      ));
    }
    return out;
  }

  /// CL-E7: the device-side convention check. Empty list ⇒ safe to send.
  /// [anchorIsLote] is the captured predio's es_lote flag when the app knows
  /// it (a lote cannot hold PH/PV units); default false.
  List<ConventionViolation> validate({bool anchorIsLote = false}) {
    final out = <ConventionViolation>[];

    if (totalizador && (totalizadorPhoto == null || totalizadorPhoto!.isEmpty)) {
      out.add(const ConventionViolation(
        SurveyViolation.totalizadorSinFoto,
        'Declaraste el totalizador pero falta su foto. Sin ella la oficina '
        'no puede confirmarlo.',
      ));
    }

    // A lote has no building: it cannot hold PH/PV units at all, and under
    // Q1=(B) the app always emits at least one, so surveying a lote is always
    // a convention breach the office would reject.
    if (anchorIsLote) {
      out.add(const ConventionViolation(
        SurveyViolation.ancoraEsLote,
        'Este predio está marcado como lote y no puede tener unidades PH/PV.',
      ));
    }

    // Real units must stay within 01..98 (ph, pv and instancia alike). Only
    // reachable with an absurd structure, but the guard makes a range 409
    // impossible from the app.
    final real = generate().where((u) => !u.isTotalizador);
    final spills = real.any((u) =>
        u.instancia > maxRealCode ||
        int.parse(u.ph) > maxRealCode ||
        int.parse(u.pv) > maxRealCode);
    if (spills) {
      out.add(const ConventionViolation(
        SurveyViolation.fueraDeRango,
        'Hay demasiadas unidades o pisos: los códigos pasan de 98.',
      ));
    }

    return out;
  }

  /// True when nothing blocks the send (CL-E7).
  bool canSend({bool anchorIsLote = false}) =>
      validate(anchorIsLote: anchorIsLote).isEmpty;
}
