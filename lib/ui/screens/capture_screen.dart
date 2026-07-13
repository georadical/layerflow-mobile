import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../providers.dart';
import 'capture_list_screen.dart';

/// Opciones de tipo de acceso (opcional). El valor guardado es la clave.
const _tipoAccesoOptions = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común (hall/escalera/patio)',
  'otro': 'Otro',
};

/// Pantalla de captura: append estricto, una placa por domicilio.
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

  @override
  void dispose() {
    _placaCtrl.dispose();
    _obsCtrl.dispose();
    _manzanaCtrl.dispose();
    _placaFocus.dispose();
    super.dispose();
  }

  Future<void> _saveAndNext() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(captureRepositoryProvider);
    try {
      await repo.appendCapture(
        routeId: widget.routeId,
        placa: _placaCtrl.text,
        manzanaCatastral: _manzanaCtrl.text,
        tipoAcceso: _tipoAcceso,
        observacion: _obsCtrl.text,
      );
      // Limpiar para el siguiente domicilio. Manzana se conserva (mismo bloque).
      _placaCtrl.clear();
      _obsCtrl.clear();
      setState(() => _tipoAcceso = null);
      _placaFocus.requestFocus();
      _autoSync();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sincroniza en segundo plano si hay conexión (best-effort).
  Future<void> _autoSync() async {
    if (!ref.read(isOnlineProvider)) return;
    await ref.read(syncServiceProvider).pushPending(widget.routeId);
  }

  Future<void> _syncNow() async {
    final res =
        await ref.read(syncServiceProvider).pushPending(widget.routeId);
    if (!mounted) return;
    final msg = res.isNoop
        ? 'No hay capturas pendientes.'
        : (res.message ?? 'Sincronización completa.');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final capturesAsync = ref.watch(capturesProvider(widget.routeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        actions: [
          capturesAsync.maybeWhen(
            data: (list) {
              final pending =
                  list.where((c) => c.syncStatus != 'synced').length;
              return _SyncButton(
                pending: pending,
                online: online,
                onPressed: _syncNow,
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Ver capturas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CaptureListScreen(routeId: widget.routeId),
              ),
            ),
          ),
        ],
      ),
      body: capturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final last = list.isEmpty ? null : list.last;
          final nextOrden = (last?.orden ?? 0) + 1;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LastCaptureCard(last: last, total: list.length),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Chip(
                      avatar: const Icon(Icons.tag, size: 18),
                      label: Text('Siguiente orden: $nextOrden'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _placaCtrl,
                  focusNode: _placaFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Placa (dirección en la puerta)',
                    hintText: 'C 5 1 11',
                    helperText: 'Opcional: puede quedar en blanco.',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _tipoAcceso,
                  decoration:
                      const InputDecoration(labelText: 'Tipo de acceso (opcional)'),
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
                    icon: Icon(_showAdvanced
                        ? Icons.expand_less
                        : Icons.expand_more),
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
                      helperText: 'Se conserva entre capturas del mismo bloque.',
                    ),
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\n')),
                    ],
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

/// Tarjeta con la última placa capturada — el ancla para verificar contra la
/// puerta ("¿el formulario N corresponde a esta casa?").
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
              'La primera será orden 1.'),
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
            Text('Última capturada · orden ${last!.orden} · total $total',
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

class _SyncButton extends StatelessWidget {
  const _SyncButton({
    required this.pending,
    required this.online,
    required this.onPressed,
  });
  final int pending;
  final bool online;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(online ? Icons.sync : Icons.sync_disabled),
          tooltip: online ? 'Sincronizar' : 'Sin conexión',
          onPressed: online ? onPressed : null,
        ),
        if (pending > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$pending',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}
