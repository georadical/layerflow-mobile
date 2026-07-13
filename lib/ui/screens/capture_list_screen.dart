import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../providers.dart';

const _tipoAccesoLabels = <String, String>{
  'puerta_calle': 'Puerta a la calle',
  'area_comun': 'Área común',
  'otro': 'Otro',
};

/// Lista de capturas de la ruta (orden estricto). Permite editar atributos
/// (placa/tipo/observación), NUNCA el `orden` (append-only).
class CaptureListScreen extends ConsumerWidget {
  const CaptureListScreen({super.key, required this.routeId});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capturesAsync = ref.watch(capturesProvider(routeId));
    return Scaffold(
      appBar: AppBar(title: const Text('Capturas de la ruta')),
      body: capturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Sin capturas todavía.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = list[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${c.orden}')),
                title: Text(
                  (c.placa == null || c.placa!.trim().isEmpty)
                      ? '(sin placa)'
                      : c.placa!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_subtitle(c)),
                trailing: _StatusIcon(status: c.syncStatus),
                onTap: () => _editDialog(context, ref, c),
              );
            },
          );
        },
      ),
    );
  }

  String _subtitle(Capture c) {
    final parts = <String>[];
    if (c.loc != null) parts.add('loc ${c.loc}');
    if (c.tipoAcceso != null) {
      parts.add(_tipoAccesoLabels[c.tipoAcceso] ?? c.tipoAcceso!);
    }
    if (c.manzanaCatastral != null) parts.add('mz ${c.manzanaCatastral}');
    if (c.observacion != null && c.observacion!.isNotEmpty) {
      parts.add(c.observacion!);
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _editDialog(
      BuildContext context, WidgetRef ref, Capture c) async {
    final placaCtrl = TextEditingController(text: c.placa ?? '');
    final obsCtrl = TextEditingController(text: c.observacion ?? '');
    final manzanaCtrl = TextEditingController(text: c.manzanaCatastral ?? '');
    var tipo = c.tipoAcceso;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Editar orden ${c.orden}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: placaCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Placa'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tipo,
                  decoration:
                      const InputDecoration(labelText: 'Tipo de acceso'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final e in _tipoAccesoLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => tipo = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: manzanaCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Manzana catastral'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(labelText: 'Observación'),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'El orden no se puede cambiar (append-only).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await ref.read(captureRepositoryProvider).editCapture(
            clientId: c.clientId,
            placa: placaCtrl.text,
            tipoAcceso: tipo,
            manzanaCatastral: manzanaCtrl.text,
            observacion: obsCtrl.text,
          );
    }
    placaCtrl.dispose();
    obsCtrl.dispose();
    manzanaCtrl.dispose();
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'synced':
        return const Icon(Icons.cloud_done, color: Colors.green);
      case 'error':
        return const Icon(Icons.error_outline, color: Colors.red);
      default:
        return const Icon(Icons.cloud_upload, color: Colors.orange);
    }
  }
}
