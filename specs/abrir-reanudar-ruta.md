# Spec 1 — Abrir y reanudar ruta (app móvil de captura)

Status: draft (listo para tickets)
Type: App móvil (Flutter) + 1 dependencia de backend (wire nuevo)
Enfoque: spec-driven & wire-driven. La spec es la fuente de verdad del contrato.
Cadena: **Spec 1 (esta)** → 2 captura en orden estricto (local) → 3 push por lote (`POST placas`) → 4 offline-first/reintento.

## User story
**Como** trabajador de campo de LayerFlow usando la app de captura (autenticado con mi
`field_token`, scoped a mi ESP), **quiero** ver la lista de rutas asignadas a mí
(sincronizada), abrir una y ver de inmediato lo ya capturado —con la **dirección**
como dato protagonista y ordenado por el recorrido—, **para** reanudar desde donde
iba (o confirmar que está vacía) sin duplicar unidades ni perder el orden estricto.

## Objetivo
Dar el punto de entrada usable en campo real: **sincronizar rutas asignadas → abrir
una → ver el estado reanudado**. Es la base sobre la que Spec 2–4 capturan y sincronizan.

## Alcance

**Incluye**
- Lista de **rutas asignadas** al field worker, sincronizada desde el backend
  (**wire nuevo**, ver Dependencias) y cacheada localmente para verse offline.
- Abrir una ruta (desde la lista) → `GET /field/capture/route/{route_id}` →
  fusionar el frame con lo local (sin pisar ediciones sin enviar).
- Vista de **reanudar (solo lectura)**: unidades ya capturadas, **dirección (`placa`)
  como protagonista**, ordenadas por `loc` ascendente (orden del recorrido).
- Estado vacío explícito; estados de carga; manejo y traducción de errores
  (401/404/400/sin conexión); avisos de expiración del token.
- Persistir la ruta abierta como **ruta activa** (sobrevive reinicio de la app).

**NO incluye** (mandatorio)
- Capturar, editar o eliminar unidades (Spec 2).
- Push por lote `POST /field/capture/placas` (Spec 3) ni reintento de cola (Spec 4).
- Emisión/renovación del `field_token` (se hace en el backend/operador; la app solo
  lo guarda en Ajustes).
- Diseño del endpoint de emisión de token, capa de observación (`/sync/*`), expansión
  PH/PV, medios/fotos y **cualquier coordenada** (invariante coordinate-free).
- Edición del orden / reasignación de `loc` (lo fija el backend: `loc = orden × 5`).

## Actores y permisos
- **Field worker** (nuestro equipo), autenticado con `field_token` (`require_field`,
  kind=`field`), scoped a **una ESP (tenant)** y a su worker. Solo ve rutas de su ESP;
  rutas de otra ESP son invisibles (→ 404 al intentar abrirlas por id).

## Precondiciones
- La app tiene **URL base** y **field_token** guardados en Ajustes (el token persiste
  en `EncryptedSharedPreferences`).
- El backend está accesible (emulador → `http://10.0.2.2:8000`).
- Existe el **wire nuevo** de rutas asignadas (ver Dependencias). Mientras no exista,
  aplica el flujo alternativo B (ingreso manual de `route_id`).
- Las rutas están **congeladas** (validadas) del lado backbone censal.

### Dependencias — wire nuevo (a especificar/construir en backend)
`GET /field/routes` (auth `require_field`, scoped a la ESP del token) →
```json
{
  "esp": "Isnos",
  "items": [
    { "route_id": "uuid", "codigo": "10", "manzana_catastral": "001",
      "total_capturado": 12, "estado": "congelada" }
  ]
}
```
- Devuelve solo rutas visibles para ese token (ESP + worker).
- Orden por `codigo`. `total_capturado` alimenta el badge de progreso en la lista.
- Sin coordenadas. Es un **prerrequisito**: se trabaja como spec de backend aparte y
  esta Spec 1 lo consume.

## Trigger
El worker abre la app (o entra al Home) y toca **"Sincronizar rutas"**, o selecciona
una ruta ya listada y toca **"Abrir y reanudar"**.

## Flujo principal (happy path)
1. En el Home, la app muestra la **lista de rutas asignadas** (desde caché local) y
   ofrece **"Sincronizar"**.
