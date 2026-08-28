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

  group('AssignedRoutes.fromJson', () {
    // Verbatim payload documented for GET /field/routes.
    Map<String, dynamic> wirePayload() => {
          'esp': 'ESP Isnos (muestra)',
          'items': [
            {
              'route_id': '405ca862-e116-4a12-a920-a520c0d063ee',
              'codigo': '10',
              'nombre': null,
              'estado': 'verificada',
              'total_capturado': 2,
            }
          ],
        };

    test('parses the documented payload', () {
      final routes = AssignedRoutes.fromJson(wirePayload());

      expect(routes.esp, 'ESP Isnos (muestra)');
      final route = routes.items.single;
      expect(route.routeId, '405ca862-e116-4a12-a920-a520c0d063ee');
      expect(route.codigo, '10');
      expect(route.estado, 'verificada');
      expect(route.totalCapturado, 2);
    });

    test('nombre null stays null, it is not coerced to a placeholder', () {
      final routes = AssignedRoutes.fromJson(wirePayload());
      expect(routes.items.single.nombre, isNull);
    });

    test('empty items is a valid answer, not an error', () {
      final routes = AssignedRoutes.fromJson({'esp': 'X', 'items': []});
      expect(routes.esp, 'X');
      expect(routes.items, isEmpty);
    });

    test('total_capturado 0 parses as 0, absent parses as null', () {
      final zero = RouteSummary.fromJson({
        'route_id': 'r1',
        'codigo': '40',
        'estado': 'verificada',
        'total_capturado': 0,
      });
      final absent = RouteSummary.fromJson({
        'route_id': 'r2',
        'codigo': '50',
        'estado': 'verificada',
      });

      // The UI tells these apart: 0 shows a muted badge, null hides it.
      expect(zero.totalCapturado, 0);
      expect(absent.totalCapturado, isNull);
    });

    test('the route_id is the one the frame endpoint consumes', () {
      final routes = AssignedRoutes.fromJson(wirePayload());
      expect(
        routes.items.single.routeId,
        '405ca862-e116-4a12-a920-a520c0d063ee',
        reason: 'It is fed straight into GET /field/capture/route/{route_id}.',
      );
    });

    test('INVARIANT: the route payload carries no coordinates', () {
      final item =
          (wirePayload()['items'] as List).single as Map<String, dynamic>;
      for (final key in item.keys) {
        expect(
          key,
          isNot(anyOf('lat', 'lon', 'latitude', 'longitude', 'coords', 'geom')),
          reason: 'Route listing must stay coordinate-free.',
        );
      }
    });
  });
}
