import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';

void main() {
  group('PlacaItemRequest.toJson', () {
    test('INVARIANT: never carries coordinates', () {
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
          reason: 'The capture payload must be coordinate-free.',
        );
      }
    });

    test('placa is sent as null when blank', () {
      final json = const PlacaItemRequest(clientId: 'abc', orden: 1).toJson();
      expect(json.containsKey('placa'), isTrue);
      expect(json['placa'], isNull);
      // Absent optional fields are not serialized.
      expect(json.containsKey('manzana_catastral'), isFalse);
      expect(json.containsKey('tipo_acceso'), isFalse);
    });

    test('maps client_id and orden using the contract snake_case', () {
      final json = const PlacaItemRequest(clientId: 'xyz', orden: 3).toJson();
      expect(json['client_id'], 'xyz');
      expect(json['orden'], 3);
    });
  });

  group('PlacaBatchResponse.fromJson', () {
    test('parses the batch and the per-item results', () {
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
    test('parses the frame used to resume', () {
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
