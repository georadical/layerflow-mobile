import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address/manzana_label.dart';
import '../../core/config/app_config.dart';
import '../../core/parada/face_prediction.dart' show composeParadaAddress;
import '../../core/parada/predio_sequence.dart';
import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
import '../../data/repositories/capture_repository.dart';
import '../../data/repositories/survey_repository.dart';
import '../providers.dart';
import '../widgets/predio_number.dart';
import '../widgets/send_bar.dart';
import '../widgets/sweep_rejected_banner.dart';
import 'capture_screen.dart';
import 'edit_unit_screen.dart';
import 'settings_screen.dart';
import 'survey_screen.dart';

/// Resume view — Spec 1, T1.6/T1.7. Read-only list of what the route already
/// has, with the address leading (BR5).
///
/// It reads the local captures rather than the server response directly, so
/// rows still queued on the device appear next to the synced ones instead of
/// vanishing when the frame arrives (BR3).
class ResumeRouteScreen extends ConsumerWidget {
  const ResumeRouteScreen({
    super.key,
    required this.routeId,
    this.codigo,
  });

  final String routeId;
  final String? codigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = ref.watch(routeFrameProvider(routeId));
    final captures = ref.watch(capturesProvider(routeId));
    final online = ref.watch(isOnlineProvider);

    // The selector knows the codigo already; the other entry paths recover it
    // from the device once the frame has been merged.
    final routeCodigo =
        codigo ?? ref.watch(routeCodigoProvider(routeId)).valueOrNull;
    final esp = ref.watch(espNameProvider).valueOrNull;
    // Spec 9: the placa pass can be closed by the office. Fail-open — only an
    // explicit 'cerrada' disables capture.
    final placasClosed = ref.watch(placasClosedProvider(routeId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routeLabel(codigo: routeCodigo, esp: esp),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Closed: the button reads as a lock and its tap explains why, rather
        // than opening a capture the server would refuse with 409.
        onPressed: placasClosed
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'La oficina cerró la captura de placas en esta ruta.'),
                  ),
                )
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CaptureScreen(routeId: routeId)),
                ),
        backgroundColor:
            placasClosed ? theme.colorScheme.surfaceContainerHighest : null,
        foregroundColor:
            placasClosed ? theme.colorScheme.onSurfaceVariant : null,
        icon: Icon(placasClosed ? Icons.lock_outline : Icons.add),
        label: Text(placasClosed ? 'Captura cerrada' : 'Capturar'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(routeFrameProvider(routeId).future),
        child: switch ((frame, captures)) {
          // A failed pull only blocks when there is nothing local to fall back
          // on; otherwise the captures already on the device are still useful.
          (AsyncError(:final error), _)
              when captures.valueOrNull?.isEmpty ?? true =>
            _errorView(context, error),
          (AsyncLoading(), AsyncData(value: final rows)) when rows.isEmpty =>
            const _Loading(),
          (_, AsyncLoading()) => const _Loading(),
          (_, AsyncError(:final error)) => _errorView(context, error),
          (_, AsyncData(value: final rows)) => rows.isEmpty
              ? const _Empty()
              : _UnitList(
                  rows: rows,
                  // Says plainly that nothing was pulled, instead of implying
                  // the list reflects the server.
                  stale: !online || frame is AsyncError,
                ),
          _ => const _Loading(),
        },
      ),
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    void openSettings() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );

    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
          return _Message(
            icon: Icons.lock_outline,
            title: 'Token vencido o inválido.',
            body: 'Renuévalo en Ajustes.',
            action: 'Ajustes',
            onAction: openSettings,
          );
        case 403:
          return _Message(
            icon: Icons.block,
            title: 'Ese token no es de campo.',
            body: 'Pide un field_token al operador.',
            action: 'Ajustes',
            onAction: openSettings,
          );
        case 404:
          return const _Message(
            icon: Icons.wrong_location,
            title: 'Esa ruta no existe o no es de tu ESP.',
            body: 'Vuelve a Mis rutas y elige otra.',
          );
      }
    }
    return const _Message(
      icon: Icons.cloud_off,
      title: 'Sin conexión con el backend.',
      body: 'Se muestra lo que haya guardado en el dispositivo.',
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Trayendo lo capturado…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const _Message(
      icon: Icons.location_off,
      title: 'Ruta sin capturas aún.',
      body: 'Empieza a capturar la primera dirección del recorrido.',
    );
  }
}

