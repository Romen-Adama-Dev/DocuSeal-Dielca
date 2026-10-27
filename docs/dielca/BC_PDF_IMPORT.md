# Importación DIELCA del PDF original de Business Central

Registro histórico de la implementación en `feat/dielca-bc-pdf-import`, desplegada por autorización del usuario
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

`completed` está prohibido. El endpoint no usa email/phone como identificadores del firmante, cuenta, URLs remotas,
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
   --check-portal y ejecutar una pasada del pedido ficticio PED-DEMO.

Una imagen que no incluye estos archivos no incorpora el importador al reiniciar.
En la revisión inicial se construyó y desplegó 3b52a75f. Ese registro histórico no
certifica la imagen actual ni el estado actual de la API AL; este cambio es local.

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
formulario de firma se habilita tras validar identidad y confirmar la copia (véase BC 0.4 abajo).
Validación de finalización: nombre hasta 100 y DNI hasta 30 caracteres, strings
no vacíos, sin NUL. SignedIdentity sincroniza el nombre escrito antes de completar.
No se precarga el NIF de la empresa. En authorized se conserva el flujo previo.

En modo libre, el documento se presenta como «DNI/NIE» y se valida en navegador y
servidor mediante letra de control: DNI, NIE X/Y/Z y NIF personales K/L/M.
Se normaliza a mayúsculas, eliminando espacios, puntos, guiones, barras,
guiones bajos y el prefijo ES. Un CIF válido se reconoce como empresa y se rechaza
como identidad del firmante. No se puede completar con un documento inválido.
El valor normalizado se conserva para el PDF, la auditoría y el retorno a BC.
El nombre interno del campo sigue siendo DNI/NIF para conservar el contrato API.
Las firmas libres abiertas anteriores reciben también la validación del navegador
al cargar el formulario; no se modifican documentos ya firmados.

El conector transforma customerIdType de BC a customer.id_type: CIF muestra
«Empresa» y DNI/NIE/NIF muestran «Persona física». Datos del cliente y tipo son
de solo lectura; no se infiere ni se sustituye el documento personal desde el cliente.
Sin tipo conocido se indica que no está especificado. No hay migraciones nuevas
para este cambio ni debe modificarse SQLite en producción; cualquier migración
posterior requiere copia consistente de SQLite antes de ejecutarla y revisión.

Nueva migración 20261009122000: signer_mode, default authorized para los envíos
anteriores. Capacidades anuncia free_signing=true y comprueba esa columna. Rails
filtra values para evitar nombres/DNI en los logs de parámetros. Revisar y activar
portal y conector como una actualización compatible; no ejecutado en este cambio.

Verificación del cambio: 37 specs del importador/servicios y 33 regresiones API/OIDC
pasan en contenedor aislado, sin red, puertos, mounts de producción ni credenciales.
Se mantienen 2 pruebas JavaScript del desplegable. Falta prueba humana posterior
al despliegue revisado con PED-DEMO y seguimiento markSigned en BC.

## BC 0.4: identidad previa, cajas por informe y copia confirmada

Cambio local pendiente de revisión y despliegue. No añade migraciones, secretos,
volúmenes ni dependencias. Conserva SQLite y los avisos/licencia AGPL existentes.
Antes de cualquier migración pendiente del despliegue, realizar una copia consistente
completa de SQLite y sus documentos; nunca usar la BD de producción para pruebas.

### Contrato que debe reenviar el conector

El multipart del importador admite `report_id` / `reportId` (identificador positivo),
`document_type` / `documentType` (`SalesOrder`, `PostedShipment`, `PostedInvoice`),
`document_number` / `documentNumber`, `customer.email` o `customerEmail`,
`authorized_signers[].email`, y `copy_email_required` / `copyEmailRequired` (booleano
JSON o texto `true` / `false`). `customerIdType` sigue entrando como `customer.id_type`.
El conector debe reenviar estos campos: recibirlos de BC no basta si los descarta
al construir el multipart. Los aliases raíz se aceptan para facilitar esa actualización.

Sin política explícita la copia es obligatoria, incluidos envíos abiertos antiguos.
La huella idempotente incluye estos datos. No reutilizar un requestId cambiando
informe, tipo, correo, política o snapshot: se devuelve `IDEMPOTENCY_CONFLICT`.
Un envío ya creado conserva sus áreas; editar el JSON no recoloca envíos existentes.

