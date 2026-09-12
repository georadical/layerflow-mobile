import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/providers.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/route_selector_screen.dart';
import 'ui/theme.dart';

class LayerFlowCaptureApp extends StatelessWidget {
  const LayerFlowCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LayerFlow — Captura',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootGate(),
    );
  }
}

/// Decides the first screen from the stored state (Spec 5, T5.2):
/// - session with an active ESP → the worker's routes (day starts there);
/// - session without a choice yet → the ESP choice (CL5);
/// - no session but a pasted token → routes, exactly as before login
///   existed (CL1: the paste path keeps working);
/// - nothing → login.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  @override
  void initState() {
    super.initState();
    // CL2: silent token renewal on app open. Waits for the stored session
    // and the first connectivity reading, then refreshes only if due.
    // Fire-and-forget: the gate never blocks on it.
    Future.microtask(() async {
      try {
        await ref.read(connectivityProvider.future);
        await ref.read(sessionProvider.future);
        await ref.read(sessionProvider.notifier).refreshIfNeeded();
      } catch (_) {
        // Offline or unreadable session: the gate handles both already.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return switch (session) {
      AsyncData(value: final s?) => s.activeEsp != null
          ? const RouteSelectorScreen()
          : EspChoiceScreen(session: s),
      AsyncData() => switch (ref.watch(tokenStatusProvider).valueOrNull) {
          null => const _Splash(),
          TokenStatus.missing => const LoginScreen(),
          _ => const RouteSelectorScreen(),
        },
      // A session that cannot be read behaves as logged out: logging in
      // re-issues everything fresh (BR-FRESH).
      AsyncError() => const LoginScreen(),
      _ => const _Splash(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
