# Importación DIELCA del PDF original de Business Central

Implementación local en `feat/dielca-bc-pdf-import`. No aplicada al servicio actual.
No se ha migrado SQLite de producción ni cambiado imagen, servicios o volúmenes.

## Contrato

`GET /api/dielca/v1/pdf_import_capabilities?layout_template_id=<id>` anuncia
version=1, mode=bc_pdf, idempotent=true y límites si la integración está configurada.
Requiere X-Auth-Token del usuario técnico; no acepta sesión como alternativa.

`POST /api/dielca/v1/submissions_from_pdf`, multipart, mismos permisos. Parámetros:

- pdf: archivo PDF original, no URL ni base64.
- request_id: UUID en minúsculas de la solicitud BC.
- pdf_sha256: SHA-256 hexadecimal en minúsculas de los bytes originales.
- layout_template_id: ID de diseño aprobado en la configuración del servidor.
- document_name: texto obligatorio hasta 200 caracteres.
- signer_name: texto opcional hasta 200 caracteres, precarga editable de Nombre.
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
La firma se exige a una persona y los campos Nombre/DNI son obligatorios/editables.
Confirmar en la revisión que no cubren totales/texto del documento de BC, incluidos
landscape/rotación. El endpoint no puede deducir zonas libres automáticamente.

Se crea una plantilla privada propia por solicitud con el original exacto y
previews de todas sus páginas, incluida la última más allá del rango upstream.
No se altera la plantilla de diseño. No hay envío de invitaciones ni contactos
email/SMS almacenados. Los documentos/resultados/auditoría se generan por el flujo
normal de DocuSeal cuando firma una persona.

El módulo propio SignedIdentity se inserta antes de assign_completed_attributes
de Submitters::SubmitValues y únicamente actúa sobre envíos registrados en
Dielca::PdfImport. Sincroniza el nombre escrito antes de defaults/sellos y
procesamiento de finalización. Las solicitudes upstream conservan su comportamiento.
No afirma que la escritura del DNI verifique identidad.

## Idempotencia y almacenamiento

Nueva tabla dielca_pdf_imports e índice único (account_id, request_id). Se crean
plantilla, adjuntos, envío, firmante y registro en la misma transacción. Mismo
request_id/hash/identidad/metadata/diseño devuelve los mismos IDs y enlace actual.
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

## Activación propuesta, sin ejecutar

1. Revisar el código y ejecutar specs en BD/storage exclusivos de test, incluidos
   API upstream y OIDC. No usar SQLite ni mounts de producción para tests.
2. Elegir la plantilla ficticia de diseño y revisar áreas sobre el PDF real de BC.
3. Programar backup/migración y desplegar imagen revisada con autorización expresa.
4. Aplicar migración 20261009120000_create_dielca_pdf_imports en ese mantenimiento.
5. Configurar DIELCA_BC_USER_ID y DIELCA_BC_LAYOUT_TEMPLATE_ID en el portal. Son
   IDs públicos, no secretos. El importador queda deshabilitado sin ambos datos.
6. Configurar conector con DOCUSEAL_MODE=bc_pdf y el mismo ID de diseño. Verificar
   --check-portal y ejecutar una pasada del pedido ficticio OFV22/41067.

Una imagen que no incluye estos archivos no incorpora el importador al reiniciar.
No se ha construido ni desplegado imagen en este encargo.

## Validación pendiente

Sintaxis Ruby revisada mediante ruby -c, sin arrancar Rails ni abrir sus datos.
Specs escritos: contrato multipart/capacidades, bytes originales, hash, replay,
conflictos, notificaciones/autocompletado, token/sesión/aislamiento, allowlist,
rollback, precarga, preview de 17 páginas, PDF cifrado/inválido, geometría y nombre
sincronizado solo para importaciones. Aún no ejecutados mientras se prepara la
configuración. Pendientes también carrera concurrente real, reinicio abrupto,
rotación/landscape y generación final de PDF/auditoría tras firma manual.
