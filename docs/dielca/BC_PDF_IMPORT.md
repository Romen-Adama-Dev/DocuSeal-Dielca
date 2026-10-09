# Importación DIELCA del PDF original de Business Central

Implementación en `feat/dielca-bc-pdf-import`, desplegada por autorización del usuario
el 09/10/2026. Servicio docuseal_app en worker3, imagen docuseal-dielca:3b52a75f.
Migraciones aplicadas; diseño 7 y técnico 4, --check-portal verificado.
Copia coherente previa con integridad SQLite verificada. Detalles operativos en
/home/dielca-server/informe-despliegue-conector.md. Falta publicar la API AL de BC.

## Contrato

`GET /api/dielca/v1/pdf_import_capabilities?layout_template_id=<id>` anuncia
version=1, mode=bc_pdf, idempotent=true, authorized_signer_selection=true,
customer_summary=true y límites si la integración está configurada.
Requiere X-Auth-Token del usuario técnico; no acepta sesión como alternativa.

`POST /api/dielca/v1/submissions_from_pdf`, multipart, mismos permisos. Parámetros:

- pdf: archivo PDF original, no URL ni base64.
- request_id: UUID en minúsculas de la solicitud BC.
- pdf_sha256: SHA-256 hexadecimal en minúsculas de los bytes originales.
- layout_template_id: ID de diseño aprobado en la configuración del servidor.
- document_name: texto obligatorio hasta 200 caracteres.
- signer_name: parámetro legado sin precarga; la selección se hace en el portal.
- customer: JSON con id/number/name/vat_registration_no/address/address2/post_code/city/county/country_code.
- authorized_signers: JSON de 1 a 50 autorizados con id/contact_number/name/job_title/id_document_no; IDs únicos y datos personales completos.
- order_number: texto opcional hasta 100 caracteres.
- customer_name: texto opcional hasta 200 caracteres.
- send_email y send_sms: ambos textos multipart `false` obligatorios.

`completed` está prohibido. El endpoint no usa email/phone, cuenta, URLs remotas,
campos o coordenadas enviados por el cliente. La cuenta procede del token.
La plantilla de diseño debe pertenecer a esa cuenta y ser accesible/activa.

Respuesta 201 (también en replay): request_id, submission_id, submitter_id,
pdf_sha256, sign_url, status=ready. Nunca imprimir sign_url ni el cuerpo completo.
Los errores contienen solo `error.code` controlado, sin excepciones originales.

Límites iniciales: 10 MiB, 30 páginas, PDF no cifrado, proporción de página entre
0.2 y 5. Presupuesto de 45 segundos comprobado entre páginas; no es un timeout
estricto de una llamada nativa a PDFium. Renderización secuencial para limitar
memoria; no se modifica el original. Se comprueba hash antes y después del upload.
Metadata estándar sha256 sigue en Base64 URL-safe; bc_pdf_sha256 es hexadecimal.

## Diseño y firma

La plantilla aprobada tiene un único rol y exactamente Nombre(text), DNI/NIF(text)
y Firma(signature), cada uno con áreas normalizadas válidas. Solo se copian sus
posiciones a la última página del original; no valores, condiciones o defaults.
Nombre/DNI son obligatorios y de solo lectura, rellenados desde el autorizado.
Firma sigue editable para la persona. El NIF del cliente se muestra por separado.
Confirmar en la revisión que no cubren totales/texto del documento de BC, incluidos
landscape/rotación. El endpoint no puede deducir zonas libres automáticamente.

Se crea una plantilla privada propia por solicitud con el original exacto y
previews de todas sus páginas, incluida la última más allá del rango upstream.
No se altera la plantilla de diseño. No hay envío de invitaciones ni contactos
email/SMS almacenados. Los documentos/resultados/auditoría se generan por el flujo
normal de DocuSeal cuando firma una persona.

La pantalla muestra los datos de cliente y un desplegable de autorizados. No
muestra el formulario de firma hasta seleccionar uno. `PATCH
/dielca/signing/authorized_signer` recibe el capability `signing_token` en el
cuerpo filtrado, nunca en la URL propia, y valida acceso y pertenencia a la lista.
Al elegir, rellena Nombre, DNI personal y cargo, guarda el ID y recarga la pantalla.
Cambiar de persona borra los valores anteriores, incluido el dibujo de firma.
No admite cambios tras completar, archivar, declinar o caducar. Desactiva reutilizar
firmas y delegar en estas importaciones. Sin JavaScript hay botón de confirmación.

`GET /api/dielca/v1/pdf_imports/:request_id` devuelve al técnico la identidad
seleccionada. El conector comprueba esta identidad contra los resultados y contra
los autorizados vigentes de BC antes de `markSignedAuthorized`.

SignedIdentity valida la selección antes de completar y mantiene el bloqueo del
firmante durante la actualización. Solo actúa sobre envíos Dielca::PdfImport.
Los envíos upstream conservan su comportamiento. DNI declarado no verifica identidad.

