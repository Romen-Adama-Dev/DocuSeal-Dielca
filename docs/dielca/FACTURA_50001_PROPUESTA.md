# Facturas 50001: perfil por tamaño del PDF

Perfil de facturas 50001: implementación y referencia de colocación.

El usuario indicó inicialmente usar el albarán para A5 y el pedido para A4;
después ajustó los tres campos en DocuSeal y pidió usar esa factura como referencia. `config/dielca_bc_layouts.json` define para `reports["50001"]`
un selector `paper_sizes`: A5 referencia el informe 50000 y A4 contiene un perfil propio, tomado de la
factura editada por el usuario en DocuSeal. El pedido 50002 conserva sus posiciones. DNI/NIF usa la misma coordenada x,
anchura, altura y fuente que Nombre; conserva su fila debajo.
No se añade un fallback global para otros informes de `PostedInvoice`.

`ReportLayout.for_page` identifica A5 o A4 a partir de las dimensiones en puntos
de la última página, admitiendo redondeos de hasta 3 puntos y ambas orientaciones.
El importador resuelve ese selector después de verificar la geometría del PDF y
antes de crear plantillas, documentos o envíos. Otros tamaños conservan el rechazo
`REPORT_LAYOUT_NOT_CONFIGURED`. Las referencias recursivas o mal configuradas
se rechazan, sin estimar posiciones nuevas.

Se reutilizan las coordenadas actuales del perfil seleccionado. Los campos
Nombre, DNI/NIF y Firma se colocan en la última página; conservan los modos
libre/autorizado, validación de identidad, confirmación de copia y hash original.
La repetición del mismo requestId no duplica el envío.

La vista ficticia admite ambos formatos:

```sh
PREVIEW_REPORT_ID=50001 PREVIEW_PAPER_SIZE=A5 PREVIEW_OUTPUT=/tmp/factura-a5.pdf bundle exec rails runner scripts/dielca_layout_preview.rb
PREVIEW_REPORT_ID=50001 PREVIEW_PAPER_SIZE=A4 PREVIEW_OUTPUT=/tmp/factura-a4.pdf bundle exec rails runner scripts/dielca_layout_preview.rb
```

Ejecutar exclusivamente en desarrollo/pruebas con datos ficticios. La vista muestra
las posiciones heredadas sobre un documento sintético; no prueba la ausencia de
solapamiento con todos los textos de una factura real.

Pruebas añadidas: selección A5/A4 en ambas orientaciones, geometría inválida,
tamaño no admitido, configuración recursiva, importación libre y autorizada de
una o tres páginas (con páginas previas de otro tamaño), coordenadas correctas,
ubicación en última página e idempotencia.

Se copiaron únicamente coordenadas y tamaños de fuente de los campos editados
por el usuario, sin datos de cliente ni valores de firma. No se han incluido PDF ni datos personales
en Git. Esta revisión sustituye la referencia inicial al pedido A4 por un perfil propio
de factura. Cada envío creado conserva sus áreas; modificar el perfil no recoloca
los envíos existentes ni sus documentos firmados. La versión activa se registra
en el informe de despliegue del servidor.

Verificación completada: 106 ejemplos RSpec de servicios DIELCA e importación
sin fallos, en PostgreSQL/storage aislados. Generadas y revisadas las vistas
ficticias A5 y A4. Comprobación git diff --check correcta.
