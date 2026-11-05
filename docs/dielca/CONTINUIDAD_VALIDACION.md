# Continuidad de accesos de Firmas

Estado revisado el 5/11/2026. Esta rama prepara metadatos BC 0.4.1.0 y controles
de autorización; no activa un portal de empleados ni amplía la consola nativa.

## Cambios preparados

- El importador conserva almacén, canal, ruta y procedencia de BC. Los valida y
  los incluye en la comprobación de idempotencia; una repetición con otro ámbito
  se rechaza sin modificar el documento original.
- `DocumentAccess` reúne la política de rol, tipo, estado y almacén fiable.
- `NativeConsoleAccess` impide que los grupos de negocio creen administradores
  nativos, incluso si se añaden por error a la allowlist de la consola.
- Los parámetros de ámbito se filtran en los logs.

## Lo que falta para activar usuarios de negocio

La política todavía no se aplica desde las rutas de documentos. Integrar una
sesión OIDC de negocio y aplicar autorización en servidor a listados, búsqueda,
detalle, firma mediada, PDF, auditoría y administración. Comprobar grupos vigentes,
revocación y acceso por URL/ID conocido. La credencial del conector no representa
la identidad del empleado.

Mostrador debe operar pedidos, albaranes y facturas de su ámbito, sin permisos de
administración. Reparto debe operar solo albaranes Delivery asignados: falta
conectar identidad/transportista/ruta y por ello sigue denegado. Mantener separados
el empleado y el autorizado del cliente que firma. Las ofertas no están soportadas.

El mapeo privado de almacenes ya está preparado fuera de Git, como se explica en
[BC_041_METADATOS_Y_ACCESO.md](BC_041_METADATOS_Y_ACCESO.md). No copiar valores
reales al repositorio ni habilitar acceso general por falta de configuración.

La configuración remota de BC apunta a `Pruebas301026`; al revisar, la credencial
de servicio devolvió HTTP 401. El entorno anterior devolvió `NoEnvironment`.
Confirmar acceso, compañía y extensión publicada antes de validar la integración.

## Validación y publicación

Las cuatro suites `document_access`, `native_console_access`, `dielca_pdf_import`
y `authentik_oidc` suman 91 ejemplos revisados. Se ejecutan sin datos de producción
y con SQLite temporal creado por migraciones. La imagen local de pruebas antigua
necesita los assets compilados `public/packs-test` y el logo del checkout actual.
Un schema exportado de PostgreSQL no se carga directamente en SQLite.

La imagen distribuible se construye con `scripts/build-image.sh` desde un commit
limpio: incorpora solo archivos versionados y su fuente AGPL correspondiente.
Compilar o subir esta rama no acredita que los permisos estén activos. Antes de
fusionar o activar roles, probar acceso permitido y denegado de los tres roles,
otras delegaciones, descargas, URL directa y retirada de grupos.
