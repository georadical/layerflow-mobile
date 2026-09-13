import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';

void main() {
  group('PlacaItemRequest.toJson', () {
    test('INVARIANT: never carries coordinates', () {
      final json = const PlacaItemRequest(
        clientId: 'abc',
        posicion: 1,
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
      final json =
          const PlacaItemRequest(clientId: 'abc', posicion: 1).toJson();
      expect(json.containsKey('placa'), isTrue);
      expect(json['placa'], isNull);
      // Absent optional fields are not serialized.
      expect(json.containsKey('manzana_catastral'), isFalse);
      expect(json.containsKey('tipo_acceso'), isFalse);
    });

    test('maps client_id and posicion using the contract snake_case', () {
      final json =
          const PlacaItemRequest(clientId: 'xyz', posicion: 3).toJson();
      expect(json['client_id'], 'xyz');
      expect(json['posicion'], 3);
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
            'posicion': 1,
            'loc': 5,
            'placa': 'C 5 1 11',
            'manzana_catastral': '001',
          }
        ],
      });
      expect(frame.routeId, 'r1');
      expect(frame.codigo, '10');
      expect(frame.items.single.posicion, 1);
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

  group('LoginResponse.fromJson (Spec 5)', () {
    // Verbatim shape documented in field-login.md @ f371076.
    Map<String, dynamic> wirePayload() => {
          'worker': {'nombre': 'Ana', 'documento': '123'},
          'esps': [
            {
              'tenant_id': 2,
              'esp_nombre': 'ESP Elías',
              'field_worker_id': 'fw-2',
              'rutas_asignadas': 1,
              'field_token': 'jwt-elias',
            },
            {
              'tenant_id': 3,
              'esp_nombre': 'ESP Isnos',
              'field_worker_id': 'fw-3',
              'rutas_asignadas': 1,
              'field_token': 'jwt-isnos',
            },
          ],
        };

    test('parses the documented multi-ESP payload', () {
      final res = LoginResponse.fromJson(wirePayload());
      expect(res.workerNombre, 'Ana');
      expect(res.esps, hasLength(2));
      expect(res.esps.last.tenantId, 3);
      expect(res.esps.last.rutasAsignadas, 1);
      expect(res.esps.last.fieldToken, 'jwt-isnos');
    });

    test('FieldSession round-trips through its storage JSON', () {
      final session = FieldSession(
        email: 'campo1@layerflow.co',
        workerNombre: 'Ana',
        esps: LoginResponse.fromJson(wirePayload()).esps,
        activeTenantId: 3,
      );

      final back = FieldSession.fromJson(session.toJson());

      expect(back.email, session.email);
      expect(back.activeTenantId, 3);
      expect(back.activeEsp!.espNombre, 'ESP Isnos');
      expect(back.esps.first.fieldToken, 'jwt-elias');
    });
  });

  group('ins_after (Spec 2.1)', () {
    test('request serialises a mark, 0 included; omits only null', () {
      // 0 is a real value — start of route — never conflated with "no mark".
      final start =
          const PlacaItemRequest(clientId: 'a', posicion: 1, insAfter: 0)
              .toJson();
      expect(start['ins_after'], 0);

      final none = const PlacaItemRequest(clientId: 'b', posicion: 2).toJson();
      expect(none.containsKey('ins_after'), isFalse);
    });

    test('frame item requires posicion; the retired alias is ignored', () {
      // Alias retired contract-wide (backend de28c1f). If 'orden' somehow
      // arrived anyway, it must not be honoured.
      final item = RouteFrameItem.fromJson(
          {'client_id': 'a', 'posicion': 2, 'orden': 99, 'loc': 10});
      expect(item.posicion, 2);

      // A payload carrying only the dead key fails loudly, never guesses.
      expect(
        () =>
            RouteFrameItem.fromJson({'client_id': 'b', 'orden': 4, 'loc': 20}),
        throwsA(isA<TypeError>()),
      );
    });

    test('the request sends posicion, never the deprecated key', () {
      final json = const PlacaItemRequest(clientId: 'a', posicion: 3).toJson();
      expect(json['posicion'], 3);
      expect(json.containsKey('orden'), isFalse);
    });

    test('request serialises npn only when present (full replacement)', () {
      final linked =
          const PlacaItemRequest(clientId: 'a', posicion: 1, npn: 'npn-1')
              .toJson();
      expect(linked['npn'], 'npn-1');

      final clean = const PlacaItemRequest(clientId: 'b', posicion: 2).toJson();
      expect(clean.containsKey('npn'), isFalse,
          reason: 'omitting clears the link server-side, by contract');
    });

    test('frame item parses npn and its provenance', () {
      final item = RouteFrameItem.fromJson({
        'client_id': 'a',
        'posicion': 1,
        'loc': 5,
        'npn': 'npn-1',
        'npn_match_method': 'field_confirmed',
      });
      expect(item.npn, 'npn-1');
      expect(item.npnMatchMethod, 'field_confirmed');

      final clean =
          RouteFrameItem.fromJson({'client_id': 'b', 'posicion': 2, 'loc': 10});
      expect(clean.npn, isNull);
    });

    test('frame item parses ins_after, and its absence, as the server sends it',
        () {
      final marked = RouteFrameItem.fromJson(
          {'client_id': 'a', 'posicion': 6, 'loc': 30, 'ins_after': 10});
      expect(marked.insAfter, 10);

      final clean = RouteFrameItem.fromJson(
          {'client_id': 'b', 'posicion': 1, 'loc': 5, 'ins_after': null});
      expect(clean.insAfter, isNull);
    });
  });
}
