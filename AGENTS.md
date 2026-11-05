# Memoria de trabajo de DIELCA

## Identificar A4/A5 y aplicar perfiles de firma

Antes de revisar o recolocar campos, leer [PERFILES_FIRMA.md](docs/dielca/PERFILES_FIRMA.md)
y [dielca_bc_layouts.json](config/dielca_bc_layouts.json). Estas fuentes guardan
los perfiles y las posiciones revisadas con el usuario; no estimarlas de nuevo.

- Medir el PDF original: A4 = 595.28 × 841.89 puntos (210 × 297 mm);
  A5 = 419.53 × 595.28 puntos (148 × 210 mm). Admitir redondeos de hasta 3 puntos
  y distinguir orientación. A5 horizontal mide aproximadamente 595.28 × 419.53.
- No deducir el papel del nombre del archivo, de una captura o del tipo de BC.
  Si hay páginas mixtas, revisar todas y colocar los campos en la última página
  del documento original que debe firmarse. Un PDF firmado descargado puede
  añadir auditoría A4 a un documento A5: excluir esa auditoría al identificar el
  formato y la página de firma.
- Elegir primero por reportId de BC (50000 albarán, 50001 factura, 50002 pedido)
  y después por tamaño real y etiquetas del diseño. Solo usar documentType
  cuando BC no facilite reportId. Un reportId desconocido se rechaza claramente.
- Conservar perfiles independientes: cambiar A4 no debe cambiar A5. Dentro de
  A4 también hay variantes: una franja horizontal y un bloque con filas
  separadas. Usar las etiquetas y posiciones de variants[].anchors para
  distinguirlas, nunca nombres, DNI ni datos del cliente.
- Albarán A4 con filas: 50000_A4_stacked, revisado el 29/10/2026. Nombre, DNI y
  fecha alineados a la izquierda; firma en la columna derecha de RECIBÍ CONFORME.
- Albarán A5 editado: 50000_A5_customer, revisado el 28/10/2026. Recuadro inferior
  izquierdo FIRMA DEL CLIENTE; Nombre ocupa la fila superior ancha y la firma
  queda a la derecha de DNI y Fecha, sin cubrir impuestos. Nombre parte de 7 pt
  en A4 y A5; en A5 su ancho es 0.195 de página para evitar que se reduzca a
  letra diminuta. No volver a estrecharlo a la columna de DNI/Fecha.
  Los perfiles anteriores siguen guardados.
- El pedido A5 no tiene referencia aprobada: no reutilizar posiciones A4.
- Mantener márgenes, columnas, alturas y espaciado coherentes, sin solapar
  campos ni tapar etiquetas, bordes, totales o impuestos. La fecha automática
  debe proceder del instante de finalización del servidor en Atlantic/Canary.
  Nunca pedir al usuario que rellene Fecha y hora ni fijarla al abrir el enlace.
  Para pendientes de la versión anterior se puede usar la función nativa:
  type=date, default_value={{date}}, readonly=true, required=false y formato
  DD/MM/YYYY HH:mm:ss. El servidor calcula el valor al completar; conservar
  las áreas aprobadas y comprobar que la cuenta usa Atlantic/Canary. No basta
  con renombrar un campo de texto ni con rellenarlo previamente desde el cliente.

## Alcance de los cambios

Guardar una posición en JSON no despliega la aplicación ni recoloca envíos
existentes. Comprobar y comunicar qué está aplicado realmente. Si el usuario
pide aplicar perfiles a pendientes ya importados, conservar identidad, valores,
UUID y enlaces; comprobar si usan plantilla o snapshot, respaldar antes y
verificar después. No modificar PDFs firmados, auditorías ni envíos completados.

Sin push ni despliegue automático. Mantener atribución y obligaciones AGPLv3.
El fork DIELCA es público: no incluir PDFs reales, clientes, firmas, secretos,
bases de datos ni backups en Git, pruebas o logs. Usar muestras ficticias.


## Grupos de Firmas e Informes

Para cambios de acceso, leer docs/dielca/CONTEXTO_GRUPOS_EL_SEBADAL.md. El ámbito
actual es El Sebadal, con grupos DIELCA/FirmasInformes/ElSebadal/{Admins,Mostrador,Reparto}.
Son roles de aplicación, no administración global de Authentik. Reutilizar las
cuentas del directorio y no enviar invitaciones, correos o avisos de provisión.
No ampliar la allowlist OIDC a Mostrador/Reparto mientras el portal les cree
usuarios admin nativos sin controles de autorización por documento/delegación.
Guardar censos y asignaciones nominales fuera de Git.

BC 0.4.1.0 aporta locationCode inmutable. El almacén de El Sebadal ya está
confirmado y guardado fuera de Git; no volver a pedirlo ni copiarlo al repo.
Leer docs/dielca/BC_041_METADATOS_Y_ACCESO.md para metadatos, gates, pruebas y
límites pendientes de integración. No confundir política preparada con acceso
por documento activo ni compilación de BC con publicación en Pruebas.