/// Shared shape for empty and error states, inside a scrollable so the pull
/// gesture keeps working when there is no list to pull on.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 40, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: onAction, child: Text(action!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitList extends StatelessWidget {
  const _UnitList({required this.rows, required this.stale});

  final List<Capture> rows;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // clears the FAB
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant,
      ),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            children: [
              _FrameSummary(total: rows.length, stale: stale),
              // Only when there is something to send: a fully sent route
              // carries no dead control (Spec 3, BR2). Photos count too —
              // a routine one waits for WiFi and outlives its queue row,
              // and without this the bar vanished with it (E2E finding).
              SendBar(routeId: rows.first.routeId),
              // Spec 10 PC.5: a sweep the server rejected surfaces HERE, not on
              // the capture screen — the optimistic walk already moved past the
              // face, so this is where the worker can see why it did not close
              // and reopen it to fix (E2E finding).
              SweepRejectedBanner(routeId: rows.first.routeId),
            ],
          );
        }
        return _UnitTile(row: rows[i - 1], allRows: rows);
      },
    );
  }
}

class _FrameSummary extends StatelessWidget {
  const _FrameSummary({required this.total, required this.stale});

  final int total;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total direcciones capturadas',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            stale ? 'sin reanudar (offline)' : 'reanudado',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One captured row in the route's list: the address leads (BR5); the row
/// opens the editor (Spec 1.1). Shows its sync badge and any server reason.
class _UnitTile extends ConsumerWidget {
  const _UnitTile({required this.row, required this.allRows});

  final Capture row;

  /// The whole route, for naming this row's anchor and for the picker.
  final List<Capture> allRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Spec 10: the stored placa is the DISTANCE only on a guided parada; show
    // the full composed address (vía + generadora + distancia + cardinal),
    // mirroring the backend's compose-on-read, so the list is readable — not a
    // column of bare numbers. Rural/classic captures have no terna and show
    // their stored text verbatim (a topónimo or a full typed address).
    final rawPlaca = row.placa?.trim();
    final stops = ref.watch(routeStopsProvider(row.routeId)).valueOrNull;
    Parada? parada;
    if (row.stopId != null && stops != null) {
      for (final p in stops) {
        if (p.stopId == row.stopId) {
          parada = p;
          break;
        }
      }
    }
    final placa = (rawPlaca == null || rawPlaca.isEmpty || parada == null)
        ? rawPlaca
        : composeParadaAddress(
            tipoVia: parada.tipoVia,
            numVia: parada.numVia,
            numCruce: parada.numCruce,
            cardinal: parada.cardinal,
            cardinalPosicion: parada.cardinalPosicion,
            distance: rawPlaca,
          );
    final hasAddress = placa != null && placa.isNotEmpty;
    // Three distinct states, not two: a row the server refused is not a row
    // waiting its turn (Spec 3, BR3).
    final refused = row.syncStatus == AppConfig.syncError;
    final queued = row.syncStatus == AppConfig.syncPending;

    // CL-E1: the survey is the second pass over this same unit — the row
    // gains a per-unit survey chip, it does not spawn a separate list.
    final surveys = ref.watch(routeSurveysProvider(row.routeId)).valueOrNull;
    final estado =
        ref.read(surveyRepositoryProvider).estadoOf(surveys?[row.clientId]);
    // CL-E8 gate (Spec 9): the entry is locked unless the worker is cleared
    // AND the route is open. Fail-closed.
    final surveyUnlocked = ref.watch(surveyUnlockedProvider(row.routeId));
    final canSurvey = ref.watch(canSurveyProvider);

    // Spec 11: the surveyor-global posicion is gone; the row leads with the
    // per-parada number ("Parada N · predio M"), rendered with its state.
    final predio = predioDisplayFor(row, allRows);
    final metaRest = <String>[
      // loc is always shown: the backend's value once synced, else the app's
      // provisional loc = posicion * 5 (anchorLoc), matching the provisional →
      // authoritative model. Spec 11 kept loc on the card but only post-sync
      // (row.loc != null); this restores it pre-sync too.
      'loc ${CaptureRepository.anchorLoc(row)}',
      // The full 17-digit LADM_COL código collapses to a readable label
      // (Mz50 / Z1·Mz88), keeping the intermediate fields that give it
      // uniqueness in a big city (PC.6, backend-pinned).
      if (row.manzanaCatastral != null) manzanaLabel(row.manzanaCatastral!),
    ].join(' · ');

    // PC.6: the geographic-reference hint, for an R1-linked row that has one.
    final geoRef = row.npn == null
        ? null
        : ref.watch(r1RefGeograficaProvider(row.npn!)).valueOrNull;

