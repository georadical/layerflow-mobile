import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address/address_normalizer.dart';
import '../../core/address/manzana_label.dart';
import '../../core/config/app_config.dart';
import '../../core/camera/plate_camera.dart';
import '../../core/ocr/plate_ocr.dart';
import '../../core/parada/predio_sequence.dart';
import '../widgets/predio_number.dart';
import '../../data/repositories/evidence_repository.dart';
import '../widgets/confirm_exact_plate.dart';
import 'plate_shot_screen.dart';

import '../../data/db/database.dart';
import '../providers.dart';
import '../widgets/token_warning_banner.dart';

/// tipo_acceso options (optional). The stored value is the key.
const _tipoAccesoOptions = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común (hall/escalera/patio)',
  'otro': 'Otro',
};

/// Result of an on-demand shot attempt. [cameraAvailable] false means the
/// camera could not start (the valve → sin foto, never blocks); when true,
/// [shot] null means the worker backed out.
class _ShotOutcome {
  const _ShotOutcome({this.shot, required this.cameraAvailable});
  final XFile? shot;
  final bool cameraAvailable;
}

/// Capture screen: strict append, one placa per household.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, required this.routeId});
  final String routeId;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _placaCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _placaFocus = FocusNode();
  String? _tipoAcceso;
  bool _saving = false;

  // R1-assisted capture (Spec 7). The typeahead only exists where a
  // directory exists; rural / paste-flow capture stays classic.
  List<R1DirectoryData> _suggestions = [];
  R1DirectoryData? _linked;
  bool _notInList = false;
  int? _duplicateOfPosicion;
  bool _directoryAvailable = false;
  int _searchSeq = 0;

  /// Spec 12: the predio's built state — false = Construido (default), true =
  /// Sin construir (a vacant lot, `es_lote`). Per-capture; resets to false on
  /// save. When true the placa is optional, R1 is hidden, and a plate-less lot
  /// is exempt from the mandatory photo.
  bool _esLote = false;

  /// Spec 10 PC.3: the worker tapped "No coincide" on the predicted placa —
  /// hide the prediction for THIS capture so they enter what they see. Reset
  /// on save (the next door predicts again).
  bool _predictionDismissed = false;

  /// The guided-sweep context for the current parada, or null on an unassisted
  /// route (classic flow). Read via [ref] so the change-handlers can reach it.
  ParadaCaptureContext? get _paradaCtx =>
      ref.read(paradaCaptureContextProvider(widget.routeId)).valueOrNull;

  /// The raw current parada (from the stops cache), available as soon as the
  /// stops load — BEFORE the heavier async [_paradaCtx] prediction. The manzana
  /// scope + stop binding read from HERE, never from [_paradaCtx], so a search is
  /// never run unscoped during the context-loading window: Spec 13 found that an
  /// unscoped (global) search lets the worker link an R1 row from ANOTHER
  /// manzana, which corrupts the anchor and breaks prediction.
  Parada? get _currentParada =>
      ref.read(currentParadaProvider(widget.routeId));

  // Camera per SHOT, on demand (CL-R3): there is NO live preview and NO
  // persistent camera across the walk — a streaming viewfinder open at every
  // door is a real battery drain over a full route. The camera is started
  // only when a shot is actually taken (the CTA, or a required trigger at
  // save), then disposed at once. `_camera` here is never started; it hosts
  // the stateless storeShotFor (compression + save) only.
  final _camera = PlateCamera();
  final _ocr = PlateOcr();

  /// Deliberate shot taken via the CTA (CL-R3 v1.1): used at save, satisfies
  /// the lottery, and divergence never re-asks for it.
  XFile? _deliberateShot;

  /// Guards the on-demand start→shot→dispose against a double tap.
  bool _takingShot = false;

  /// CL-R3 v1.1: starts a FRESH camera for one aimed shot and disposes it
  /// right after. Returns the outcome so the caller can tell a dead camera
  /// (valve → sin foto, never blocks) from a worker who backed out (a
  /// required shot then aborts the save).
  Future<_ShotOutcome> _takeDeliberateShot({required bool required}) async {
    if (_takingShot) return const _ShotOutcome(cameraAvailable: true);
    setState(() => _takingShot = true);
    final camera = PlateCamera();
    try {
      final ok = await camera.start();
      if (!ok) return const _ShotOutcome(cameraAvailable: false);
      if (!mounted) return const _ShotOutcome(cameraAvailable: true);
      final shot = await Navigator.of(context).push<XFile?>(
        MaterialPageRoute(
          builder: (_) => PlateShotScreen(camera: camera, required: required),
        ),
      );
      return _ShotOutcome(shot: shot, cameraAvailable: true);
    } finally {
      await camera.dispose();
      if (mounted) setState(() => _takingShot = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId == null) return;
      final count =
          await ref.read(r1DirectoryRepositoryProvider).countFor(tenantId);
      if (mounted) setState(() => _directoryAvailable = count > 0);
    });
  }

  /// Compresses and queues the ALREADY-taken shot. Fire-and-forget from
  /// the save gesture: the worker moves to the next door immediately.
  ///
  /// [evidenceRepo] is captured BEFORE the async gap: this future outlives
  /// the screen (the worker may leave while it compresses), and touching
  /// `ref` after dispose would silently kill the enqueue — found live in
  /// the E2E when case C's file landed but its row never did.
  Future<void> _storeEvidence(
    EvidenceRepository evidenceRepo,
    String clientId,
    String soporte,
    String? owner,
    XFile shot,
  ) async {
    final path = await _camera.storeShotFor(clientId, shot);
    if (path == null) return; // sin foto: degraded, never blocking
    await evidenceRepo.enqueue(
      clientId: clientId,
      routeId: widget.routeId,
      filePath: path,
      soporte: soporte,
      owner: owner,
    );
  }

  /// CL-R2: reads the shot and, ONLY on a mismatch against what the worker
  /// typed/selected, asks "¿confirmas?". Returns false when the worker
  /// wants to correct (save aborts, the form stays); true otherwise —
  /// including every silent path (no OCR reading, no mismatch, any error).
  Future<bool> _ocrSoftCheck(XFile shot) async {
    final read = await _ocr.readPlate(shot.path);
    if (read == null) return true; // nothing plausible: total silence

    final typed = _placaCtrl.text;
    final reference =
        typed.trim().isNotEmpty ? typed : (_linked?.direccionNorm ?? '');
    if (!plateMismatch(read, reference)) return true;

    if (!mounted) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('La cámara leyó otra cosa'),
        content: Text('La cámara leyó "$read" y tú escribiste '
            '"$typed". ¿Confirmas lo escrito?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Corregir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmo lo escrito'),
          ),
        ],
      ),
    );
    return confirmed ?? true; // dismissed = keep going: assist, not cage
  }

  /// Filters the directory as the worker types (CL-R1). The typed text is
  /// NEVER modified by anything here — it is the observed truth.
  ///
  /// Spec 13: scoped to the parada's MANZANA (full-placa search). AM.8: once the
  /// parada has an R1-linked anchor, the worker types only the distance and we
  /// search by distance on the anchor's face (terna from the anchor's R1 row). A
  /// parada with NO manzana is rural — free text, no search.
  Future<void> _onPlacaChanged(String text) async {
    if (_linked != null || _notInList) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId == null || !_directoryAvailable) return;
    // Spec 13 — do NOT search until the stops have loaded: a premature GLOBAL
    // search (manzana unknown) surfaces rows from OTHER manzanas and lets the
    // worker link one (the cross-manzana anchor bug).
    if (!ref.read(routeStopsProvider(widget.routeId)).hasValue) return;
    final parada = _currentParada;
    // Rural (a parada with no manzana): free text, nothing to search.
    if (parada != null && (parada.manzana?.trim().isEmpty ?? true)) return;
    final mz = parada?.manzana?.trim() ?? '';
    final seq = ++_searchSeq;
    final repo = ref.read(r1DirectoryRepositoryProvider);
    // AM.8: after an R1-linked anchor, the typed text is a DISTANCE — search by
    // distance on the anchor's face (terna from the anchor's R1 row), scoped to
    // the manzana. Before the anchor it is the full placa (Spec 13).
    final anchor = _esLote ? null : _paradaCtx?.anchorFace;
    final List<R1DirectoryData> hits;
    if (anchor != null && mz.isNotEmpty) {
      hits = await repo.searchByDistance(
        tenantId,
        tipoVia: anchor.via,
        numVia: anchor.numVia,
        numCruce: anchor.numCruce,
        distancePrefix: text.trim(),
        manzana: mz,
      );
    } else {
      hits = await repo.search(tenantId, text, manzana: mz.isEmpty ? null : mz);
    }
    if (!mounted || seq != _searchSeq) return;
    // setState even when empty: the panel must show "No está en la lista"
    // for text that matches NOTHING (CL-R1).
    setState(() => _suggestions = hits);
  }

  bool get _panelVisible {
    if (_esLote) return false; // Spec 12: a lot uses no R1 directory UI.
    if (!_directoryAvailable) return false;
    final parada = _currentParada;
    // Spec 13: rural (a parada with no manzana) has no directory UI; a parada
    // WITH a manzana — or an unassisted route — uses the downloaded directory.
    if (parada != null && (parada.manzana?.trim().isEmpty ?? true)) {
      return false;
    }
    return _linked == null &&
        !_notInList &&
        _placaCtrl.text.trim().isNotEmpty;
  }

  /// Links the unit to the tapped R1 address. The NPN rides hidden. A
  /// second use of the same NPN in the route warns and marks divergence —
  /// never blocks (CL-R3 trigger 5, PH share).
  ///
  /// A confirmed R1 link stores the FULL direccion (Jorge 2026-10-05): the worker
  /// types a shortcut ("3A-02") or a distance ("08"), and the stored placa becomes
  /// the canonical "CALLE 13 # 3A-02". CL-R1 is preserved for divergence: in
  /// full-placa mode, if the typed text does not already read as the R1 door, the
  /// app asks "¿dice exactamente…?" — "No, difiere" keeps the typed observation
  /// (still links the npn); dismissing links nothing. In distance / guided mode
  /// the pick is an exact match by construction, so it links straight to the full.
  Future<void> _select(R1DirectoryData hit) async {
    final ctx = _paradaCtx;
    // Full-placa mode (Spec 13: no anchor yet, no terna) with a typed text that
    // does NOT already read as this R1 door: confirm the plate says exactly it.
    // "No, difiere" is a legitimate divergence → keep the typed observation
    // (still link the npn); dismissing links nothing.
    final fullPlacaMode = ctx?.anchorFace == null && !(ctx?.hasTerna ?? false);
    // Spec 13: warn BEFORE anchoring a MIDDLE placa (one before AND one after),
    // which gives no sweep direction. Only for the anchor (fullPlacaMode); the
    // worker can still anchor it ("Anclar igual").
    final manzana = ctx?.parada.manzana;
    if (fullPlacaMode && manzana != null && manzana.trim().isNotEmpty) {
      final isMiddle = await ref.read(isMiddleAnchorProvider(
        (manzana: manzana, direccionNorm: hit.direccionNorm),
      ).future);
      if (!mounted) return;
      if (isMiddle && !await _confirmMiddleAnchor()) return; // chose another
      if (!mounted) return;
    }
    var keepTyped = false;
    if (fullPlacaMode &&
        !typedMatchesLinked(_placaCtrl.text, hit.direccionNorm)) {
      final saysExactly = await confirmExactPlate(context, hit.direccionNorm);
      if (saysExactly == null || !mounted) return; // dismissed: no link
      keepTyped = !saysExactly; // "No, difiere" → keep what the worker observed
    }
    // Jorge 2026-10-05: a confirmed R1 link stores the FULL direccion. The worker
    // may type a shortcut ("3A-02") or a distance ("08"), but the stored placa is
    // the canonical "CALLE 13 # 3A-02" (the npn carries identity). Only an
    // explicit divergence keeps the typed text.
    if (!keepTyped) _placaCtrl.text = hit.direccionNorm;
    // v4: a multi-unit placa has no npn — no per-npn duplicate to check.
    final dup = hit.npn == null
        ? null
        : await ref
            .read(captureRepositoryProvider)
            .npnPosicionInRoute(widget.routeId, hit.npn!);
    if (!mounted) return;
    setState(() {
      _linked = hit;
      _duplicateOfPosicion = dup;
      _suggestions = [];
    });
  }

  /// Spec 13: a soft confirm before anchoring a MIDDLE placa. Returns true to
  /// anchor anyway, false to pick another.
  Future<bool> _confirmMiddleAnchor() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('¿Seguro?'),
        content: const Text(
          'Esta placa no inicia la parada — verifica el sentido de la ruta y '
          'ancla en la placa correcta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Elegir otra'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Anclar igual'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  void _unlink() => setState(() {
        _linked = null;
        _duplicateOfPosicion = null;
      });

  void _markNotInList() => setState(() {
        _notInList = true;
        _linked = null;
        _duplicateOfPosicion = null;
        _suggestions = [];
      });

  /// Spec 10 / AM.8: the predicted door matches — link it in one tap. The worker
  /// never typed the full address (a distance shortcut, or nothing at all before
  /// tapping), so the field takes the full composed direccion; the npn carries
  /// the identity.
  Future<void> _coincide(R1DirectoryData expected) async {
    _placaCtrl.text = expected.direccionNorm;
    final dup = expected.npn == null
        ? null
        : await ref
            .read(captureRepositoryProvider)
            .npnPosicionInRoute(widget.routeId, expected.npn!);
    if (!mounted) return;
    setState(() {
      _linked = expected;
      _duplicateOfPosicion = dup;
      _notInList = false;
      _suggestions = [];
      _predictionDismissed = false;
    });
  }

  /// The predicted door is NOT what is here (Spec 10): dismiss the prediction
  /// for this capture and let the worker enter what they see — the manzana R1
  /// typeahead, or "No está en la lista" (a finding). The anchor does not move,
  /// so the same R1 door is offered again at the next door.
  void _noCoincide() {
    setState(() => _predictionDismissed = true);
    _placaFocus.requestFocus();
  }

  /// Closes the current face (Spec 10). Optimistic-LOCAL (Decision Q1): the
  /// next parada unlocks at once and the mark is queued. PC.4 adds the
  /// foto_obligatoria gate; PC.5 pushes it and reconciles the server verdict
  /// (barrido_fuera_de_orden / foto_obligatoria_pendiente).
  Future<void> _markFaceSwept(String stopId) async {
    await ref.read(paradaRepositoryProvider).markSwept(stopId);
    if (!mounted) return;
    // Spec 16/PL.5: closing a parada returns to the parada list (the route
    // home), where the just-closed parada now reads barrida and the next one
    // is the current 🔵. When there is no list to return to (a route with no
    // paradas / classic flow), advance in place instead.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    setState(() {
      _linked = null;
      _notInList = false;
      _duplicateOfPosicion = null;
      _suggestions = [];
      _predictionDismissed = false;
      _placaCtrl.clear();
    });
  }

  // The example lives OUTSIDE the field (helper), so it is never mistaken for a
  // value; the instruction is the hint INSIDE. "Se guarda tal cual" keeps the
  // raw-text reassurance.
  String get _directoryHelper => _directoryAvailable
      ? 'Ej: CALLE 13 # 3-20 — se guarda tal cual, siempre.'
      : 'Opcional: puede quedar en blanco.';

  @override
  void dispose() {
    _placaCtrl.dispose();
    _obsCtrl.dispose();
    _placaFocus.dispose();
    unawaited(_camera.dispose());
    unawaited(_ocr.dispose());
    super.dispose();
  }

  Future<void> _saveAndNext() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(captureRepositoryProvider);
    try {
      final owner = ref.read(queueOwnerProvider);
      // Snapshot the divergence state BEFORE the form resets (CL-R3).
      final soporte = EvidenceRepository.classifySoporte(
        notInList: _notInList,
        duplicateNpn: _duplicateOfPosicion != null,
        typedPlaca: _placaCtrl.text,
        linkedDireccionNorm: _linked?.direccionNorm,
      );
      // CL-R3 v1.1 — graduated photo obligation, decided AT save:
      // divergence demands the aimed shot; routine draws the 1/N lottery;
      // a CTA shot already taken satisfies both; a dead camera skips all
      // (the ABSENT expected photo is itself the QA signal). Spec 10 PC.4
      // adds a per-route floor: under foto_obligatoria EVERY placa demands
      // the shot too, no lottery escape (Decision 3) — same valve either way.
      XFile? shot = _deliberateShot;
      final lotteryRoll = Random().nextInt(AppConfig.evidenceLotteryOneIn);
      // cameraReady:true — we always ATTEMPT on demand; the hardware valve is
      // handled at capture time (a dead camera returns cameraAvailable:false).
      // Spec 12, BR4: a plate-less lot (es_lote && placa blank) is exempt from
      // the forced photo entirely — never required (it may still be taken via
      // the CTA). A lot WITH a placa falls through to the normal rule.
      final loteExempt = _esLote && _placaCtrl.text.trim().isEmpty;
      final needsAimed = !loteExempt &&
          EvidenceRepository.needsDeliberateShot(
            soporte: soporte,
            cameraReady: true,
            alreadyDeliberate: shot != null,
            lotteryRoll: lotteryRoll,
            fotoObligatoria: ref.read(fotoObligatoriaProvider(widget.routeId)),
          );
      if (needsAimed) {
        final outcome = await _takeDeliberateShot(required: true);
        if (!outcome.cameraAvailable) {
          // Hardware valve: a dead camera NEVER blocks the capture; the
          // absent expected photo is itself the QA signal.
          shot = null;
        } else if (outcome.shot == null) {
          // Camera worked but the worker backed out of a required shot: the
          // save aborts, form intact.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Esta captura requiere la foto de la placa.')));
          }
          return;
        } else {
          shot = outcome.shot;
        }
      }
      // No passive fallback frame: with no persistent camera there is nothing
      // to grab for free. Routine photos are the CTA or the 1/N lottery only.
      if (shot != null && !await _ocrSoftCheck(shot)) {
        // The worker chose "Corregir": abort, keep the form as-is.
        return;
      }
      // Spec 10 / Decisions v2: on an assisted route the parada fixes the
      // manzana and binds by stop_id (§6); block_face_id rides too when the
      // parada has one. Spec 13: bind to the RAW parada (reliable identity +
      // manzana, loaded before the async prediction context), and "rural" (no R1
      // link / finding stored) = a parada with NO manzana; a manzana parada
      // stores npn / sinR1 like any R1 capture.
      final parada = ref.read(currentParadaProvider(widget.routeId));
      final rural =
          parada != null && (parada.manzana?.trim().isEmpty ?? true);
      final clientId = await repo.appendCapture(
        routeId: widget.routeId,
        placa: _placaCtrl.text,
        manzanaCatastral: parada?.manzana,
        tipoAcceso: _tipoAcceso,
        observacion: _obsCtrl.text,
        stopId: parada?.stopId,
        blockFaceId: parada?.blockFaceId,
        // Spec 12: the built state the worker picked (Construido / Sin construir).
        esLote: _esLote,
        // CL4: unsent content belongs to the person who captured it.
        owner: owner,
        // Spec 7: the pair is the record — raw placa above, npn here. v4: a
        // multi-unit placa has no npn (it is null on the linked row).
        npn: rural ? null : _linked?.npn,
        // v4 (Spec 15): a multi-unit placa (npn null) is linked by its
        // direccion_norm instead; a single-unit link uses npn, so this stays null.
        direccionNorm: (!rural && _linked != null && _linked!.npn == null)
            ? _linked!.direccionNorm
            : null,
        // CL-R7: only the EXPLICIT tap asserts it. Typing and saving
        // without opening suggestions says nothing (null) — turning
        // passivity into a "finding" would poison the very indicator. A
        // rural (topónimo) capture has no R1 list to "not be in" at all.
        sinR1: rural ? null : (_notInList ? true : null),
      );
      // The worker walks on while the photo compresses and queues.
      if (shot != null) {
        final evidenceRepo = ref.read(evidenceRepositoryProvider);
        unawaited(_storeEvidence(evidenceRepo, clientId, soporte, owner, shot));
      }
      // Clear for the next household. manzana_catastral is kept (same block).
      _placaCtrl.clear();
      _obsCtrl.clear();
      setState(() {
        _tipoAcceso = null;
        _linked = null;
        _notInList = false;
        _duplicateOfPosicion = null;
        _suggestions = [];
        _deliberateShot = null;
        _predictionDismissed = false; // the next door predicts again
        _esLote = false; // Spec 12: each new capture starts Construido
      });
      _placaFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capturesAsync = ref.watch(capturesProvider(widget.routeId));
    final pending = ref.watch(pendingCountProvider(widget.routeId));
    // Spec 10 PC.4: every placa on this route requires its photo — the CTA
    // label reflects it (PC.2 wireframe) so the mandatory shot at save is
    // never a surprise.
    final fotoObligatoria = ref.watch(fotoObligatoriaProvider(widget.routeId));
    // Spec 10: the guided-sweep context. Null = unassisted route → the classic
    // flow renders unchanged.
    final paradaCtx =
        ref.watch(paradaCaptureContextProvider(widget.routeId)).valueOrNull;
    // Spec 13: the raw parada (identity + manzana) loads before the async
    // prediction context — read the manzana from HERE so the field shape is
    // right immediately, not after the context resolves.
    final rawParada = ref.watch(currentParadaProvider(widget.routeId));
    // Spec 13 robustness: the first keystrokes can land while the parada is
    // still loading — _onPlacaChanged skips the search until the stops load and
    // would otherwise never re-fire (it only runs on a keystroke). When the
    // parada resolves (null → parada), re-run the search for whatever is already
    // typed, so a fast typer isn't left with an empty dropdown.
    ref.listen<Parada?>(currentParadaProvider(widget.routeId), (prev, next) {
      if (prev == null &&
          next != null &&
          !_esLote &&
          _linked == null &&
          !_notInList &&
          _placaCtrl.text.trim().isNotEmpty) {
        _onPlacaChanged(_placaCtrl.text);
      }
    });
    final assisted = paradaCtx != null;
    // "rural" (no R1 concept, free text) = a parada with NO manzana; a manzana —
    // with or without a terna — drives the assisted full-placa anchor flow.
    final rural = rawParada != null &&
        (rawParada.manzana?.trim().isEmpty ?? true);
    final showPrediction = assisted &&
        !_esLote && // Spec 12: a lot has no R1 address to predict/link.
        !_predictionDismissed &&
        _linked == null &&
        !_notInList &&
        _placaCtrl.text.trim().isEmpty &&
        paradaCtx.expectedRow != null;
    // Soft acera check (Spec 10): a typed distance whose parity is the other
    // acera of this face. Only when NOT linked (a link is R1, same parity).
    final faceParity = assisted ? paradaCtx.facePlacaParity : null;
    final typedParity = _typedDistanceParity(_placaCtrl.text);
    final parityMismatch = faceParity != null &&
        _linked == null &&
        typedParity != null &&
        typedParity != faceParity;

    // The placa field's shape depends on the parada (Spec 13 + AM.8): a lote's
    // address is optional; a rural parada (NO manzana) asks for the predio's name
    // (topónimo); AFTER an R1-linked anchor the worker types only the distance
    // (AM.8), composed from the anchor's terna; the first anchor (and the
    // unassisted route) asks for the full placa, searched within the manzana.
    final distanceMode = !_esLote && !rural && paradaCtx?.anchorFace != null;
    final String placaLabel;
    final String? placaHint;
    final String? placaHelper;
    if (_esLote) {
      // Spec 12: a lot's address is optional (empty for a potrero).
      placaLabel = 'Dirección del lote (opcional)';
      placaHint = 'Vacío en potrero';
      placaHelper = 'Si lees la dirección, escríbela; si no, déjala vacía.';
    } else if (rural) {
      placaLabel = 'Nombre del predio';
      placaHint = 'FINCA CANAÁN';
      placaHelper = 'Se guarda tal cual, siempre.';
    } else if (distanceMode) {
      // AM.8: the face is fixed by the anchor — the worker types only the
      // distance; the helper shows the composed preview from the anchor's terna.
      // Once linked, the field holds the full direccion (not a distance), so the
      // preview would double-compose — hide it and let the linked card speak.
      placaLabel = 'Distancia (a la esquina)';
      // Just the number to the corner; the live preview in the helper shows
      // where it lands. Pairs with the anchor field's instruction hint.
      placaHint = 'Ej: 28';
      placaHelper =
          _linked == null ? paradaCtx!.previewFromAnchor(_placaCtrl.text) : null;
    } else {
      placaLabel = 'Placa (dirección en la puerta)';
      // Instruction, not an example (the example is in the helper). This field
      // is the full-placa anchor that starts the parada (or the placa on an
      // unassisted route).
      placaHint = 'Escribe aquí la dirección ancla';
      placaHelper = _directoryHelper;
    }

    // Spec 12, BR4: a plate-less lot (es_lote && placa blank) is exempt from the
    // mandatory photo; a lot WITH a placa behaves like any predio.
    final placaBlank = _placaCtrl.text.trim().isEmpty;
    final fotoRequired = fotoObligatoria && !(_esLote && placaBlank);
    final fotoSubject = _esLote ? 'del lote' : 'de placa';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        bottom: assisted ? _ParadaBar(parada: paradaCtx.parada) : null,
      ),
      body: capturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final last = list.isEmpty ? null : list.last;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TokenWarningBanner(),
                _LastCaptureCard(
                  last: last,
                  total: list.length,
                  predio: last == null ? null : predioDisplayFor(last, list),
                ),
                if (assisted) ...[
                  const SizedBox(height: 16),
                  _FaceContextCard(parada: paradaCtx.parada),
                ],
                const SizedBox(height: 16),
                // Spec 11: the "Siguiente posición" chip is gone — the prediction
                // card guides what's next. Only the queue-status chip remains
                // (visibility; the send control lives in the resume view,
                // Spec 3, BR2).
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      pending == 0 ? Icons.cloud_done : Icons.cloud_upload,
                      size: 18,
                    ),
                    label: Text(
                        pending == 0 ? 'Todo enviado' : '$pending sin enviar'),
                  ),
                ),
                const SizedBox(height: 16),
                // Spec 12: built state — Construido (default) vs Sin construir
                // (= lote). Sin construir makes the placa optional, hides R1, and
                // exempts a plate-less lot from the mandatory photo.
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
                    selected: {_esLote},
                    onSelectionChanged: (sel) => setState(() {
                      _esLote = sel.first;
                      if (_esLote) {
                        // A lot has no R1 link / finding / suggestions.
                        _linked = null;
                        _notInList = false;
                        _suggestions = [];
                        _duplicateOfPosicion = null;
                        _predictionDismissed = false;
                      }
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                // No live viewfinder (battery): a CTA that opens the camera
                // only when tapped, shoots once, and releases it.
                OutlinedButton.icon(
                  onPressed: _takingShot
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final outcome =
                              await _takeDeliberateShot(required: false);
                          if (!mounted) return;
                          if (!outcome.cameraAvailable) {
                            messenger.showSnackBar(const SnackBar(
                                content: Text('Cámara no disponible.')));
                            return;
                          }
                          if (outcome.shot != null) {
                            setState(() => _deliberateShot = outcome.shot);
                          }
                        },
                  icon: _takingShot
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_deliberateShot != null
                          ? Icons.check_circle
                          : Icons.photo_camera),
                  label: Text(_deliberateShot != null
                      ? 'Foto $fotoSubject lista'
                      : fotoRequired
                          ? 'Tomar foto $fotoSubject (requerida)'
                          : _esLote
                              ? 'Tomar foto $fotoSubject (opcional)'
                              : 'Tomar foto $fotoSubject'),
                ),
                if (assisted) ...[
                  const SizedBox(height: 16),
                  // Decision 9: closing is available whenever a parada is
                  // open — never gated on exhausting a prediction, or a
                  // parada with none (rural, or urban before end-of-face)
                  // could never close and the walk would stall.
                  paradaCtx.endOfFace
                      ? _FinParadaCard(
                          onSweep: () =>
                              _markFaceSwept(paradaCtx.parada.stopId),
                        )
                      : _CerrarParadaButton(
                          onSweep: () =>
                              _markFaceSwept(paradaCtx.parada.stopId),
                        ),
                ],
                // Spec 13: anchoring a MIDDLE placa (one before AND one after)
                // leaves the sweep direction unresolved, so nothing is
                // predicted — tell the worker instead of leaving the absence
                // of a prediction unexplained.
                if (paradaCtx?.warning != null) ...[
                  const SizedBox(height: 16),
                  _MidAnchorWarning(message: paradaCtx!.warning!),
                ],
                if (showPrediction) ...[
                  const SizedBox(height: 16),
                  _ExpectedPlacaCard(
                    expected: paradaCtx.expectedRow!.direccionNorm,
                    onCoincide: () => _coincide(paradaCtx.expectedRow!),
                    onNoCoincide: _noCoincide,
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _placaCtrl,
                  focusNode: _placaFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: placaLabel,
                    hintText: placaHint,
                    helperText: placaHelper,
                  ),
                  textInputAction: TextInputAction.next,
                  // setState first so the acera warning / prediction visibility
                  // recompute on every keystroke (the async filter may return
                  // early without one).
                  onChanged: (t) {
                    setState(() {});
                    _onPlacaChanged(t);
                  },
                ),
                if (parityMismatch) ...[
                  const SizedBox(height: 8),
                  _ParityWarningBanner(faceParity: faceParity),
                ],
                if (_duplicateOfPosicion != null) ...[
                  const SizedBox(height: 8),
                  const _DuplicateBanner(),
                ],
                if (_linked != null) ...[
                  const SizedBox(height: 8),
                  _LinkedCard(
                    direccion: _linked!.direccionNorm,
                    typed: _placaCtrl.text,
                    onUnlink: _unlink,
                  ),
                ] else if (_notInList) ...[
                  const SizedBox(height: 8),
                  _NotInListCard(
                      onUndo: () => setState(() => _notInList = false)),
                ] else if (_panelVisible) ...[
                  const SizedBox(height: 8),
                  _SuggestionPanel(
                    suggestions: _suggestions,
                    onNotInList: _markNotInList,
                    onSelect: _select,
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  // Not migrated to `initialValue`: FormFieldState ignores it
                  // after the first build, so the reset in _save() would leave
                  // a stale access type on screen while the stored value is
                  // null. Revisit if the framework starts honouring it.
                  // ignore: deprecated_member_use
                  value: _tipoAcceso,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de acceso (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final e in _tipoAccesoOptions.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _tipoAcceso = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observación (opcional)',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                // The manual manzana field is gone: with the parada model every
                // point is a parada and the manzana is authoritative from the
                // face (Spec 10) — never typed.
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveAndNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Guardar y siguiente'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Card with the last captured placa — the anchor for checking against the
/// door ("does form N correspond to this house?").
class _LastCaptureCard extends StatelessWidget {
  const _LastCaptureCard({
    required this.last,
    required this.total,
    this.predio,
  });
  final Capture? last;
  final int total;

  /// Spec 11: the per-parada number of [last] (null when there is none yet).
  final PredioDisplay? predio;

  @override
  Widget build(BuildContext context) {
    if (last == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aún no hay capturas en esta ruta. '
              'El primer predio será el 1.'),
        ),
      );
    }
    final placa = last!.placa?.trim();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text('Última capturada ·',
                    style: Theme.of(context).textTheme.labelMedium),
                if (predio != null) PredioNumber(display: predio!),
                Text('· total $total',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              (placa == null || placa.isEmpty) ? '(sin placa)' : placa,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  last!.syncStatus == 'synced'
                      ? Icons.cloud_done
                      : Icons.cloud_upload,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  last!.syncStatus == 'synced'
                      ? 'sincronizada · loc ${last!.loc ?? '—'}'
                      : 'pendiente de sincronizar',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel that filters the R1 directory as the worker types (CL-R1).
/// "No está en la lista" is a FIXED FIRST ROW with the same tap size as any
/// suggestion — never a small link, never at the bottom.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.onNotInList,
    required this.onSelect,
  });

  final List<R1DirectoryData> suggestions;
  final VoidCallback onNotInList;
  final ValueChanged<R1DirectoryData> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: Text(
              'No está en la lista',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text('Lo que ves manda. Queda como hallazgo.'),
            onTap: onNotInList,
          ),
          const Divider(height: 1),
          for (final hit in suggestions)
            ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(hit.direccionNorm),
              subtitle: hit.manzana == null
                  ? null
                  : Text('R1 · manzana …${_tail(hit.manzana!)}'),
              onTap: () => onSelect(hit),
            ),
        ],
      ),
    );
  }

  static String _tail(String s) =>
      s.length <= 3 ? s : s.substring(s.length - 3);
}