### Identidad y acceso a la firma

Tanto el modo libre como el autorizado requieren documento personal válido. Un
snapshot autorizado con documento vacío, inválido o CIF no se puede seleccionar;
corregir la ficha en BC y crear una solicitud nueva. El cliente y su tipo siguen
siendo solo lectura. Nunca se toma su CIF como DNI del firmante.

Antes de mostrar el formulario de firma se valida Nombre/DNI y se confirma el correo.
El servidor bloquea también la subida de dibujos y los valores de firma enviados
sin esta confirmación. Al completar vuelve a comprobar DNI y destinatarios.
Cambiar de autorizado borra el dibujo y la confirmación anterior. No se modifican
PDF ni auditorías de documentos ya completados.

### Configuración de colocación

Archivo por defecto: `config/dielca_bc_layouts.json`. Se puede usar otro JSON mediante
`DIELCA_BC_LAYOUTS_FILE`, montado de solo lectura y accesible al usuario del contenedor.
No contiene credenciales. El Dockerfile ya incluye la carpeta config; no es necesario
cambiarlo. La pila actual no necesita cambios para el archivo incluido.

Orden: `reports[reportId]`, después `document_types[documentType]`. Si ambos identificadores
faltan, se conserva el diseño de la plantilla permitida para clientes antiguos.
Si se informa un identificador pero no hay perfil aplicable, se rechaza el import con
`REPORT_LAYOUT_NOT_CONFIGURED`. No se estima una posición genérica.

Cada perfil contiene `box: {x,y,w,h}` en fracciones de página con origen arriba a la
izquierda y `fields` con Nombre, DNI/NIF y Firma. Las áreas de esos campos son fracciones
de la caja. Se validan límites y solapamientos. `font_size` se expresa en puntos.
Los tres campos se colocan en la última página. El nombre y DNI quedan en una línea:
se reduce la fuente si es necesario sin recortar su valor; si no cabe, se rechaza.
Los nombres no admiten saltos de línea. Revisar legibilidad de nombres muy largos.

Perfil 50000 / PostedShipment: selección A5/A4 por tamaño de última página. A5 horizontal: recuadro inferior izquierdo debajo
de las cifras de impuestos. La revisión del 27/10/2026 toma las coordenadas del
último albarán firmado: firma arriba y Nombre/DNI debajo; véase la sección de
posiciones aprobadas y fecha/hora al final de este documento. No se guardan
los PDFs reales ni sus datos personales en el repositorio.

Informe 50002 / SalesOrder: por indicación expresa del usuario se conserva la
posición ya utilizada en los pedidos anteriores de la plantilla 7. Nombre:
x=0.09, y=0.792, w=0.55, h=0.018; DNI/NIF: x=0.09, y=0.832, w=0.22, h=0.019;
Firma: x=0.34, y=0.815, w=0.33, h=0.05. Se mantienen en la última página.

Informe 50001 / PostedInvoice: por indicación del usuario se selecciona el perfil
según el tamaño de la última página del PDF: A5 usa la colocación A5 del albarán 50000 y A4 usa un
perfil propio con las posiciones editadas por el usuario en DocuSeal. El diseño
del pedido 50002 se conserva. Se admiten ambas orientaciones y hasta 3 puntos de diferencia por
dimensión para el redondeo habitual del PDF. Otros tamaños se rechazan con
REPORT_LAYOUT_NOT_CONFIGURED. El selector se resuelve antes de crear el envío;
las facturas ya importadas conservan sus campos. La versión activa se registra
en el informe de despliegue del servidor.

Vista de revisión con datos ficticios (solo entorno aislado test/desarrollo):
`bundle exec rails runner scripts/dielca_layout_preview.rb` genera
`/tmp/dielca-layout-preview.pdf`. `PREVIEW_REPORT_ID`, `PREVIEW_PAPER_SIZE` (`A5`/`A4`) y `PREVIEW_OUTPUT` permiten elegir
perfil, tamaño y destino. No lee fichas, firmantes ni documentos reales; no escribe en la BD.

### Copia y retorno al conector

