import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Points the sqlite3 package at the library Linux actually ships.
///
/// Distributions install `libsqlite3.so.0` and leave the unversioned
/// `libsqlite3.so` to the -dev package, which a CI box or a plain workstation
/// usually lacks. Without this the drift tests silently skip themselves, which
/// is worse than failing: the suite stays green while the repository is never
/// exercised at all.
void useSystemSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    for (final name in ['libsqlite3.so', 'libsqlite3.so.0']) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {
        continue;
      }
    }
    return DynamicLibrary.process();
  });
}
