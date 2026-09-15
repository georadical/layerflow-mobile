import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address/address_normalizer.dart';
import '../../core/config/app_config.dart';
import '../../data/db/database.dart';
import '../../data/repositories/capture_repository.dart';
import '../providers.dart';
import '../widgets/confirm_exact_plate.dart';

const _tipoAccesoLabels = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común',
  'otro': 'Otro',
};

/// Human name for a row's anchor: the placa of the unit whose loc matches,
/// "el inicio de la ruta" for 0, or the bare loc when the anchor is not on
/// this device (set elsewhere, or dangling).
String anchorLabel(List<Capture> rows, String excludeClientId, int target) {
  if (target == 0) return 'el inicio de la ruta';
  for (final r in rows) {
    if (r.clientId == excludeClientId) continue;
    if (CaptureRepository.anchorLoc(r) == target) {
      final placa = r.placa?.trim();
      return (placa == null || placa.isEmpty)
          ? 'la unidad ${r.posicion}'
          : placa;
    }
  }
  // Anchor not on this device: set elsewhere, or dangling after a rejection.
  return 'loc $target';
}

/// Full-screen editor for one captured unit (replaces the Spec 1.1 dialog).
///
/// Why a screen and not a modal any more: Spec 7 outgrew the dialog —
/// correcting a placa in the urban core is exactly the moment to re-check
/// against the R1 (typeahead) and manage the door link, and none of that
/// fits a dialog that shifts under the keyboard.
///
/// Rules preserved from the dialog, all tested at the repository level:
/// - `posicion` shown, never editable (BR1); loc shown is anchorLoc.
/// - `manzana_catastral` preserved untouched (full-replacement trap).
/// - editCapture leaves ins_after and npn alone; each change is its own
///   deliberate step (A3 and the provenance rule: only a CHANGED npn is a
///   field decision — an untouched link is re-carried, never re-stamped).
class EditUnitScreen extends ConsumerStatefulWidget {
  const EditUnitScreen({super.key, required this.row, required this.allRows});

  final Capture row;

  /// The whole route, for the anchor picker and anchor naming.
  final List<Capture> allRows;

  @override
  ConsumerState<EditUnitScreen> createState() => _EditUnitScreenState();
}

class _EditUnitScreenState extends ConsumerState<EditUnitScreen> {
  late final TextEditingController _placa;
  late final TextEditingController _obs;
  String? _tipo;
  int? _insAfter;
  bool _insAfterChanged = false;

  // Door link (Spec 7). _npn mirrors what WILL be stored; the label names
  // it for the worker (address, never the npn value).
  String? _npn;
  String? _linkedLabel;