    // Spec 1.1: this row is the only way into the editor. There is no second
    // list of the same route to hunt for.
    return InkWell(
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The address in plain language leads. A missing one keeps
                  // the size but goes muted and italic, so the gap reads as
                  // pending rather than as a shorter address.
                  Row(
                    children: [
                      // The address leads. A plate-less lot reads "Lote" (Spec
                      // 12); any other missing address stays muted/italic so the
                      // gap reads as pending.
                      Flexible(
                        child: Text(
                          hasAddress
                              ? placa
                              : (row.esLote ? 'Lote' : 'Sin dirección aún'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight:
                                hasAddress ? FontWeight.w600 : FontWeight.w400,
                            fontStyle: hasAddress || row.esLote
                                ? FontStyle.normal
                                : FontStyle.italic,
                            color: hasAddress || row.esLote
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (row.esLote) ...[
                        const SizedBox(width: 8),
                        const _LoteChip(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      PredioNumber(
                        display: predio,
                        faceSequence: parada?.faceSequence,
                      ),
                      if (metaRest.isNotEmpty)
                        Text(
                          '· $metaRest',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  // PC.6: best-effort geographic reference (corregimiento/
                  // vereda) — an approximate hint, only for an R1-linked row
                  // that carries one. Gives context to a "Rural con calles"
                  // (Mz 50, Zona Rural · 📍 ref: Salto de Bordones).
                  if (geoRef != null && geoRef.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '📍 ref: $geoRef',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // Pending relocation, naming the anchor (Spec 2.1). A line
                  // rather than a pill: the point is *which* unit it goes
                  // after, and that needs words.
                  if (row.insAfter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.low_priority,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'tras ${anchorLabel(allRows, row.clientId, row.insAfter!)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // The server's reason, on the row. A refused unit is useless
                  // to the worker unless they can read why.
                  if (refused && row.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        row.syncError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _SurveyLine(
                      estado: estado,
                      locked: !surveyUnlocked,
                      onTap: surveyUnlocked
                          ? () => _survey(
                                context,
                                predioPlainLabel(predio,
                                    faceSequence: parada?.faceSequence),
                                // The COMPOSED address (same as this row shows),
                                // not the raw stored distance.
                                hasAddress ? placa : null,
                              )
                          : () => _explainLock(context, canSurvey),
                    ),
                  ),
                ],
              ),
            ),
            if (queued) const _PendingBadge(),
            if (refused) const _ErrorBadge(),
          ],
        ),
      ),
    );
  }

  /// Opens the full-screen editor (Spec 1.1's dialog outgrew Spec 7: the
  /// editor now carries the R1 typeahead and the door link, which never fit
  /// a modal). The screen persists on save; nothing to hand back here.
  Future<void> _edit(BuildContext context, WidgetRef ref) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditUnitScreen(row: row, allRows: allRows),
      ),
    );
  }

  /// Opens the survey pass for this unit (Spec 8). Tapping the chip enters
  /// the survey; tapping the rest of the row still edits the placa — the two
  /// passes share the row without a mode toggle.
  ///
  /// (The CL-E8 lock gate rides here once the backend's TJ.5 flags land; for
  /// now the entry is always open — enforcement is server-side at push.)
  Future<void> _survey(
      BuildContext context, String predioLabel, String? address) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurveyScreen(
          anchorClientId: row.clientId,
          routeId: row.routeId,
          predioLabel: predioLabel,
          // The composed address, so the survey header reads like the list
          // ("CARRERA 4 # 2-85"), not the raw stored distance ("85").
          address: address,
        ),
      ),
    );
  }

  /// CL-E8: a locked survey chip says WHY, and distinguishes the two causes —
  /// the worker is not cleared, or the route is not open — so the surveyor
  /// knows whether to ask about themselves or about the route.
  void _explainLock(BuildContext context, bool canSurvey) {
    final msg = canSurvey
        ? 'La oficina no ha habilitado la encuesta en esta ruta.'
        : 'La oficina no ha habilitado la encuesta para este encuestador.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// The per-unit survey chip in the resume list (CL-E1). Tappable, and it
/// stops the tap from reaching the row's placa editor underneath. When
/// [locked] (CL-E8, Spec 9) it shows the lock and its tap only explains why.
class _SurveyLine extends StatelessWidget {
  const _SurveyLine({
    required this.estado,
    required this.onTap,
    this.locked = false,
  });

  final SurveyEstado estado;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg, icon) = locked
        ? (
            'Encuesta bloqueada',
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.onSurfaceVariant,
            Icons.lock_outline,
          )
        : switch (estado) {
            SurveyEstado.completa => (
                'Encuesta completa',
                theme.colorScheme.secondaryContainer,
                theme.colorScheme.onSecondaryContainer,
                Icons.check_circle_outline,
              ),
            SurveyEstado.aMedias => (
                'Encuesta a medias',
                theme.colorScheme.tertiaryContainer,
                theme.colorScheme.onTertiaryContainer,
                Icons.timelapse,
              ),
            SurveyEstado.sinEncuesta => (
                'Levantar encuesta',
                theme.colorScheme.surfaceContainerHighest,
                theme.colorScheme.onSurfaceVariant,
                Icons.assignment_outlined,
              ),
          };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: theme.textTheme.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Marks a row the server refused. Uses the error colour because, unlike a
/// queued row, this one will not resolve by waiting.
/// Spec 12: marks a captured row as a vacant lot (`es_lote`).
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

class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'rechazada',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// Marks a row that still lives only on the device. Offline queueing is the
/// normal field state, so it informs without competing with the address.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'sin enviar',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
