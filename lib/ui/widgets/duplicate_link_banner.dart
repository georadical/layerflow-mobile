import 'package:flutter/material.dart';

/// CL-R3 trigger 5 (R1 duplicate amendment, DR2/DR3): says where the same R1
/// link already is in the route; never blocks. Shared by capture and editor.
class DuplicateLinkBanner extends StatelessWidget {
  const DuplicateLinkBanner({super.key, required this.message});

  final String message;

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
                message,
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
