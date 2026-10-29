# Factura registrada 50001: bloque inferior izquierdo

El perfil del informe 50001 ya existía antes de esta revisión. Se ha ajustado
su variante A4 para reunir Nombre, DNI/NIF, Firma, logo y fecha/hora dentro del
recuadro inferior izquierdo, bajo los datos de pago. El perfil anterior dejaba
la firma en el recuadro central. Solo se han utilizado medidas de una referencia
local para revisar el diseño: no se copia ningún PDF, identidad, dato bancario
ni valor de firma al repositorio ni a las pruebas.

`config/dielca_bc_layouts.json` mantiene el selector A4/A5 del informe 50001:

- A4: textos alineados a la izquierda; logo y firma alineados en la columna
  derecha del mismo bloque. Las áreas quedan entre x=0.082195 y x=0.354 y entre
  y=0.809 e y=0.873, en fracciones de página. El recuadro central queda libre.
- A5: conserva la configuración compartida con el albarán A5, aprobada en la
  fase anterior. Esta revisión no dispone de una factura A5 independiente;
  su colocación debe revisarse con ese informe si se utiliza.

Los campos se insertan solo en la última página del documento original. Se
mantienen la identidad válida, selección de autorizado, confirmación de copia,
hash original e idempotencia. La fecha/hora procede de completed_at y se guarda
en horario Atlantic/Canary. Los envíos ya importados o firmados no se recolocan.

## Informes sin perfil

Un reportId explícito debe existir en reports. Si no existe, no se usa el
fallback de documentType. El fallback solo se permite cuando no hay reportId.
Un tamaño de página no configurado también se rechaza. En ambos casos, la API
responde HTTP 422 con error.code=REPORT_LAYOUT_NOT_CONFIGURED, error.message en
español y error.portal_url. No crea plantillas, archivos ni envíos incompletos.

La página /dielca/import-error muestra la explicación en el portal, con el logo
DIELCA y la atribución original. Es estática, no acepta identificadores de
clientes, enlaces de firma ni textos de error arbitrarios y no se almacena en
caché. El conector debe mostrar error.message y ofrecer error.portal_url al
usuario; esta revisión no modifica el conector ni la extensión de BC. El código
de error existente se conserva para no romper su tratamiento de reintentos.

## Validación y muestras

Las pruebas generan PDF ficticios de una y tres páginas, A4/A5, incluidos
PDF mixtos. Comprueban los modos libre y autorizado, todas las áreas dentro del
bloque, ausencia de solapamientos, campos en última página e idempotencia.
Verifican además que un informe desconocido no produzca efectos parciales y
que el portal muestre un error sin revelar datos del documento.

```sh
PREVIEW_REPORT_ID=50001 PREVIEW_PAPER_SIZE=A4 PREVIEW_OUTPUT=/tmp/factura-a4.pdf bundle exec rails runner scripts/dielca_layout_preview.rb
PREVIEW_REPORT_ID=50001 PREVIEW_PAPER_SIZE=A5 PREVIEW_OUTPUT=/tmp/factura-a5.pdf bundle exec rails runner scripts/dielca_layout_preview.rb
```

Ejecutar exclusivamente en desarrollo/pruebas. Las muestras contienen datos
ficticios y sirven para la revisión visual, sin garantizar otros diseños de BC.
No hay migraciones, secretos ni nuevas dependencias. Se conserva la licencia
AGPLv3 y la atribución a DocuSeal. Sin push, PR a upstream ni despliegue automático;
el repositorio DIELCA es público y no debe contener datos operativos.

Verificación de esta revisión: 124 ejemplos RSpec de servicios DIELCA e
importación, sin fallos, ejecutados con SQLite y almacenamiento aislados.
Muestra A4 ficticia renderizada y revisada; git diff --check correcto.
