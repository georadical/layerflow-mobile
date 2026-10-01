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

  group('route-state locks — DTO parsing + fail directions (Spec 9)', () {
    test('RouteSummary defaults: placa fail-OPEN, survey fail-CLOSED', () {
      final r = RouteSummary.fromJson({
        'route_id': 'r1',
        'codigo': '10',
        'estado': 'verificada',
      });
      expect(r.placasEstado, 'abierta');
      expect(r.surveyEstado, 'bloqueada');
    });

    test('RouteSummary reads explicit estados and round-trips them', () {
      final r = RouteSummary.fromJson({
        'route_id': 'r1',
        'codigo': '10',
        'estado': 'verificada',
        'placas_estado': 'cerrada',
        'survey_estado': 'abierta',
      });
      expect(r.placasEstado, 'cerrada');
      expect(r.surveyEstado, 'abierta');
      final back = RouteSummary.fromJson(r.toJson());
      expect(back.placasEstado, 'cerrada');
      expect(back.surveyEstado, 'abierta');
    });

    test('RouteFrame carries the estados with the same defaults', () {
      final def = RouteFrame.fromJson({'route_id': 'r1', 'items': []});
      expect(def.placasEstado, 'abierta');
      expect(def.surveyEstado, 'bloqueada');

      final explicit = RouteFrame.fromJson({
        'route_id': 'r1',
        'items': [],
        'placas_estado': 'cerrada',
        'survey_estado': 'abierta',
      });
      expect(explicit.placasEstado, 'cerrada');
      expect(explicit.surveyEstado, 'abierta');
    });

    test('LoginEsp.can_survey is fail-CLOSED and round-trips', () {
      final off = LoginEsp.fromJson({
        'tenant_id': 1,
        'esp_nombre': 'ESP',
        'field_worker_id': 'fw',
        'field_token': 't',
      });
      expect(off.canSurvey, isFalse);

      final on = LoginEsp.fromJson({
        'tenant_id': 1,
        'esp_nombre': 'ESP',
        'field_worker_id': 'fw',
        'field_token': 't',
        'can_survey': true,
      });
      expect(on.canSurvey, isTrue);
      expect(LoginEsp.fromJson(on.toJson()).canSurvey, isTrue);
    });
  });

  group('parada-scoped capture DTOs (Spec 10)', () {
    test('RouteStops parses paradas with es_actual / swept', () {
      final s = RouteStops.fromJson({
        'route_id': 'r1',
        'items': [
          {
            'stop_id': 's1',
            'face_sequence': 1,
            'block_face_id': 'bf1',
            'face_index': 1,
            'manzana_catastral': '001',
            'orientation': 'N',
            'swept': true,
          },
          {
            'stop_id': 's2',
            'face_sequence': 2,
            'block_face_id': 'bf2',
            'es_actual': true,
          },
        ],
      });
      expect(s.items.length, 2);
      expect(s.items[0].swept, isTrue);
      expect(s.items[0].faceIndex, 1);
      expect(s.items[1].esActual, isTrue);
      expect(s.items[1].swept, isFalse);
    });

    test(
        'RouteStop: a rural parada has no block_face_id and no terna '
        '(Decisions v2 §6/§8)', () {
      final s = RouteStops.fromJson({
        'route_id': 'r1',
        'items': [
          {'stop_id': 's-rural', 'face_sequence': 4},
          {
            'stop_id': 's-urban',
            'face_sequence': 1,
            'block_face_id': 'bf1',
            'tipo_via': 'CALLE',
            'num_via': '13',
            'num_cruce': '3A',
          },
        ],
      });
      final rural = s.items[0];
      expect(rural.blockFaceId, isNull);
      expect(rural.tipoVia, isNull);
      expect(rural.numVia, isNull);
      expect(rural.numCruce, isNull);

      final urban = s.items[1];
      expect(urban.blockFaceId, 'bf1');
      expect(urban.tipoVia, 'CALLE');
      expect(urban.numVia, '13');
      expect(urban.numCruce, '3A');
      expect(urban.cardinal, isNull);
      expect(urban.cardinalPosicion, isNull);
    });

    test(
        'RouteStop parses the cardinal zone suffix (address-profiles '
        'AP.1–AP.5)', () {
      final s = RouteStops.fromJson({
        'route_id': 'r1',
        'items': [
          {
            'stop_id': 's1',
            'face_sequence': 1,
            'tipo_via': 'CALLE',
            'num_via': '11',
            'num_cruce': '3A',
            'cardinal': 'SUR',
            'cardinal_posicion': 'via',
          },
        ],
      });
      expect(s.items.single.cardinal, 'SUR');
      expect(s.items.single.cardinalPosicion, 'via');
    });

    test('PlacaItemRequest carries block_face_id only when present', () {
      expect(
        const PlacaItemRequest(clientId: 'a', posicion: 1, blockFaceId: 'bf1')
            .toJson()['block_face_id'],
        'bf1',
      );
      expect(
        const PlacaItemRequest(clientId: 'a', posicion: 1)
            .toJson()
            .containsKey('block_face_id'),
        isFalse,
      );
    });

    test('PlacaItemRequest carries stop_id only when present (Decisions v2 §6)',
        () {
      expect(
        const PlacaItemRequest(clientId: 'a', posicion: 1, stopId: 's1')
            .toJson()['stop_id'],
        's1',
      );
      expect(
        const PlacaItemRequest(clientId: 'a', posicion: 1)
            .toJson()
            .containsKey('stop_id'),
        isFalse,
      );
    });

    test('PlacaItemResult reads the per-item codigo', () {
      final r = PlacaItemResult.fromJson({
        'client_id': 'a',
        'ok': false,
        'codigo': 'barrido_fuera_de_orden',
      });
      expect(r.ok, isFalse);
      expect(r.codigo, 'barrido_fuera_de_orden');
    });

    test('foto_obligatoria: absent → false, explicit true; round-trips', () {
      final def = RouteSummary.fromJson(
          {'route_id': 'r', 'codigo': '10', 'estado': 'verificada'});
      expect(def.fotoObligatoria, isFalse);

      final on = RouteSummary.fromJson({
        'route_id': 'r',
        'codigo': '10',
        'estado': 'verificada',
        'foto_obligatoria': true,
      });
      expect(on.fotoObligatoria, isTrue);
      expect(RouteSummary.fromJson(on.toJson()).fotoObligatoria, isTrue);

      final frame = RouteFrame.fromJson(
          {'route_id': 'r', 'items': [], 'foto_obligatoria': true});
      expect(frame.fotoObligatoria, isTrue);
    });

    test('RouteFrameItem carries block_face_id', () {
      final item = RouteFrameItem.fromJson({
        'client_id': 'a',
        'posicion': 1,
        'loc': 5,
        'block_face_id': 'bf1',
      });
      expect(item.blockFaceId, 'bf1');
    });

    test('RouteFrameItem carries stop_id (Decisions v2 §6)', () {
      final item = RouteFrameItem.fromJson({
        'client_id': 'a',
        'posicion': 1,
        'loc': 5,
        'stop_id': 's1',
      });
      expect(item.stopId, 's1');
    });
  });

  group('R1DirectoryItem.fromJson (Spec 10)', () {
    test('parses ref_geografica when present; null on a clean urban row', () {
      final rural = R1DirectoryItem.fromJson({
        'npn': 'n1',
        'direccion': 'CARRERA 2 # 3-09',
        'direccion_norm': 'CARRERA 2 # 3-09',
        'ref_geografica': 'SALTO DE BORDONES',
      });
      expect(rural.refGeografica, 'SALTO DE BORDONES');

      final urban = R1DirectoryItem.fromJson({
        'npn': 'n2',
        'direccion': 'CALLE 6 # 4-17',
        'direccion_norm': 'CALLE 6 # 4-17',
      });
      expect(urban.refGeografica, isNull);
    });
  });
}
