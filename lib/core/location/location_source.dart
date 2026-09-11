/// "Location source" seam.
///
/// The MVP is **coordinate-free**: coordinates are NOT captured and the API
/// payload does not carry them. This abstraction exists only so that, later on,
/// an external GNSS receiver (e.g. Polaris, NMEA over Bluetooth) can be plugged
/// in WITHOUT touching the rest of the app.
///
/// MVP golden rule: nobody should call [LocationSource.currentFix] to inject
/// coordinates into the capture. The default implementation is
/// [NullLocationSource], which always returns `null`.
library;

/// A location "fix". Deliberately inert in the MVP: no part of the capture
/// flow consumes it. It is modeled for the GNSS phase.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.source = 'unknown',
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  /// Identifier of the source that produced the fix (e.g. 'polaris-nmea').
  final String source;
  final DateTime? timestamp;

  @override
  String toString() =>
      'LocationFix($latitude, $longitude, ±${accuracyMeters}m, $source)';
}

/// Location source interface. Future implementations:
/// - `BluetoothNmeaLocationSource` (external receiver)
/// The MVP uses [NullLocationSource].
abstract interface class LocationSource {
  /// Stable identifier of the source (telemetry / diagnostics).
  String get id;

  /// Can the source deliver coordinates right now? In the MVP: always
  /// `false`.
  bool get isAvailable;

  /// Returns the last available fix, or `null` if there is no location.
  /// In the MVP it always returns `null`.
  Future<LocationFix?> currentFix();
}

/// NULL implementation for the MVP: coordinate-free. Never delivers
/// coordinates.
class NullLocationSource implements LocationSource {
  const NullLocationSource();

  @override
  String get id => 'null';

  @override
  bool get isAvailable => false;

  @override
  Future<LocationFix?> currentFix() async => null;
}