Propuesta: correo del autorizado elegido, o correo del cliente. Se confirma mediante
«Es correcto» o se cambia; si está vacío, introducir uno válido. Se pueden añadir
cuatro destinatarios adicionales (cinco en total). Solo `copyEmailRequired=false`
permite «Sin copia por correo». El servidor valida formato, cantidad y ausencia de
inyección de cabeceras. Los adicionales se envían como BCC para no revelar direcciones.

Se guarda `submitter.metadata.dielca_copy_email`: `confirmed`, `confirmed_at`, `skipped`,
`primary`, `changed`, `additional`, `recipients` y `status`. Se devuelve también en
`GET /api/dielca/v1/pdf_imports/:request_id`, autenticado con el usuario técnico.
No poner este contenido ni enlaces de firma en logs/Git. El endpoint de firma exige
el token del envío, autorización del formulario y CSRF; no es una API técnica para BC.

Tras generar PDF y auditoría, el job de copia usa el SMTP existente configurado por
entorno o ajustes nativos del portal. Adjunta PDFs firmados y auditoría separada;
asunto `Documento firmado: <tipo> <nº>`. No duplica el correo nativo para estos imports.
No se ha comprobado ni modificado SMTP en producción y no se han enviado correos reales.

Estados: `pending` (en cola), `sending`, `sent` (SMTP aceptó; no implica recepción),
`connector_pending` (sin SMTP), `skipped`, `failed` (requiere revisión). Con
`connector_pending`, el conector debe leer los destinatarios y asumir el envío,
evitar duplicados y registrar su resultado en su propio sistema. Este cambio del
portal no implementa transporte de correo dentro del repositorio del conector.

No se reenvían jobs duplicados. Un fallo SMTP o interrupción durante `sending` requiere
conciliación manual antes de reintentar: no se promete entrega exactamente una vez.
El procesamiento usa el worker ya existente; comprobar su ejecución tras un despliegue
revisado. No habilitar SMTP, cambiar proxy ni desplegar como efecto de esta edición.

Verificación BC 0.4: 128 ejemplos RSpec del importador, identidad, layouts, correo y
regresiones API/OIDC; 32 pruebas JavaScript. Se usaron SQLite y storage ficticios en
contenedor sin red, puertos ni volúmenes de producción. PDFs A5 horizontales de una
y tres páginas se renderizan con los campos en la última página. La vista ficticia
permite revisar la caja; no equivale a validar el diseño real de BC. Webpack compilado.

### Pedido: posiciones aprobadas y fecha/hora de firma (27/10/2026)

El perfil `50002` y el fallback `SalesOrder` toman las posiciones de Nombre,
DNI/NIF y Firma del último pedido A4 firmado y editado en el portal. Se han copiado
solo coordenadas y tamaños; no contiene PDF, identificadores ni datos del cliente.
El perfil `50000` y el fallback `PostedShipment` incorporan también la colocación
del albarán A5 firmado durante la revisión: firma encima de Nombre y DNI en el
recuadro inferior izquierdo. Las facturas A5 que referencian ese perfil heredan
sus posiciones; la colocación propia de factura A4 se conserva. En el albarán no
se sustituye la fecha de documento de la cabecera por la hora de firma.

El pedido añade `signed_at: {x,y,w,h,font_size,valign}` al perfil JSON, en fracciones de
la misma caja `box`. Es opcional: omitirlo conserva los tres campos habituales.
Se valida también su geometría y la ausencia de solapamientos. La plantilla de
referencia autorizada sigue teniendo tres campos; el importador añade el cuarto
campo generado cuando lo indica el perfil.

La zona a la derecha del rótulo «Fecha» del documento revisado es demasiado
estrecha para fecha y hora legibles. El sello ocupa dos líneas inmediatamente
encima de ese rótulo, dentro del recuadro de conformidad, separado de Nombre,
DNI y dibujo. Formato `dd/mm/aaaa` y `HH:mm:ss`, fuente de 6 puntos configurada
por perfil. Nombre, DNI y fecha/hora usan la misma altura de caja, tamaño inicial
y alineación inferior (`valign: bottom`); la última línea de la fecha/hora se alinea
con los otros valores. La firma está centrada sobre las tres columnas. En albaranes,
Nombre y DNI comparten también altura y alineación inferior. El perfil acepta
`top`, `center` o `bottom`, con `center` por defecto para diseños anteriores.
Aparece en la última página del PDF original, antes de la auditoría.