## Idempotencia y almacenamiento

Nueva tabla dielca_pdf_imports e índice único (account_id, request_id). Se crean
plantilla, adjuntos, envío, firmante y registro en la misma transacción. Mismo
request_id/hash/cliente/lista de autorizados/metadata/diseño devuelve los mismos IDs y enlace actual.
Contenido incompatible responde 409 IDEMPOTENCY_CONFLICT. Registro archivado
responde IMPORT_ARCHIVED; no se crea otro envío. Cambiar las coordenadas de la
plantilla no cambia firmas ya creadas ni el resultado de replays existentes.

Un fallo concurrente de SQLite se traduce en 503; reintentar con la misma clave.
Un índice único impide confirmar dos envíos para la misma clave. Storage no es
transaccional: se registran los blobs propios antes de subirlos y se borran tras
rollback. Una caída abrupta del proceso puede dejar objetos sin referencia;
revisar la política de limpieza de blobs huérfanos antes del despliegue. La limpieza
nunca borra objetos ajenos a esta llamada. Un fallo de indexado posterior a commit
permite recuperar el mismo envío repitiendo el endpoint.

## Procedimiento de activación

1. Revisar el código y ejecutar specs en BD/storage exclusivos de test, incluidos
   API upstream y OIDC. No usar SQLite ni mounts de producción para tests.
2. Elegir la plantilla ficticia de diseño y revisar áreas sobre el PDF real de BC.
3. Programar backup/migración y desplegar imagen revisada con autorización expresa.
4. Aplicar migraciones 20261009120000 y 20261009121000 en ese mantenimiento.
   Compilar/probar/publicar también la rama AL feat/autorizados-en-docuseal.
5. Configurar DIELCA_BC_USER_ID y DIELCA_BC_LAYOUT_TEMPLATE_ID en el portal. Son
   IDs públicos, no secretos. El importador queda deshabilitado sin ambos datos.
6. Configurar conector con DOCUSEAL_MODE=bc_pdf y el mismo ID de diseño. Verificar
   --check-portal y ejecutar una pasada del pedido ficticio OFV22/41067.

Una imagen que no incluye estos archivos no incorpora el importador al reiniciar.
La imagen 3b52a75f ya está construida y desplegada. El conector espera la API AL.

## Validación realizada y pendiente

31 specs del importador y sus servicios, 33 regresiones API/OIDC del portal y
2 pruebas JavaScript pasan. BD/storage exclusivos en contenedor de test sin red,
mounts ni credenciales reales. Se comprobaron bytes, hash, idempotencia, rollback,
previews, restricciones de notificaciones, selección, relleno, cambio de persona,
rechazo de identidad manipulada y finalización del formulario con datos readonly.

Compilación Webpack del formulario completada sin errores en el contenedor aislado.
No hay todavía prueba de navegador ni firma manual real.
Pendientes carrera concurrente real, reinicio abrupto, rotación/landscape y
verificación final del PDF firmado/auditoría. El importador activo pasa capacidades y el diseño cumple el contrato.
La API signatureAuthorizedSigners de BC sigue devolviendo 404; el conector espera
sin reservar solicitudes. Las pruebas completas requieren publicar esa extensión.

## Cambio local: firma libre para clientes sin autorizados

Pendiente de revisión/despliegue, no aplicado al servicio actual. No requiere
cambiar las acciones BC publicadas. El multipart admite authorized_signers=[]:
crea signer_mode=free; lista no vacía crea signer_mode=authorized. signer_mode
opcional debe coincidir con la lista si se envía. El snapshot/lista fija el modo,
se almacena en dielca_pdf_imports y no cambia después. La huella incluye la lista;
no se permite pasar de free a authorized reutilizando requestId.

En free: Nombre y DNI/NIF vacíos, editables, obligatorios; no hay desplegable y el
formulario de firma aparece directamente. La persona escribe ambos y firma.
Validación de finalización: nombre hasta 100 y DNI hasta 30 caracteres, strings
no vacíos, sin NUL. SignedIdentity sincroniza el nombre escrito antes de completar.
No se precarga el NIF de la empresa. En authorized se conserva el flujo previo.

Nueva migración 20261009122000: signer_mode, default authorized para los envíos
anteriores. Capacidades anuncia free_signing=true y comprueba esa columna. Rails
filtra values para evitar nombres/DNI en los logs de parámetros. Revisar y activar
portal y conector como una actualización compatible; no ejecutado en este cambio.

Verificación del cambio: 37 specs del importador/servicios y 33 regresiones API/OIDC
pasan en contenedor aislado, sin red, puertos, mounts de producción ni credenciales.
Se mantienen 2 pruebas JavaScript del desplegable. Falta prueba humana posterior
al despliegue revisado con OFV26/102186 y seguimiento markSigned en BC.
