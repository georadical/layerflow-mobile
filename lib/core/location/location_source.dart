/// Costura de "fuente de ubicación".
///
/// El MVP es **coordinate-free**: NO se capturan coordenadas y el payload de la
/// API no las lleva. Esta abstracción existe únicamente para que, más adelante,
/// se pueda enchufar un receptor GNSS externo (p. ej. Polaris, NMEA por
/// Bluetooth) SIN tocar el resto de la app.
///
/// Regla de oro del MVP: nadie debe llamar a [LocationSource.currentFix] para
/// inyectar coordenadas en la captura. La implementación por defecto es
/// [NullLocationSource], que siempre devuelve `null`.
library;

/// Un "fix" de ubicación. Deliberadamente inerte en el MVP: ninguna parte del
/// flujo de captura lo consume. Queda modelado para la fase GNSS.
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

  /// Identificador de la fuente que produjo el fix (p. ej. 'polaris-nmea').
  final String source;
  final DateTime? timestamp;

  @override
  String toString() =>
      'LocationFix($latitude, $longitude, ±${accuracyMeters}m, $source)';
}

/// Interfaz de la fuente de ubicación. Implementaciones futuras:
/// - `BluetoothNmeaLocationSource` (receptor externo)
/// El MVP usa [NullLocationSource].
abstract interface class LocationSource {
  /// Identificador estable de la fuente (telemetría / diagnóstico).
  String get id;

  /// ¿La fuente puede entregar coordenadas ahora mismo? En el MVP: siempre
  /// `false`.
  bool get isAvailable;

  /// Devuelve el último fix disponible, o `null` si no hay ubicación.
  /// En el MVP devuelve siempre `null`.
  Future<LocationFix?> currentFix();
}

/// Implementación NULA del MVP: coordinate-free. Nunca entrega coordenadas.
class NullLocationSource implements LocationSource {
  const NullLocationSource();

  @override
  String get id => 'null';

  @override
  bool get isAvailable => false;

  @override
  Future<LocationFix?> currentFix() async => null;
}
