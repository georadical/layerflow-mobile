import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';

void main() {
  group('PlacaItemRequest.toJson', () {
    test('INVARIANTE: nunca lleva coordenadas', () {
      final json = const PlacaItemRequest(
        clientId: 'abc',
        orden: 1,
        placa: 'C 5 1 11',
        manzanaCatastral: '001',
        tipoAcceso: 'puerta_calle',
        observacion: 'obs',
      ).toJson();

      for (final key in json.keys) {
        expect(
          key,
          isNot(anyOf('lat', 'lon', 'latitude', 'longitude', 'coords', 'geom')),
          reason: 'El payload de captura debe ser coordinate-free.',
        );
      }
    });

    test('placa se envía como null cuando está en blanco', () {
      final json = const PlacaItemRequest(clientId: 'abc', orden: 1).toJson();
      expect(json.containsKey('placa'), isTrue);
      expect(json['placa'], isNull);
      // Opcionales ausentes no se serializan.
      expect(json.containsKey('manzana_catastral'), isFalse);
      expect(json.containsKey('tipo_acceso'), isFalse);
    });

    test('mapea client_id y orden con snake_case del contrato', () {
      final json = const PlacaItemRequest(clientId: 'xyz', orden: 3).toJson();
      expect(json['client_id'], 'xyz');
      expect(json['orden'], 3);
    });
  });

  group('PlacaBatchResponse.fromJson', () {
    test('parsea el lote y los resultados por item', () {
      final res = PlacaBatchResponse.fromJson({
        'batch_id': 'b1',
        'total': 1,
        'created': 1,
        'updated': 0,
        'errores': 0,
        'items': [
          {
            'client_id': 'abc',
            'ok': true,
            'id': 'uuid-1',
            'loc': 5,
            'status': 'created',
          }
        ],
      });
      expect(res.total, 1);
      expect(res.items.single.ok, isTrue);
      expect(res.items.single.loc, 5);
      expect(res.items.single.status, 'created');
    });
  });

  group('RouteFrame.fromJson', () {
    test('parsea el frame para reanudar', () {
      final frame = RouteFrame.fromJson({
        'route_id': 'r1',
        'codigo': '10',
        'items': [
          {
            'client_id': 'abc',
            'orden': 1,
            'loc': 5,
            'placa': 'C 5 1 11',
            'manzana_catastral': '001',
          }
        ],
      });
      expect(frame.routeId, 'r1');
      expect(frame.codigo, '10');
      expect(frame.items.single.orden, 1);
      expect(frame.items.single.loc, 5);
    });
  });
}
