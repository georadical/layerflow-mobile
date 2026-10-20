import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../providers.dart';

/// Spec 18 BR1: "sin placa a la vista" ≡ no placa read on the door AND an R1 link
/// (`npn`, or `direccion_norm` for a multi-unit placa). A lot is never linked
/// (Spec 12 BR6), so it never reads this way.
bool isSinPlaca(Capture c) =>
    (c.placa == null || c.placa!.trim().isEmpty) &&
    !c.esLote &&
    (c.npn != null || c.direccionNorm != null);

/// The R1 address a capture is linked to: a multi-unit link carries it
/// (`direccion_norm`); a single-unit link is looked up by `npn`, as editar unidad
/// does. Null when unknown (no tenant, row not in the local directory).
final linkedAddressProvider = FutureProvider.autoDispose
    .family<String?, ({String? npn, String? direccionNorm})>((ref, key) async {
  if (key.direccionNorm != null) return key.direccionNorm;
  final npn = key.npn;
  if (npn == null) return null;
  final tenantId = ref.watch(activeTenantIdProvider);
  if (tenantId == null) return null;
  final row =
      await ref.watch(r1DirectoryRepositoryProvider).byNpn(tenantId, npn);
  return row?.direccionNorm;
});

/// "enlazada a <R1 address>" (Spec 18 BR10), with a neutral fallback while the
/// address loads or when it cannot be resolved.
class LinkedAddressText extends ConsumerWidget {
  const LinkedAddressText(
    this.capture, {
    super.key,
    this.suffix = '',
    this.style,
  });

  final Capture capture;
  final String suffix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref
        .watch(linkedAddressProvider(
            (npn: capture.npn, direccionNorm: capture.direccionNorm)))
        .valueOrNull;
    return Text('enlazada a ${address ?? 'dirección del R1'}$suffix',
        style: style);
  }
}
