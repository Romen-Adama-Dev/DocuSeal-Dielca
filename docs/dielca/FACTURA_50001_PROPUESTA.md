# Facturas 50001: perfil por tamaño del PDF

Estado: implementación local para revisión, sin despliegue ni push.

El usuario indicó usar como referencia el albarán para facturas A5 y el pedido
para facturas A4. `config/dielca_bc_layouts.json` define para `reports["50001"]`
un selector `paper_sizes`: A5 referencia el informe 50000 y A4 referencia 50002.
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

La lectura del PDF de BC devolvió HTTP_404 durante esta tarea, por lo que el diseño
real queda pendiente de revisión visual. No se han incluido PDF ni datos personales
en Git. Tras revisar y autorizar el despliegue en otro paso, se podrá reintentar en
BC la solicitud que quedó en Error. El despliegue actual todavía carece del perfil.

Verificación completada: 106 ejemplos RSpec de servicios DIELCA e importación
sin fallos, en PostgreSQL/storage aislados. Generadas y revisadas las vistas
ficticias A5 y A4. Comprobación git diff --check correcta.
