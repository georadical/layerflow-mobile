import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';

/// The version shown in Ajustes must be the one the APK is built with.
void main() {
  test('AppConfig.appVersion mirrors pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(AppConfig.appVersion, match!.group(1));
  });
}
