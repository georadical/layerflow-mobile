# LayerFlow Mobile — Contexto del Proyecto para Claude Code

## ¿Qué es LayerFlow Mobile?
App de **captura de campo** para el censo de usuarios de LayerFlow. La usan los
**encuestadores** para recorrer una ruta y registrar **placas + accesos en orden
estricto**, sin coordenadas (*coordinate-free*). No es el backend: es el **cliente
móvil** que consume la API de LayerFlow. El registro de unidades (census_codes) lo
crea el backend a partir de lo que la app empuja.

> Repos separados: el backend (FastAPI/PostGIS) vive en otro repositorio/sesión.
> Esta app **no** toca base de datos ni geoprocesamiento; solo consume la API HTTP.

## Stack Tecnológico
- **Framework:** Flutter (canal stable), Dart
- **Target:** Android (prueba en emulador; ver "Backend local" abajo)
- **Red:** cliente HTTP en `api_client.dart` (Bearer field_token)
- **Persistencia local / cola offline:** _AJUSTAR al real (p. ej. sqflite / Hive / Isar)_
- **State management:** _AJUSTAR al real (p. ej. Riverpod / Bloc / Provider)_
- **Config en app:** pantalla **Ajustes** → URL base + field_token

## Estructura del Proyecto
> _AJUSTAR a la estructura real del repo; layout Flutter típico:_
```
mobile/
├── lib/
│   ├── main.dart
│   ├── api/            # api_client.dart, modelos de request/response
│   ├── models/         # entidades de dominio (Route, CaptureItem, RouteFrame…)
│   ├── features/       # pantallas por feature (ajustes, selector de ruta, captura…)
│   ├── data/           # cola offline / persistencia local
│   └── shared/         # widgets y utilidades comunes
├── test/               # unit + widget tests
├── specs/              # specs por feature (spec-driven; ver workflow abajo)
└── CLAUDE.md
```

## Relación con el Backend (contrato — fuente de verdad)
Auth: **field_token** (`kind='field'`), scoped a una ESP (tenant) y a un encuestador.
Va en `Authorization: Bearer <token>`. Sin token → 401; token de login → 403.

Backend local desde el **emulador Android**: `http://10.0.2.2:8000`
(`10.0.2.2` = localhost de la laptop visto desde el emulador). En dispositivo
físico: IP LAN de la laptop.

Endpoints que consume (ya implementados en el backend):
| Método | Path | Uso en la app |
|--------|------|---------------|
| GET  | `/field/routes` | Selector de rutas del encuestador (titular o pareja), `estado='verificada'`, con `total_capturado` |
| GET  | `/field/capture/route/{route_id}` | Frame de una ruta para **reanudar** (lo ya capturado, ordenado por `loc`) |
| POST | `/field/capture/placas` | **Push** de un lote de placas en orden (upsert de census_codes) |

Contrato POST `/field/capture/placas` (request):
```json
{
  "route_id": "<uuid>",
  "batch_id": "<uuid del lote, generado por la app>",
  "items": [
    { "client_id": "<uuid v4 POR UNIDAD, estable entre reintentos>",
      "orden": 1, "placa": "12-34", "manzana_catastral": "001",
      "tipo_acceso": "porton", "observacion": "texto" }
  ]
}
```
Respuesta: `{ batch_id, route_id, total, created, updated, errores, items:[{client_id, ok, id, loc, status}] }`.

## Invariantes de Dominio (respeta el contrato — no reinventar)
- **Coordinate-free:** ningún request/response/almacenamiento lleva coordenadas.
- **Orden estricto:** `orden` entero ≥ 1; `loc = orden × 5` (lo fija el backend).
- **PH/PV:** siempre `00` en esta captura (los fija el backend).
- **Idempotencia:** `client_id` es un **UUID por unidad, estable entre reintentos**.
  Reenviar el mismo `client_id` **actualiza**, nunca duplica → la cola offline puede
  reintentar sin miedo.
- **Estado de ruta:** dominio real `borrador | verificada`. Solo se capturan rutas
  **`verificada`** (no existe "congelada"). `/field/routes` ya filtra por eso.