/// The pair, both halves visible (CL-R1 hard rule: selecting never
/// overwrites the typed placa). The NPN itself is never shown.
class _LinkedCard extends StatelessWidget {
  const _LinkedCard({
    required this.direccion,
    required this.typed,
    required this.onUnlink,
  });

  final String direccion;
  final String typed;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text('Enlazada a: $direccion'),
        subtitle: Text('Tú escribiste: "$typed" — se guardan las dos.'),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Quitar enlace',
          onPressed: onUnlink,
        ),
      ),
    );
  }
}

/// First-class outcome, not an error state (doctrine).
class _NotInListCard extends StatelessWidget {
  const _NotInListCard({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.flag, color: theme.colorScheme.onErrorContainer),
        title: Text('No está en la lista',
            style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        subtitle: Text(
          'Se captura tal cual y queda como hallazgo del censo.',
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.onErrorContainer),
          tooltip: 'Deshacer',
          onPressed: onUndo,
        ),
      ),
    );
  }
}

/// CL-R3 trigger 5: warns, never blocks (PH legitimately share an NPN).
class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.copy_all, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                // Spec 11: no posición locator; the duplicate is findable in the
                // resume list. The warning still conveys "already used, can go on".
                'Esa dirección ya se usó en esta ruta. '
                'Puedes continuar — varias unidades pueden compartirla (PH).',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The parity of the distance the worker typed (0 = par, 1 = impar), read from
