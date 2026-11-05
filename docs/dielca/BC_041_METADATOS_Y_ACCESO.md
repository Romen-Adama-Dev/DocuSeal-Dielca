# BC 0.4.1.0: metadatos y preparación de acceso

Cambios locales revisables, no desplegados. No hay push ni cambios de permisos
activos como consecuencia de esta preparación. Se conserva AGPLv3 y atribución.

## Flujo implementado

El conector mantiene todas las delegaciones en su cola de servicio. Congela los
metadatos en el snapshot de creación y los entrega al importador autenticado:

| Campo BC | Parámetro del importador / clave en metadata |
| --- | --- |
| locationCode | location_code |
| channel | channel |
| routeId | route_id |
| routeDescription | route_description |
| requestedBy | requested_by |

Los códigos se conservan exactamente, sin convertir mayúsculas ni quitar espacios.
El importador valida tipo, longitud y caracteres de control; solo acepta Counter
(incluye recogidas) o Delivery como canal no vacío. No acepta estos datos desde
el formulario público de firma. requestedBy es procedencia del empleado, nunca
prueba de identidad ni autorización del firmante del cliente.

Los metadatos forman parte del fingerprint: repetir la misma solicitud reutiliza
el envío; cambiar su almacén/ruta/canal/solicitante devuelve conflicto sin alterar
el original. Los snapshots anteriores sin estos campos siguen siendo reutilizables:
se omiten valores opcionales vacíos. No se enriquecen retroactivamente documentos
firmados ni se sustituyen sus PDFs/auditorías. Los parámetros se filtran en logs.

El portal anuncia `bc_scope_metadata: true`. El conector devuelve
PORTAL_BC041_REQUIRED antes de claim si una solicitud con almacén llega a un
portal que no anuncia esa capacidad. Se conserva PORTAL_BC04_REQUIRED para las
funciones anteriores; las fases posteriores de firmas existentes no dependen
de estos gates.

## Política preparada y acceso que sigue sin activarse

`Dielca::DocumentAccess` reúne la política del portal para su futura entrada de
negocio: grupos exactos, prioridad admin > mostrador > reparto, tipo/informe,
estado y almacén fiable. El estado debe resolverse desde el servidor, no desde
el navegador. Mostrador admite SalesOrder/50002, PostedShipment/50000 y
PostedInvoice/50001 en su almacén, para Counter y Delivery. SalesQuote se deniega.
Sin grupo de la aplicación, sin mapeo válido o con estado desconocido: denegar.
Un firmado no admite preparar/abrir otra firma. Documentos antiguos sin almacén
o sin mapeo: solo admin explícito del ámbito. Admin global no es rol de negocio.

Reparto sigue denegado en el portal hasta acordar y conectar identidad ↔ ruta.
La puerta del conector exige además PostedShipment + Delivery + routeId y una
regla de servidor confirmada; no se habilita por tener un ID o grupo conocido.

La consola nativa conserva su acceso existente. `NativeConsoleAccess` impide
que añadir los grupos de negocio por error a la allowlist cree admins nativos.
NO ampliar DOCUSEAL_OIDC_ALLOWED_GROUPS para estos grupos.

**Límite pendiente de integración:** la política está probada, pero todavía no
hay una sesión OIDC de negocio ni adaptadores HTTP para listados/búsquedas,
firma mediada, descarga/auditoría y administración que la apliquen. Las rutas
nativas siguen siendo de consola, no un portal restringido para empleados.
No habilitar Mostrador/Reparto ni anunciar RBAC activo hasta completar esas rutas,
consulta de grupos vigentes, revocación y pruebas por URL directa. Las operaciones
humanas no implementadas en el conector se deniegan. La credencial del conector
identifica un servicio, nunca al empleado.

## Configuración privada del servidor

Ambos repositorios aceptan:

- DIELCA_BC_SITE_LOCATIONS_FILE: ruta legible a un JSON privado (prioritaria).
- DIELCA_BC_SITE_LOCATIONS: el mismo JSON como alternativa de servidor.

Ejemplo ficticio (no utilizar como valor real):

```json
{"el-sebadal": ["SITE-DEMO-01", "SITE-DEMO-02"]}
```

El mapeo real confirmado se ha preparado en
`/home/dielca-server/.config/dielca/firmas-informes-site-locations.json`, fuera de
Git y con permisos 0600. No está montado ni cargado en los servicios activos.
En Swarm debe añadirse como config de solo lectura y establecer la variable
_FILE a su ruta dentro del contenedor; una ruta del host no basta. Configuración
inválida, archivo inaccesible o JSON mayor de 10 KB: denegar, sin imprimirlo.
No volver a pedir el código ya confirmado ni guardarlo en el navegador.

## Despliegue a revisar después

1. Confirmar extensión BC 0.4.1.0 publicada en Pruebas; solo consta compilación.
   Las solicitudes antiguas no reciben almacén por publicar la extensión.
2. Respaldar SQLite/volúmenes del portal y estado del conector. Este cambio no
   añade migraciones ni tablas; no se ha tocado la base de producción.
3. Construir imágenes inmutables y revisar el diff de ambos repositorios.
   Actualizar primero docuseal_app (imagen disponible en worker3) y validar
   HTTPS /up + capacidad bc_scope_metadata; actualizar después
   dielca-firma_connector. No cambiar redes/puertos/proxies/DNS ni allowlist OIDC.
4. Montar configuración privada solo al integrar la entrada de negocio. Mantener
   Reparto denegado hasta aprobar la correspondencia de rutas.
5. Probar en Pruebas con documentos e identidades ficticios, incluyendo
   reintentos, retirada de grupo, almacén desconocido y acceso por ID directo.
   Nunca importar PDFs/clientes/empleados reales al repo o a los tests.

Compilar BC o terminar estas pruebas locales no autoriza un despliegue automático.


## Validación local completada

- Conector: `.venv/bin/pytest -q` — 216 pruebas, sin fallos.
- Portal: 91 ejemplos, sin fallos, en contenedor sin red con SQLite/almacenamiento
  de pruebas. Suites: document_access, native_console_access, dielca_pdf_import
  y authentik_oidc. Incluyen importación autenticada, metadatos exactos,
  reintentos/conflictos, compatibilidad antigua, OIDC y configuración privada.
- `git diff --check` correcto en ambos repositorios.

No se ha modificado la extensión BC ni se ha supuesto que ya esté publicada.
No se han ejecutado migraciones, solicitudes, firmas ni envíos de correo reales.
