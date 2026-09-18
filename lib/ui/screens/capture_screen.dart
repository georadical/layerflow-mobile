import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address/address_normalizer.dart';
import '../../core/config/app_config.dart';
import '../../core/camera/plate_camera.dart';
import '../../core/ocr/plate_ocr.dart';
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
  final _manzanaCtrl = TextEditingController();
  final _placaFocus = FocusNode();
  String? _tipoAcceso;
  bool _saving = false;
  bool _showAdvanced = false;

  // R1-assisted capture (Spec 7). The typeahead only exists where a
  // directory exists; rural / paste-flow capture stays classic.
  List<R1DirectoryData> _suggestions = [];
  R1DirectoryData? _linked;
  bool _notInList = false;
  int? _duplicateOfPosicion;
  bool _directoryAvailable = false;
  int _searchSeq = 0;

  /// CL-R6: the manzana's R1 rows are all linked already. Named in the
  /// POSITIVE — an empty panel reads as "broken / wrong manzana" and the
  /// worker either forces another block (poisons the data) or skips the
  /// doors (loses exactly what the census is for).
  bool _manzanaExhausted = false;

  Future<void> _refreshManzanaState() async {
    final tenantId = ref.read(activeTenantIdProvider);
    final mz = _manzanaCtrl.text.trim();
    if (tenantId == null || mz.isEmpty) {
      if (mounted && _manzanaExhausted) {
        setState(() => _manzanaExhausted = false);
      }
      return;
    }
    final stats = await ref
        .read(r1DirectoryRepositoryProvider)
        .manzanaStats(tenantId, mz);
    if (!mounted) return;
    setState(() => _manzanaExhausted = stats.total > 0 && stats.free == 0);
  }

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
      await _refreshManzanaState();
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
  Future<void> _onPlacaChanged(String text) async {
    if (_linked != null || _notInList || !_directoryAvailable) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId == null) return;
    final seq = ++_searchSeq;
    // CL-R1 v1.2: the current manzana (persisted per block; later fed by
    // "paradas" with zero change here) scopes the placa-only mode.
    final mz = _manzanaCtrl.text.trim();
    final hits = await ref.read(r1DirectoryRepositoryProvider).search(
          tenantId,
          text,
          manzana: mz.isEmpty ? null : mz,
        );
    if (!mounted || seq != _searchSeq) return;
    // setState even when empty: the panel must show "No está en la lista"
    // for text that matches NOTHING — the most divergent case of all is
    // exactly where that action must stay one tap away (CL-R1).
    setState(() => _suggestions = hits);
  }

  bool get _panelVisible =>
      _directoryAvailable &&
      _linked == null &&
      !_notInList &&
      _placaCtrl.text.trim().isNotEmpty;

  /// Links the unit to the tapped R1 address. The NPN rides hidden. A
  /// second use of the same NPN in the route warns and marks divergence —
  /// never blocks (CL-R3 trigger 5, PH share).
  ///
  /// CL-R1 v1.1: with an INCOMPLETE typed placa the app asks whether the
  /// physical plate reads exactly the R1 text. "Sí" copies it (affirmed
  /// observation, rutina); "No" keeps the typed text (legitimate
  /// divergence); dismissing links nothing. Silent overwrite stays
  /// forbidden.
  Future<void> _select(R1DirectoryData hit) async {
    // v1.2: full match OR cruce-placa part match ("3A 08" is literally
    // what the door says) counts as coincidente — no dialog.
    final matches = typedMatchesLinked(_placaCtrl.text, hit.direccionNorm);
    if (!matches) {
      final saysExactly = await confirmExactPlate(context, hit.direccionNorm);
      if (saysExactly == null || !mounted) return; // dismissed: no link
      if (saysExactly) _placaCtrl.text = hit.direccionNorm;
    }
    final dup = await ref
        .read(captureRepositoryProvider)
        .npnPosicionInRoute(widget.routeId, hit.npn);
    if (!mounted) return;
    setState(() {
      _linked = hit;
      _duplicateOfPosicion = dup;
      _suggestions = [];
    });
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

  String get _directoryHelper => _directoryAvailable
      ? 'Escribe lo que VES. Se guarda tal cual, siempre.'
      : 'Opcional: puede quedar en blanco.';

  @override
  void dispose() {
    _placaCtrl.dispose();
    _obsCtrl.dispose();
    _manzanaCtrl.dispose();
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
      // (the ABSENT expected photo is itself the QA signal).
      XFile? shot = _deliberateShot;
      final lotteryRoll = Random().nextInt(AppConfig.evidenceLotteryOneIn);
      // cameraReady:true — we always ATTEMPT on demand; the hardware valve is
      // handled at capture time (a dead camera returns cameraAvailable:false).
      final needsAimed = EvidenceRepository.needsDeliberateShot(
        soporte: soporte,
        cameraReady: true,
        alreadyDeliberate: shot != null,
        lotteryRoll: lotteryRoll,
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
      final clientId = await repo.appendCapture(
        routeId: widget.routeId,
        placa: _placaCtrl.text,
        manzanaCatastral: _manzanaCtrl.text,
        tipoAcceso: _tipoAcceso,
        observacion: _obsCtrl.text,
        // CL4: unsent content belongs to the person who captured it.
        owner: owner,
        // Spec 7: the pair is the record — raw placa above, npn here.
        npn: _linked?.npn,
        // CL-R7: only the EXPLICIT tap asserts it. Typing and saving
        // without opening suggestions says nothing (null) — turning
        // passivity into a "finding" would poison the very indicator.
        sinR1: _notInList ? true : null,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
      ),
      body: capturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final last = list.isEmpty ? null : list.last;
          final nextPosicion = (last?.posicion ?? 0) + 1;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TokenWarningBanner(),
                _LastCaptureCard(last: last, total: list.length),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Chip(
                      avatar: const Icon(Icons.tag, size: 18),
                      label: Text('Siguiente posición: $nextPosicion'),
                    ),
                    const SizedBox(width: 8),
                    // Queue visibility only (Spec 2, T2.1): the single send
                    // control stays in the resume view (Spec 3, BR2).
                    Chip(
                      avatar: Icon(
                        pending == 0 ? Icons.cloud_done : Icons.cloud_upload,
                        size: 18,
                      ),
                      label: Text(pending == 0
                          ? 'Todo enviado'
                          : '$pending sin enviar'),
                    ),
                  ],
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
                      ? 'Foto de placa lista'
                      : 'Tomar foto de placa'),
                ),
                if (_manzanaExhausted) ...[
                  const SizedBox(height: 16),
                  const _DiscoveryBanner(),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _placaCtrl,
                  focusNode: _placaFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Placa (dirección en la puerta)',
                    hintText: 'C 5 1 11',
                    helperText: _directoryHelper,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: _onPlacaChanged,
                ),
                if (_duplicateOfPosicion != null) ...[
                  const SizedBox(height: 8),
                  _DuplicateBanner(posicion: _duplicateOfPosicion!),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(
                        _showAdvanced ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Manzana catastral (opcional)'),
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                  ),
                ),
                if (_showAdvanced)
                  TextField(
                    controller: _manzanaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Manzana catastral',
                      helperText:
                          'Se conserva entre capturas del mismo bloque.',
                    ),
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\n')),
                    ],
                    onChanged: (_) => _refreshManzanaState(),
                  ),
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
  const _LastCaptureCard({required this.last, required this.total});
  final Capture? last;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (last == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aún no hay capturas en esta ruta. '
              'La primera será la posición 1.'),
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
            Text('Última capturada · posición ${last!.posicion} · total $total',
                style: Theme.of(context).textTheme.labelMedium),
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
  const _DuplicateBanner({required this.posicion});

  final int posicion;

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
                'Esa dirección ya se usó en esta ruta (posición $posicion). '
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

/// CL-R6 discovery mode: every R1 address of this manzana is already
/// linked. Three different realities share that symptom (faces without
/// plates, doors the R1 never knew, bad earlier links) and the app must
/// not presume which — but the second one is the most valuable thing the
/// census produces, so the state is named in the positive and capture is
/// never discouraged.
class _DiscoveryBanner extends StatelessWidget {
  const _DiscoveryBanner();

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
            Icon(Icons.explore, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todas las direcciones del R1 de esta manzana ya están '
                'enlazadas. Lo que encuentres aquí es nuevo — captúralo.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