/// the LAST integer run in the text — the placa/distance sits at the end of an
/// address ("… # 2-15" → 15) whether they typed a fragment or the whole thing.
/// Null when there is no number yet.
int? _typedDistanceParity(String typed) {
  final matches = RegExp(r'\d+').allMatches(typed);
  if (matches.isEmpty) return null;
  return int.parse(matches.last.group(0)!) % 2;
}

String _parityLabel(int parity) => parity == 0 ? 'par' : 'impar';

/// Spec 10: the typed distance looks like the OTHER acera of this face. A soft
/// warning only — the worker may be on the wrong side or the plate may be odd;
/// either way it is saved as-is ("se guarda tal cual").
class _ParityWarningBanner extends StatelessWidget {
  const _ParityWarningBanner({required this.faceParity});

  final int faceParity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final other = faceParity == 0 ? 1 : 0;
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.rule, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Esta parada es ${_parityLabel(faceParity)}, pero la distancia '
                'que escribiste es ${_parityLabel(other)}. Revisa la acera — se '
                'guarda igual.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spec 13: the anchor is a MIDDLE placa (one before AND one after), so the
/// sweep direction cannot be inferred and the app does not predict the next
/// placa. A soft heads-up — the worker can still capture by hand; anchoring at
/// an end of the parada restores the prediction.
class _MidAnchorWarning extends StatelessWidget {
  const _MidAnchorWarning({required this.message});