2. El worker toca **"Sincronizar"** → `GET /field/routes` con `Bearer <field_token>`.
3. La app guarda/actualiza la lista local y la muestra ordenada por `codigo`, cada
   ítem con `codigo`, `manzana_catastral` y badge `total_capturado`.
4. El worker **toca una ruta** de la lista → la app llama `GET /field/capture/route/{route_id}`.
5. La app **fusiona** el frame con lo local (regla BR3) y **persiste la ruta activa**.
6. Navega a la vista de **reanudar (solo lectura)**, con:
   - título = **código de la ruta** (p. ej. "Ruta 10"),
   - lista de unidades ordenada por **`loc` ascendente**,
   - por ítem: **`placa` como título grande (la dirección)**; subtítulo pequeño y
     secundario con `orden` y `loc` (y `manzana` si existe).
7. Si el frame no tiene ítems → muestra **estado vacío** ("Ruta sin capturas aún;
   empieza a capturar").

## Flujos alternativos (sad paths)
- **A1 — Sin conexión al sincronizar**: `GET /field/routes` falla por red → la app
  muestra la **última lista cacheada** con aviso "sin sincronizar (offline)". No bloquea.
- **A2 — Abrir offline**: el worker toca una ruta sin red → la app abre con lo que haya
  **localmente** y avisa "abierta sin reanudar (offline)". Al recuperar red, reabrir
  sincroniza (idempotente).
- **B — Ingreso manual (fallback / mientras no exista el wire nuevo)**: el worker
  escribe/pega un `route_id` y **pulsa el botón "Abrir y reanudar"**; la app valida el
  UUID localmente y sigue desde el paso 4. (Vía distinta de interacción a la del happy
  path, que abre por **toque en la lista**.)
- **C — 401 (token ausente/inválido/expirado)**: SnackBar "Token vencido o inválido —
  renuévalo en Ajustes" + acción "Ajustes"; permanece en Home.
- **D — 404 (ruta de otra ESP o inexistente)**: SnackBar "Esa ruta no existe o no es de
  tu ESP"; no navega.
- **E — 400 (route_id no-UUID)**: en el fallback manual, se detecta **antes** de llamar;
  SnackBar "route_id inválido (debe ser UUID)".
- **F — Timeout / host inalcanzable**: SnackBar "Sin conexión con el backend" + acción
  "Reintentar".

## Reglas de negocio
- **BR1** Autorización: `require_field`, scoped a la ESP del token; rutas de otra ESP
  son invisibles (404). La app nunca asume acceso cross-ESP.
- **BR2** La app **valida el UUID** del `route_id` en el fallback manual antes de llamar.
- **BR3** Fusión al reanudar (idempotente por `client_id`):
  - ítem del servidor que no existe local → **insertar como `synced`**;
  - local `pending`/`error` (sin enviar) → **se preserva** (no se pisa la edición local);
  - local `synced` → se **actualiza** con `placa`/`loc`/`orden` del servidor.
- **BR4** **Orden estricto** de visualización = `loc` ascendente (`loc = orden × 5`,
  lo fija el backend). La app no reordena ni reasigna.
- **BR5** **Protagonismo de la dirección**: el dato principal por ítem es la **`placa`
  (dirección en lenguaje natural)**; el código `loc`/`orden` es metadato secundario.
  `placa` nula → mostrar "Sin dirección aún" (unidad creada sin placa, válida).
- **BR6** **Coordinate-free**: ningún dato mostrado o almacenado lleva coordenadas.
- **BR7** El `field_token` viaja **solo** como header `Authorization: Bearer`; nunca en
  la URL, query, logs ni telemetría.
- **BR8** Abrir una ruta la fija como **ruta activa** persistida; el Home ofrece
  "Continuar ruta activa" y sobrevive al reinicio.
- **BR9** La lista de rutas asignadas se **cachea localmente** para uso offline; se
  refresca en cada sincronización exitosa.

## Casos borde y manejo de errores
- Frame vacío (`items: []`) → estado vacío, **no** error.
- Reabrir la misma ruta varias veces → sin duplicados (BR3).
- Ruta con capturas locales `pending` que aún no existen en el servidor → se conservan y
  se muestran junto a las `synced` (marcadas visualmente como pendientes).
- Token válido pero por vencer → banner de aviso no bloqueante (días restantes).
- Respuesta con `placa=null` en varios ítems → todos muestran "Sin dirección aún".
- Lista de rutas vacía (worker sin rutas asignadas) → estado vacío "No tienes rutas
  asignadas en tu ESP".
- `total_capturado` ausente en el wire → badge oculto, no error.

## Criterios de aceptación
- La app muestra una lista de rutas asignadas obtenida de `GET /field/routes`, scoped a
  la ESP del token, ordenada por `codigo`, y la cachea para verse offline.
- Tocar una ruta llama `GET /field/capture/route/{route_id}` y navega a la vista de
  reanudar.
- La vista de reanudar ordena por `loc` ascendente y muestra **`placa` como título
  protagonista**; `orden`/`loc` como metadato secundario; `placa` nula → "Sin dirección
  aún".
- Frame vacío → estado vacío explícito (no lista en blanco, no error).
- 401 → mensaje de token + acción a Ajustes; 404 → mensaje de ruta no visible; 400
  (manual) → validación local previa; sin conexión → mensaje + "Reintentar". En todos,
  no se navega a reanudar.
- Reabrir una ruta no duplica y preserva capturas locales `pending`/`error`.
- La ruta abierta queda como activa y persiste tras reiniciar la app.
- Ningún campo de coordenadas aparece en request, almacenamiento ni UI.

## BDD (Gherkin)
```gherkin
Feature: Abrir y reanudar ruta

  Scenario: Sincronizar y listar rutas asignadas
    Given un field worker autenticado con token de la ESP Isnos
    When toca "Sincronizar"
    Then ve la lista de sus rutas ordenada por codigo, con su total capturado
    And la lista queda disponible offline

  Scenario: Abrir una ruta con capturas, dirección protagonista
    Given una ruta con 3 unidades capturadas (loc 5, 10, 15)
    When el worker toca esa ruta en la lista
    Then ve las 3 unidades ordenadas por loc ascendente
    And cada unidad muestra su placa como título y loc/orden como metadato secundario

  Scenario: Abrir una ruta vacía
    Given una ruta congelada sin capturas
    When el worker la abre
    Then ve el estado vacío "Ruta sin capturas aún; empieza a capturar"

  Scenario: Fallback manual con UUID inválido
    Given no hay wire de rutas asignadas disponible
    When el worker escribe "ruta-123" y pulsa "Abrir y reanudar"
    Then la app rechaza localmente con "route_id inválido (debe ser UUID)"
    And no llama al backend

  Scenario: Token expirado
    Given un field_token vencido
    When el worker abre una ruta
    Then la API responde 401
    And la app muestra "Token vencido o inválido — renuévalo en Ajustes" con acción a Ajustes

  Scenario: Ruta de otra ESP
    Given un token de la ESP Isnos
    When el worker intenta abrir por id una ruta de otra ESP
    Then la API responde 404
    And la app muestra "Esa ruta no existe o no es de tu ESP" y no navega

  Scenario: Reabrir preserva lo pendiente
    Given una unidad capturada localmente en estado pending (aún sin enviar)
    When el worker reabre la ruta y llega el frame del servidor
    Then la unidad pending se conserva sin ser pisada
    And las unidades synced se actualizan con placa/loc del servidor
```

## Tickets sugeridos
- **T1.0 (backend, prerrequisito) — `GET /field/routes`**: rutas asignadas scoped a la
  ESP del token, con `codigo`, `manzana_catastral`, `total_capturado`, `estado`.
  Gate: pytest (scoping por ESP, orden por codigo, sin coordenadas).
- **T1.1 (app) — Lista de rutas + sincronización**: consumir `GET /field/routes`,
  cachear local (drift), UI de lista con badge de progreso, estados offline/vacío.
- **T1.2 (app) — Abrir y reanudar**: `pullFrame` + `mergeFrame` (ya existe), navegación
  a la vista de reanudar; persistir ruta activa.
- **T1.3 (app) — Vista de reanudar (solo lectura)**: orden por `loc`, **placa como
  protagonista**, metadato secundario, estado vacío, marca de pendientes.
- **T1.4 (app) — Manejo de errores/estados**: mapear 401/404/400/timeout a mensajes y
  acciones (SnackBar + "Reintentar"/"Ajustes"); aviso de expiración de token.
- **T1.5 (app) — Fallback manual**: mantener ingreso manual de `route_id` con validación
  UUID mientras T1.0 no exista.
