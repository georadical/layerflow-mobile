import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
import '../../data/repositories/survey_repository.dart';
import '../providers.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routeLabel(codigo: routeCodigo, esp: esp),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaptureScreen(routeId: routeId)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Capturar'),
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
              _QueueBar(routeId: rows.first.routeId),
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

/// The queue and the only way to send it (Spec 3, BR2).
class _QueueBar extends ConsumerWidget {
  const _QueueBar({required this.routeId});

  final String routeId;

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(pushProvider(routeId).notifier).send();
      if (!context.mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Envío completo.')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // The queue is untouched by any of these: a credentials or network
      // problem must never cost captured work (BR6).
      final detail = switch (e.statusCode) {
        401 => 'Token vencido o inválido — renuévalo en Ajustes.',
        403 => 'Ese token no es de campo — pide un field_token al operador.',
        404 => 'Esa ruta no existe o no es de tu ESP.',
        _ => 'No se pudo enviar: ${e.message}',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail)));
    }
  }

  /// "hace X" from the device clock; best-effort, needs no server time.
  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  static const _outcomeLabels = <String, String>{
    AppConfig.pushOk: 'todo enviado',
    AppConfig.pushPartial: 'algunas rechazadas',
    AppConfig.pushNetwork: 'sin señal',
    AppConfig.pushAuth: 'token rechazado',
    AppConfig.pushHttp: 'error del servidor',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final waiting = ref.watch(pendingCountProvider(routeId));
    final photos =
        ref.watch(pendingEvidenceCountProvider(routeId)).valueOrNull ?? 0;
    if (waiting == 0 && photos == 0) return const SizedBox.shrink();
    final sending = ref.watch(pushProvider(routeId));
    final online = ref.watch(isOnlineProvider);
    final onWifi = ref.watch(isOnWifiProvider);
    final route = ref.watch(routeRowProvider(routeId)).valueOrNull;
    final lastAt = route?.lastPushAt;
    final lastOutcome = route?.lastPushOutcome;

    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_upload_outlined : Icons.cloud_off,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (waiting > 0) '$waiting sin enviar',
                    // Photos are named apart: with the capture queue empty
                    // this line is the only reason the bar is here.
                    if (photos > 0) '$photos ${photos == 1 ? 'foto' : 'fotos'}',
                    if (!online) 'sin conexión',
                  ].join(' · '),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                // CL-R5: routine photos only travel under WiFi. Say so,
                // rather than letting the worker press Enviar and wonder
                // why the count did not move.
                if (waiting == 0 && photos > 0 && online && !onWifi)
                  Text(
                    'Las fotos de rutina esperan WiFi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                // "Tried, and when": tells never-tried from tried-and-failed
                // even if the momentary message was missed (Spec 4, BR7).
                if (lastAt != null)
                  Text(
                    'Último intento ${_ago(lastAt)}'
                    '${_outcomeLabels[lastOutcome] != null ? ' · ${_outcomeLabels[lastOutcome]}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          if (sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            // Disabled offline rather than hidden: the action should be
            // visibly unavailable, not missing.
            FilledButton(
              onPressed: online ? () => _send(context, ref) : null,
              child: const Text('Enviar'),
            ),
        ],
      ),
    );
  }
}

class _UnitTile extends ConsumerWidget {
  const _UnitTile({required this.row, required this.allRows});

  final Capture row;

  /// The whole route, for naming this row's anchor and for the picker.
  final List<Capture> allRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placa = row.placa?.trim();
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

    final meta = <String>[
      'posición ${row.posicion}',
      if (row.loc != null) 'loc ${row.loc}',
      if (row.manzanaCatastral != null) 'mz ${row.manzanaCatastral}',
    ].join(' · ');

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
                  Text(
                    hasAddress ? placa : 'Sin dirección aún',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight:
                          hasAddress ? FontWeight.w600 : FontWeight.w400,
                      fontStyle:
                          hasAddress ? FontStyle.normal : FontStyle.italic,
                      color: hasAddress
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                      onTap: () => _survey(context),
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
  Future<void> _survey(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurveyScreen(
          anchorClientId: row.clientId,
          routeId: row.routeId,
          posicion: row.posicion,
          placa: row.placa,
        ),
      ),
    );
  }
}

/// The per-unit survey chip in the resume list (CL-E1). Tappable, and it
/// stops the tap from reaching the row's placa editor underneath.
class _SurveyLine extends StatelessWidget {
  const _SurveyLine({required this.estado, required this.onTap});

  final SurveyEstado estado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg, icon) = switch (estado) {
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
