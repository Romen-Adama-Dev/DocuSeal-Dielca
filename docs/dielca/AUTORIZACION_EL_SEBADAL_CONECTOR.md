# Integración de autorización de Firmas e Informes

Preparación local del 29/10/2026. No desplegada, sin cambios de acceso,
provisión, notificaciones, proxy ni proveedor OIDC.

Contrato y código del conector:
`/home/dielca-server/Dielca-Firma-Conector/CONTRATO_AUTORIZACION_EL_SEBADAL.md`.
Define una puerta de operaciones humanas separada de la cola de servicio y de
la consola nativa de DocuSeal, con aserciones firmadas de un solo uso, sesión
vigente, identidad `(issuer, sub)` y política de rol/delegación/documento.

La preparación del conector contiene una política denegada por defecto, un
verificador de aserciones RS256, control de repetición y comprobaciones antes y
después de claim. La preparación humana reutiliza hash, snapshot y correlación
de la solicitud. No altera el seguimiento de firmas ni la copia posterior.

Faltan decisiones y adaptadores antes de activar acceso documental:

- Publicación de BC 0.4.1.0 en Pruebas y regla de asignación de reparto.
  El campo `locationCode` y la correspondencia del almacén ya están confirmados;
  el valor real permanece en configuración privada del servidor.
- Sesión de negocio con login OIDC verificado, grupos vigentes y correspondencias
  corporativas explícitas. No aprovisionar estos roles como usuarios admin nativos.
- Emisor/audience/clave de aserciones de operación, distintos del token compartido
  del conector y de los ID tokens de la consola.
- Endpoints de negocio con autorización de listados, recuentos, búsquedas, URLs
  directas, firma mediada y proxy de PDF/auditoría. No devolver URLs bearer
  permanentes para sustituir la autorización ni filtrar solo en JavaScript.
- Verificación equivalente dentro de BC en sus transacciones y permission sets.

Hasta entonces, la puerta nueva no se conecta a rutas HTTP y sus operaciones
no implementadas se deniegan. Este trabajo no concede acceso a ningún miembro
de los grupos recién provisionados.

## Protección preparada de la consola nativa

`Dielca::NativeConsoleAccess` excluye los grupos
`DIELCA/FirmasInformes/*` de la allowlist que permite aprovisionar/iniciar sesión
en la consola nativa. Se aplica en el controlador, antes de buscar o crear usuarios.
Esto evita que una ampliación accidental de configuración convierta Mostrador,
Reparto o Admins del ámbito en administradores nativos sin restricciones.

Los administradores globales ya permitidos por la configuración de la consola
mantienen esa vía de acceso; eso no les concede un rol en la política de negocio.
Una allowlist vacía o un claim groups de tipo inválido se deniegan. No se cambia
el valor configurado en Swarm ni se incorporan nuevos grupos a la allowlist.

La vinculación y grupos actuales de la sesión de negocio no se obtienen de una
cookie o JSON sin verificar; tampoco se deducen del correo o del rol nativo.
El cliente que firma sigue siendo distinto del empleado que tramita el documento.

La implementación usa controles propios abiertos, sin activar funciones de pago
ni eludir licencias. Se conserva la licencia/atribución AGPL y la entrega de fuente.

La adaptación BC 0.4.1.0 añade conservación de almacén/canal/ruta y empleado,
control idempotente y la política reutilizable `Dielca::DocumentAccess`, con
configuración de almacenes exclusivamente del servidor. Su existencia no conecta
por sí sola los endpoints de negocio ni activa accesos; no anunciar autorización
por documento en todas las rutas hasta completar esa integración.

Ver [BC_041_METADATOS_Y_ACCESO.md](BC_041_METADATOS_Y_ACCESO.md). Las pruebas usan
SQLite y almacenamiento aislados, usuarios ficticios y ninguna llamada a producción.