`Fecha y hora de firma` es un campo de texto readonly, no obligatorio para el
firmante. El servidor lo rellena al finalizar con el mismo `completed_at` que
registra DocuSeal, convertido a `Atlantic/Canary` con cambio automático de hora
estacional. No acepta el reloj ni un valor enviado por el navegador. El dato
queda guardado en los valores del envío: generar el PDF o enviarlo por correo
más tarde conserva la hora de firma, no estampa la hora de ese proceso posterior.

Se aplica a nuevas importaciones después de desplegar esta revisión. No cambia
plantillas/envíos ya creados ni reescribe documentos completados o sus auditorías.
No añade migraciones, variables, secretos ni dependencias. No se ha desplegado
ni se ha hecho push durante esta edición. Cualquier despliegue posterior requiere
la revisión y copia consistente de SQLite y documentos acordadas.

Validado con datos ficticios: pedidos A4 de una y tres páginas, fecha/hora de
invierno y verano, rechazo de fecha forjada, persistencia posterior y renderizado
sin solapamiento de las cuatro áreas.

### Logotipo corporativo en la estampa

Los perfiles admiten `logo: {x,y,w,h}` en fracciones de la caja `box`. La zona
se comprueba contra Nombre, DNI, fecha y firma: no se permiten solapamientos.
El pedido A4 y la factura A4 reservan una franja encima del dibujo; el albarán A5
sitúa el logotipo a su lado, dentro del recuadro de conformidad. Las coordenadas
se congelan al importar, junto a las áreas de la firma.

Se utiliza `public/dielca/logo.png`, idéntico al PNG proporcionado por DIELCA.
Se conserva completo, con transparencia, proporciones y colores, incluido el verde
de Renovables. Se incorpora al resultado antes de la firma criptográfica del PDF.
La firma manuscrita del cliente y los datos de identidad/fecha se conservan.
No añade campos editables, servicios ni dependencias; no cambia el PDF original.
Los diseños antiguos sin zona de logo siguen su renderizado anterior. Solo los
envíos registrados por el importador DIELCA utilizan este añadido. Los documentos
ya firmados y almacenados no se modifican. Cambio local pendiente de despliegue.


### Albarán A4: fecha junto a «Fecha» en la franja de recibí (27/10/2026)

La última revisión detectó un albarán 50000 en A4, distinto del A5 y del pedido
50002. El 50000 y el fallback PostedShipment seleccionan ahora su perfil A4 o A5
por el tamaño de la última página. Las facturas A5 conservan su perfil anterior.
En A4, Nombre y DNI conservan las columnas observadas, con sus cajas alineadas; la firma se contiene
en la franja inferior y la fecha/hora se coloca inmediatamente después del
rótulo «Fecha», en dos líneas de 4 puntos por el ancho disponible. Caja:
`x=0.480, y=0.8915, w=0.041, h=0.0175`, fracciones de página. No se modifica
la fecha de documento de la cabecera. No se añade otro logo dentro de esa
franja estrecha: el informe A4 ya incorpora el logotipo corporativo.

La imagen activa observada era `docuseal-dielca:e09ce33d`, sin este estampado.
Esta corrección requiere revisar y desplegar la nueva imagen antes de importar
nuevos documentos. No modifica plantillas ya importadas ni PDFs ya firmados.
Las pruebas usan albaranes y pedidos ficticios de una y tres páginas, comprueban
la hora de finalización del servidor y rechazan una fecha impuesta desde el navegador.
No hay migraciones ni cambios de infraestructura. Mantener copia consistente de
SQLite y documentos antes del despliegue, según el procedimiento operativo.


### Fecha de firma en todos los perfiles BC

Se habilita el campo readonly de fecha/hora también en albaranes A5 y facturas
A5/A4. En A5 se reserva espacio bajo el logo y junto al dibujo, encima de Nombre
y DNI. En factura A4 se sitúa bajo las dos líneas de identidad. PostedInvoice
admite el mismo selector que 50001 cuando BC no facilita reportId. Son posiciones
iniciales configurables: revisar cada muestra con el diseño de informe correspondiente.
Los cinco perfiles cubiertos son albarán A4/A5, factura A4/A5 y pedido A4; no se
extrapola un pedido A5 sin disponer de su diseño. Todos usan la última página y
la fecha de finalización persistida por el servidor en Atlantic/Canary.