  /// e.g. "esta placa no inicia la parada" (from face_prediction).
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = message.isEmpty
        ? message
        : '${message[0].toUpperCase()}${message.substring(1)}';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    'Tiene direcciones antes y después, así que no se predice la '
                    'siguiente. Ancla en un extremo de la parada o captura a mano.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _orientationLabel(String? code) {
  if (code == null || code.isEmpty) return null;
  const map = {
    'N': 'Norte',
    'S': 'Sur',
    'E': 'Este',
    'O': 'Oeste',
    'W': 'Oeste',
  };
  return map[code.toUpperCase()] ?? code;
}

/// Spec 10: the parada context strip under the app bar — face + manzana +
/// direction, so the worker always knows which face they are sweeping.
class _ParadaBar extends StatelessWidget implements PreferredSizeWidget {
  const _ParadaBar({required this.parada});

  final Parada parada;

  @override
  Size get preferredSize => const Size.fromHeight(26);

  @override
  Widget build(BuildContext context) {
    final orient = _orientationLabel(parada.orientation);
    final parts = <String>[
      // Always "Parada" in the worker-facing label — the surveyor walks
      // "paradas"; "cara" is office/cadastral jargon (Jorge 2026-10-03).
      'Parada ${parada.faceSequence}',
      // The manzana lives on the readable face card below (Zona · Mz · ref),
      // so the pinned strip drops it — no raw 17-digit código, no duplication.
      if (orient != null) orient,
      if (parada.direction != null) parada.direction!,
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(parts.join(' · '),
            style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

/// Spec 10/11: the parada's manzana, authoritative and read-only — never a field.
/// Urban vs rural is read from the manzana's ZONA (the código), not from terna
/// presence: a parada WITH a manzana shows "Zona: X · Mz N" even if its terna
/// was not seeded; only a parada with NO manzana shows the topónimo card.
class _FaceContextCard extends ConsumerWidget {
  const _FaceContextCard({required this.parada});

  final Parada parada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manzana = parada.manzana?.trim();
    // Spec 11 follow-up: the urban/rural signal is the manzana's ZONA
    // (Urbana/Rural/Centro poblado, read from the código by manzanaLabel), NOT
    // terna presence — a missing terna is a backend SEED GAP and must not
    // mislabel an urban predio as rural. The topónimo card is ONLY for a point
    // with no cadastral manzana at all.
    if (manzana == null || manzana.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: const Icon(Icons.cottage_outlined),
          title: Text('Parada ${parada.faceSequence} · predio rural'),
          subtitle: Text(
            'Sin manzana catastral — escribe el nombre del predio.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    final orient = _orientationLabel(parada.orientation);
    // Always "parada" in the worker-facing label — "cara" is office/cadastral
    // jargon (Jorge 2026-10-03). The zona (Urbana/Rural) still comes from the
    // manzana código via manzanaLabel.
    // PC.6: readable manzana (Zona: X · Mz N) + its best-effort geo reference.
    final label = manzanaLabel(manzana);
    final geoRef = ref.watch(manzanaRefGeograficaProvider(manzana)).valueOrNull;
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: const Icon(Icons.grid_4x4),
        title: Text(
          '$label · parada ${parada.faceSequence}'
          '${orient == null ? '' : ' ($orient)'}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (geoRef != null && geoRef.isNotEmpty)
              Text('📍 ref: $geoRef', style: theme.textTheme.bodySmall),
            Text('La manzana la fija la parada — no se escribe.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Spec 10 PC.3: the predicted next placa — confirm it, or flag "No coincide"
/// and enter what is really there.
class _ExpectedPlacaCard extends StatelessWidget {
  const _ExpectedPlacaCard({
    required this.expected,
    required this.onCoincide,
    required this.onNoCoincide,
  });

  final String expected;
  final VoidCallback onCoincide;
  final VoidCallback onNoCoincide;

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
                  color: theme.colorScheme.onSecondaryContainer,
                )),
            const SizedBox(height: 4),
            Text(expected,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCoincide,
                    icon: const Icon(Icons.check),
                    label: const Text('Coincide'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNoCoincide,
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

/// Decision 9: closing must be available whenever a parada is open — mid-face
/// on a guided one, or ALWAYS on a rural one (which has no prediction to
/// exhaust, so this is its ONLY way to close and unlock the next parada). A
/// plain action, not a card: it is not announcing "you're done" the way
/// [_FinParadaCard] does, just always offering the door.
class _CerrarParadaButton extends StatelessWidget {
  const _CerrarParadaButton({required this.onSweep});

  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onSweep,
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: const Text('Cerrar esta parada'),
      ),
    );
  }
}

/// Spec 10: the prediction is exhausted for this face. The worker may still
/// capture a straggler the R1 never knew (a finding), then close the face —
/// which unlocks the next parada. Closing is optimistic-local (PC.3); PC.4
/// adds the foto_obligatoria gate and PC.5 the server reconcile.
class _FinParadaCard extends StatelessWidget {
  const _FinParadaCard({required this.onSweep});

  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.done_all,
                  color: theme.colorScheme.onSecondaryContainer),
              title: Text('Fin de la parada',
                  style:
                      TextStyle(color: theme.colorScheme.onSecondaryContainer)),
              subtitle: Text(
                'No hay más direcciones esperadas. Si ves una puerta que la '
                'lista no tiene, captúrala como hallazgo; si no, cierra la parada.',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onSweep,
              icon: const Icon(Icons.flag),
              label: const Text('Marcar parada barrida'),
            ),
            const SizedBox(height: 4),
            Text('Desbloquea la siguiente parada.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                )),
          ],
        ),
      ),
    );
  }
}
