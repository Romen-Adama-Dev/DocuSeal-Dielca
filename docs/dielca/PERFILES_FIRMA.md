# Perfiles de firma por informe y papel

Configuración: `config/dielca_bc_layouts.json`.

| Informe BC | Tipo | A4 | A5 |
| --- | --- | --- | --- |
| 50000 | PostedShipment / albarán | 50000_A4 y 50000_A4_stacked | 50000_A5 y 50000_A5_customer |
| 50001 | PostedInvoice / factura registrada | 50001_A4 | 50001_A5 |
| 50002 | SalesOrder / pedido | 50002_A4 y 50002_A4_stacked | Pendiente de referencia |

`profiles` guarda cada juego de coordenadas una sola vez. `reports` y
`document_types` seleccionan mediante `paper_sizes` y `profile_id`. Aunque dos
perfiles partan de las mismas coordenadas, sus entradas son independientes:
ajustar factura A5 no cambia el albarán A5. Los overrides de configuración ya
existentes pueden seguir usando perfiles inline y referencias `report_id`.

Ejemplo de selector:

```json
{"paper_sizes":{"A4":{"profile_id":"50000_A4"},"A5":{"profile_id":"50000_A5"}}}
```

Se usa el reportId explícito que envía BC; solo si no existe reportId se
consulta documentType. Un reportId desconocido se rechaza. El papel se detecta
por las dimensiones reales de la última página del PDF original (no por el
nombre del archivo ni el tamaño que declare el navegador), con tolerancia de
3 puntos para redondeos. El tamaño detectado elige un único perfil; si falta,
se muestra el error de configuración en lugar de colocar campos de otro papel.
No se inventa un perfil de pedido A5 sin disponer de su diseño.

Cada nueva importación conserva `report_layout_id` en los metadatos del
firmante, además del reportId y documentType de BC. Las áreas se copian a la
plantilla de ese envío. Un ajuste posterior de configuración no altera
plantillas ya importadas ni documentos firmados. Los reintentos idempotentes
conservan el envío y el perfil originales.

## Revisión del último albarán (28/10/2026)

Se revisó fuera de Git un albarán 50000 A4, firmado con tres campos y sin campo
de fecha. El dibujo desbordaba verticalmente la franja inferior. Se conserva
la columna de Nombre observada y se limita la firma al espacio posterior al
rótulo Firma; Nombre, DNI, fecha y firma comparten altura y límites verticales.
La fecha/hora de servidor se sitúa junto a Fecha. El perfil A5 no se modifica
por este ajuste. No se copian identificadores, valores de identidad, firmas
ni documentos de referencia a Git.

Las pruebas y muestras utilizan únicamente datos ficticios. Sin migraciones,
sin despliegue automático ni cambios en proxy, secretos o almacenamiento.
La atribución y licencia AGPLv3 se conservan.

Verificación: 127 ejemplos de servicios e importación sin fallos; tras ajustar
el límite derecho de la firma A4, 21 ejemplos de perfiles y albaranes A4
completados sin fallos. Muestra ficticia A4 renderizada para revisión.


## Diseños revisados y A5 editado por el usuario (28/10/2026)

Los tres documentos revisados inicialmente eran A4: dos albaranes con el mismo
bloque de tres renglones y un pedido con sus propios renglones de identidad.
Se añaden las variantes 50000_A4_stacked y 50002_A4_stacked. Las firmas permanecen
dentro del recuadro de conformidad y no pisan las filas de identidad o fecha.

Después se inspeccionó la plantilla A5 horizontal de dos páginas editada por el
usuario. El perfil 50000_A5_customer guarda la columna y filas seleccionadas
para Nombre, DNI y Fecha, alineadas con igual x, ancho y altura. La firma manual
editada estaba sobre las cifras de impuestos: el perfil corregido la contiene
en la columna derecha del recuadro FIRMA DEL CLIENTE, sin invadir los impuestos.
Los textos se ajustan a su columna y la fecha/hora ocupa una sola línea.
No se añade un logo en esa caja porque carece de espacio libre suficiente.

Se detecta cada variante por las etiquetas estáticas de la última página del
PDF original, con cajas normalizadas configuradas en variants[].anchors. A5 se
reconoce por FIRMA DEL CLIENTE y Nombre; los nuevos A4 por sus rótulos en filas
separadas. Los textos de cliente, valores de DNI y firmas no se usan como claves
ni se guardan en configuración o logs. Si hay dos coincidencias, se rechaza la
selección por ambigua. Si no hay coincidencia, se conserva el perfil anterior
del tamaño correspondiente. El PDF se inspecciona sin modificar su contenido.

Las muestras admiten PREVIEW_PROFILE_ID para revisar una variante concreta;
por ejemplo, 50000_A5_customer junto con PREVIEW_PAPER_SIZE=A5. Los perfiles se
conservan en Git solo como coordenadas y reglas de etiquetas, sin PDFs reales.
Esta revisión sigue siendo local y no modifica el envío editado por el usuario
ni despliega a producción automáticamente.

Verificación de las variantes: 134 ejemplos de servicios e importación sin
fallos; 27 ejemplos de perfiles e identidad tras añadir la comprobación de
ambigüedad, sin fallos. Muestras sintéticas de A5 y de los dos nuevos A4
renderizadas y revisadas. Lectura separada de las referencias locales confirma
las etiquetas estáticas de detección, sin incorporarlas como fixtures reales.