  /// CL-R7: the finding can also be asserted here — a worker who realises
  /// it later must not be mute. Distinct from UNLINKING, which only means
  /// "this link was wrong".
  bool _sinR1 = false;
  List<R1DirectoryData> _suggestions = [];
  bool _directoryAvailable = false;
  int _searchSeq = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _placa = TextEditingController(text: widget.row.placa ?? '');
    _obs = TextEditingController(text: widget.row.observacion ?? '');
    _tipo = widget.row.tipoAcceso;
    _insAfter = widget.row.insAfter;
    _npn = widget.row.npn;
    _sinR1 = widget.row.sinR1;
    Future.microtask(() async {
      final tenantId = ref.read(activeTenantIdProvider);
      if (tenantId == null) return;
      final repo = ref.read(r1DirectoryRepositoryProvider);
      final count = await repo.countFor(tenantId);
      String? label;
      final npn = _npn;
      if (npn != null) {
        final hit = await repo.byNpn(tenantId, npn);
        // The link may point outside the local slice (linked elsewhere,
        // directory reloaded): still shown as linked, just unnamed.
        label = hit?.direccionNorm ?? 'dirección del R1';
      }
      if (mounted) {
        setState(() {
          _directoryAvailable = count > 0;
          _linkedLabel = label;
        });
      }
    });
  }

  @override
  void dispose() {
    _placa.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _onPlacaChanged(String text) async {
    if (_npn != null || !_directoryAvailable) return;
    final tenantId = ref.read(activeTenantIdProvider);
    if (tenantId == null) return;
    final seq = ++_searchSeq;
    final mz = widget.row.manzanaCatastral?.trim();
    final hits = await ref.read(r1DirectoryRepositoryProvider).search(
          tenantId,
          text,
          manzana: (mz == null || mz.isEmpty) ? null : mz,
        );
    if (!mounted || seq != _searchSeq) return;
    setState(() => _suggestions = hits);
  }

  /// CL-R1 v1.1: linking with an incomplete typed placa asks for the
  /// explicit confirmation; "Sí" copies the R1 text (affirmed
  /// observation), "No" keeps the typed text, dismissing links nothing.
  Future<void> _link(R1DirectoryData hit) async {
    final typedComplete = normalizeAddress(_placa.text).direccionNorm != null;
    if (!typedComplete) {
      final saysExactly = await confirmExactPlate(context, hit.direccionNorm);
      if (saysExactly == null || !mounted) return;
      if (saysExactly) _placa.text = hit.direccionNorm;
    }
    setState(() {
      _npn = hit.npn;
      _linkedLabel = hit.direccionNorm;
      _sinR1 = false; // linking supersedes the assertion
      _suggestions = [];
    });
  }

  void _unlink() => setState(() {
        _npn = null;
        _linkedLabel = null;
      });

  /// Opens the anchor picker. The number that travels as `ins_after` is
  /// derived from the unit the worker points at, never typed (BR1/BR2).
  Future<void> _pickAnchor() async {
    final choice = await showDialog<_AnchorChoice>(
      context: context,
      builder: (_) => _AnchorPicker(
        candidates: [
          for (final r in widget.allRows)
            if (r.clientId != widget.row.clientId) r,
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.loc > 9999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esa unidad queda fuera del rango permitido.')));
      return;
    }
    setState(() {
      _insAfter = choice.loc;
      _insAfterChanged = true;
    });
    if (choice.anchorRefused) {
      // A5: warn, never block.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ojo: esa unidad fue rechazada por el servidor. '
            'La oficina no podrá aplicar el movimiento hasta corregirla.'),
      ));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(captureRepositoryProvider);
      final owner = ref.read(queueOwnerProvider);
      await repo.editCapture(
        clientId: widget.row.clientId,
        placa: _placa.text,
        tipoAcceso: _tipo,
        // Not editable here (it belongs to capture, set per block), but it
        // must be preserved: the push is full-replacement.
        manzanaCatastral: widget.row.manzanaCatastral,
        observacion: _obs.text,
        owner: owner,
      );
      if (_npn != widget.row.npn) {
        // Provenance rule: only a CHANGED link is a field decision.
        await repo.setNpn(
            clientId: widget.row.clientId, npn: _npn, owner: owner);
      }
      if (_sinR1 != widget.row.sinR1) {
        await repo.setSinR1(
            clientId: widget.row.clientId, sinR1: _sinR1, owner: owner);
      }
      if (_insAfterChanged) {
        if (_insAfter == null) {
          await repo.clearInsAfter(widget.row.clientId, owner: owner);
        } else {
          await repo.setInsAfter(
              clientId: widget.row.clientId,
              insAfter: _insAfter!,
              owner: owner);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // posicion is shown, never editable (BR1); the loc shown is the
        // row's effective one (anchorLoc).
        title: Text(
          'Posición ${widget.row.posicion} · '
          'Loc ${CaptureRepository.anchorLoc(widget.row)}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _placa,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Placa (dirección en la puerta)',
              helperText: _directoryAvailable
                  ? 'Escribe lo que VES. Se guarda tal cual, siempre.'
                  : 'Opcional: puede quedar en blanco.',
            ),
            onChanged: _onPlacaChanged,
          ),
          if (_npn != null) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.link),
                title: Text('Enlazada a: ${_linkedLabel ?? '…'}'),
                subtitle: const Text('Quitar el enlace es decisión de campo; '
                    'viaja en el próximo envío.'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar enlace',
                  onPressed: _unlink,
                ),
              ),
            ),
          ] else if (_sinR1) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading:
                    Icon(Icons.flag, color: theme.colorScheme.onErrorContainer),
                title: Text('No está en la lista',
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer)),
                subtitle: Text(
                  'Declarada como hallazgo del censo: no existe en el R1.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close,
                      color: theme.colorScheme.onErrorContainer),
                  tooltip: 'Deshacer',
                  onPressed: () => setState(() => _sinR1 = false),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            // The assertion is available even with no suggestions on
            // screen: realising it later must never leave the worker mute.
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _sinR1 = true;
                _suggestions = [];
              }),
              icon: Icon(Icons.block, color: theme.colorScheme.error),
              label: Text(
                'No está en la lista',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
          if (_npn == null && !_sinR1 && _suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final hit in _suggestions)
                    ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(hit.direccionNorm),
                      subtitle: const Text('R1'),
                      onTap: () => _link(hit),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            // Not migrated to `initialValue`: FormFieldState ignores it
            // after the first build, and this rebuilds on every selection.
            // ignore: deprecated_member_use
            value: _tipo,
            decoration: const InputDecoration(
              labelText: 'Tipo de acceso (opcional)',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final e in _tipoAccesoLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _tipo = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _obs,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          // Spec 2.1: the answer to the question the append-only note
          // raises — "what if I put it in the wrong place?".
          _RelocateRow(
            anchorLabel: _insAfter == null
                ? null
                : anchorLabel(widget.allRows, widget.row.clientId, _insAfter!),
            onPick: _pickAnchor,
            onClear: () => setState(() {
              _insAfter = null;
              _insAfterChanged = true;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'La posición no se puede cambiar (append-only).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
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
            label: const Text('Guardar'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

/// What the anchor picker hands back. [loc] is what travels as `ins_after`;
/// [anchorRefused] triggers the dangling-anchor warning (A5).
class _AnchorChoice {
  const _AnchorChoice({required this.loc, this.anchorRefused = false});
  final int loc;
  final bool anchorRefused;
}

/// Entry to "Mover localización": shows the current anchor or invites
/// setting one. "Quitar" appears only when there is a mark.
class _RelocateRow extends StatelessWidget {
  const _RelocateRow({
    required this.anchorLabel,
    required this.onPick,
    required this.onClear,
  });

  final String? anchorLabel;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = anchorLabel != null;

    return InkWell(
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.low_priority,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mover localización', style: theme.textTheme.bodyLarge),
                  Text(
                    marked
                        ? 'Va tras $anchorLabel'
                        : 'Va al final del recorrido',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (marked)
              TextButton(onPressed: onClear, child: const Text('Quitar')),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Anchor picker. The worker points at a unit — placa and posicion on show —
/// and the loc that travels as `ins_after` is derived (BR1/BR2). There is no
/// numeric field anywhere.
class _AnchorPicker extends StatelessWidget {
  const _AnchorPicker({required this.candidates});

  /// The route's units, already excluding the one being moved.
  final List<Capture> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('¿Después de cuál va?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('Al inicio de la ruta'),
              onTap: () => Navigator.pop(context, const _AnchorChoice(loc: 0)),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            for (final r in candidates)
              ListTile(
                title: Text(
                  (r.placa?.trim().isNotEmpty ?? false)
                      ? r.placa!.trim()
                      : 'Sin dirección aún',
                  style: (r.placa?.trim().isNotEmpty ?? false)
                      ? null
                      : const TextStyle(fontStyle: FontStyle.italic),
                ),
                // The loc shown is the very value that will travel as
                // ins_after — never a second, different number.
                subtitle: Text(
                    'posición ${r.posicion} · loc ${CaptureRepository.anchorLoc(r)}'),
                onTap: () => Navigator.pop(
                  context,
                  _AnchorChoice(
                    loc: CaptureRepository.anchorLoc(r),
                    anchorRefused: r.syncStatus == AppConfig.syncError,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