- **Batch parcial:** el push no es todo-o-nada; procesa `items[].ok` y `errores`.
- **Placa vacía permitida:** `placa=null` es válido (unidad sin dirección aún).

## Development Rule: Atomic & Verifiable Progress
Cada avance debe ser:
- **Atómico:** una sola cosa por paso (una pantalla, un widget, un modelo, un método del api_client).
- **Incremental:** cada paso sobre uno anterior ya aprobado.
- **Verificable:** si se puede observar, se prueba antes de seguir. Para esta app:
  `flutter analyze` sin errores, `flutter test` verde, la app compila (`flutter run`),
  la pantalla renderiza el layout, o la llamada al endpoint devuelve lo esperado.

**Ningún paso siguiente arranca sin aprobación explícita del actual.**

## Feature Workflow: Spec-Driven + Wireframe-First
Definir la intención antes de escribir código. No empieces por widgets ni llamadas
HTTP: empieza por reglas, flujos y resultados esperados. Toda feature nace como spec
en `specs/<feature>.md`. La spec **debe** declarar lo que queda FUERA de alcance.

Como es una app (todo UI), el pipeline es:

`Spec → Wireframe → Design → Implementación`

- **Spec:** user story, alcance + fuera-de-alcance, estados de UI (cargando / lista /
  vacía / error de red / 401→re-login), datos por pantalla, acciones, casos borde.
  Valida los supuestos no explícitos **antes** de codear.
- **Wireframe:** layout y ubicación de elementos con **datos dummy**, sin estilo
  (widgets planos, sin tema, sin colores). Gate: la pantalla renderiza el layout.
- **Design:** aplicar estilo/tema **sin** cambiar estructura ni textos. Gate: compila
  y se ve; commit.
- **Implementación:** conectar al `api_client` real (endpoints de arriba), manejar
  estados y errores, cola offline. Gate: `flutter test` verde + prueba manual contra
  el backend local.

Cada fase termina con su gate verificable, un `git commit` y **aprobación explícita**
antes de la siguiente.

### Reglas para el agente
- Nunca saltes de la spec directo al código.
- Nunca asumas lógica no especificada. Si falta una regla o un campo, **pregunta**.
- Parte las specs en tickets pequeños. Nunca implementes una historia grande de un tirón.
- No cambies el contrato del backend desde la app: si algo no cuadra, repórtalo.

## Code Conventions
- **Todo en inglés:** código, comentarios, commits, docs internas (specs/, README).
  Excepción: referencias a normativa colombiana (LADM_COL, SUI, CRA) en su idioma.
- Formato y lint: `dart format .` + `flutter analyze` limpios antes de commit.
- Nombres de dominio consistentes con el backend (ver glosario).

## Common Commands
```bash
flutter pub get            # instalar dependencias
flutter run                # correr en emulador/dispositivo
flutter test               # correr tests
flutter analyze            # lints / análisis estático
dart format .              # formatear
```

## Fuera de Alcance (de la app)
- El backend y su base de datos (repo aparte; la app solo consume la API).
- La capa de **observación** del encuestador (`/sync/push`, `/sync/pull`) — flujo distinto.
- Expansión PH/PV, hogar, medidor (encuesta extendida — observación).
- Coordenadas / mapas / geoprocesamiento.
- Emisión o renovación de tokens (la hace el operador en el backend).
- Segmentos de ruta (rango `localizacion`): por ahora se abre la ruta completa.

## Glosario (alineado con el backend)
- **ESP / tenant:** empresa de servicios públicos; el token está atado a una.
- **Encuestador (field worker):** operario de campo; puede ir como **titular** o **pareja**.
- **Ruta (route):** unidad operativa del recorrido; se identifica por `codigo` y `route_id`.
- **census_code:** unidad/usuario del censo que crea el backend con cada placa (`Ruta+Loc+PH+PV`).
- **placa:** número/placa del predio capturado en campo (texto crudo).
- **loc (localizacion):** secuencial en orden de recorrido; `loc = orden × 5`.
- **client_id:** UUID por unidad generado por la app; llave de idempotencia.
- **batch_id:** UUID del lote de push generado por la app.
```
