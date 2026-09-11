import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory stand-in for the platform secure storage. Implemented through
/// noSuchMethod so it survives signature changes in the package.
class MemSecure implements FlutterSecureStorage {
  final Map<String, String?> data = {};

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #read:
        return Future<String?>.value(data[inv.namedArguments[#key]]);
      case #write:
        data[inv.namedArguments[#key] as String] =
            inv.namedArguments[#value] as String?;
        return Future<void>.value();
      case #delete:
        data.remove(inv.namedArguments[#key]);
        return Future<void>.value();
    }
    return super.noSuchMethod(inv);
  }
}
