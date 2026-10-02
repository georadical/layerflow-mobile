import 'package:flutter/material.dart';

import '../../core/parada/predio_sequence.dart';
import '../theme.dart';

/// The per-parada number, rendered with the Spec 11 Design tokens.
///
/// - Definitive (synced): no tilde, bold, [kPredioDefinitiveColor] green — only the
///   number is colored; the "Parada N ·" anchor stays neutral so it pops.
/// - Provisional (pre-sync): medium gray + a pending glyph (right before
///   "predio") + a tilde.
/// - Legacy (no parada): a neutral "predio —".
///
/// [faceSequence] prefixes "Parada N · " (the resume list, whose rows span
/// paradas); omit it where the parada is already named on screen (the capture
/// header shows "cara N").
class PredioNumber extends StatelessWidget {
  const PredioNumber({super.key, required this.display, this.faceSequence});

  final PredioDisplay display;
  final int? faceSequence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gray = theme.colorScheme.onSurfaceVariant;
    final base = theme.textTheme.bodySmall;
    final prefix = faceSequence == null ? '' : 'Parada $faceSequence · ';

    if (display.legacy) {
      return Text('${prefix}predio —', style: base?.copyWith(color: gray));
    }

    if (display.provisional) {
      // Gray + pending glyph (right before "predio") + tilde — all three cues.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty)
            Text(prefix, style: base?.copyWith(color: gray)),
          Icon(Icons.cloud_upload, size: 14, color: gray),
          const SizedBox(width: 3),
          Text('predio ~${display.number}', style: base?.copyWith(color: gray)),
        ],
      );
    }

    // Definitive: only the number is colored + bold; the anchor stays neutral.
    return Text.rich(
      TextSpan(children: [
        if (prefix.isNotEmpty)
          TextSpan(text: prefix, style: base?.copyWith(color: gray)),
        TextSpan(
          text: 'predio ${display.number}',
          style: base?.copyWith(
            color: kPredioDefinitiveColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }
}
