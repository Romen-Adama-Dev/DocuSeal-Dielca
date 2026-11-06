# Contexto para Conector y Firmas e Informes — El Sebadal

Fecha de revisión: 29/10/2026. Solo provisión de grupos en Authentik y contrato
para implementar permisos; no se despliegan aplicaciones ni se cambian accesos
existentes como efecto de esta preparación. No enviar invitaciones, bienvenida,
restablecimientos de contraseña ni avisos de alta/cambio de grupo.

## Grupos y alcance acordados

| Nombre exacto del grupo Authentik | Rol de negocio | Asignación inicial |
| --- | --- | --- |
| DIELCA/FirmasInformes/ElSebadal/Admins | admin | 6 administradores indicados por el usuario |
| DIELCA/FirmasInformes/ElSebadal/Mostrador | mostrador | 7 personas con puesto Comercial o Dependiente de mostrador en El Sebadal |
| DIELCA/FirmasInformes/ElSebadal/Reparto | reparto | 1 persona con puesto Transportista en El Sebadal |

Se reutilizan 14 cuentas existentes de Authentik: no crear duplicados ni cambiar
contraseñas. El directorio contiene 18 personas de El Sebadal; 10 puestos de
almacén/administración/delegación no reciben de momento estos roles. Los seis
administradores pertenecen a Oficina Central según el directorio, pero el
usuario los autorizó para administrar este ámbito de la aplicación. No cambiar
sus atributos de delegación para simular que trabajan en El Sebadal.

Los grupos se crean sin is_superuser, sin padres y sin roles administrativos de
Authentik. No modificar los grupos globales Admins, Responsables o Comerciales.
No guardar en este repositorio censos, nombres, correos, IDs de empleados,
contraseñas, tokens o copias de la base de datos.

Atributos de los grupos:

```json
{
  "managed_by": "dielca-firmas-informes-el-sebadal-v1",
  "dielca_application": "firmas-informes",
  "dielca_site": "el-sebadal",
  "dielca_role": "admin | mostrador | reparto",
  "dielca_document_types": ["tipos permitidos según el rol"]
}
```

Estado verificado: tres grupos creados, 14 cuentas existentes reutilizadas,
ninguna cuenta nueva, 0 notificaciones enviadas. No se cambiaron privilegios
globales, contraseñas, proveedores OIDC ni bindings de aplicaciones.

Estos atributos describen el contrato. No crean permisos en DocuSeal o BC por
sí solos, ni aparecen automáticamente en un token sin un mapeo explícito.

## Matriz de permisos a implementar en servidor

| Rol | Documentos en El Sebadal | Acciones de negocio |
| --- | --- | --- |
| admin | Pedidos, albaranes y facturas compatibles | Administración del ámbito y sus documentos; acceso a configuración propia |
| mostrador | Pedidos, facturas de venta y albaranes | Tramitar, consultar y abrir la firma de sus documentos; incluir recogida en mostrador; sin administración |
| reparto | Solo albaranes registrados | Consultar/abrir firma de los albaranes autorizados para reparto; sin ofertas, pedidos, facturas ni administración |

La regla de delegación se exige además del tipo de documento. No conceder
acceso global a otras delegaciones. El estado completado permite consulta y
las acciones de archivo/copia ya autorizadas; no permite alterar un PDF firmado.
La delegación y las asignaciones de reparto han de proceder de datos fiables de
BC, no de un selector libre del navegador. BC 0.4.1.0 aporta `locationCode`
como almacén inmutable del pedido/albarán/factura al crear la solicitud.
El código de El Sebadal está confirmado y se guarda exclusivamente en la
configuración privada del servidor; no volver a solicitarlo ni copiarlo al repo.
Decisión 06/11/2026 (provisional, TODO): sin correspondencia transportista ↔ ruta.
Reparto ve todos los albaranes registrados con canal Delivery de su delegación y
elige en el portal cuál firmar (solo consulta y abrir firma). El canal lo elige el
empleado en BC al preparar la firma. Counter incluye recogida en mostrador. Las ofertas
(SalesQuote) no están soportadas por BC y se deniegan.
Las solicitudes antiguas con almacén vacío o sin mapeo se reservan al admin
explícito del ámbito; Mostrador/Reparto no pueden acceder a ellas.

Prioridad de roles en este ámbito: admin > mostrador > reparto. Sin coincidencia
con un grupo de esta aplicación: denegar. Un Admins global de Authentik no es
por ese solo hecho administrador de Firmas e Informes.

## Autenticación y limitación actual del portal

Origen: https://firmas.intra.dielca.com
Emisor OIDC verificado en la configuración de Swarm:
https://auth.intra.dielca.com/application/o/docuseal/
Callback: https://firmas.intra.dielca.com/auth/authentik/callback

El proveedor existente usa los scopes openid/profile/email. Verificar el claim
groups con los nombres completos anteriores; configurar un mapeo si no está
incluido. No usar token/cookie del navegador como prueba sin validar firma,
issuer, audience, caducidad y vinculación de la sesión.

El portal actual permite el grupo global Admins. Su provisión OIDC crea usuarios
DocuSeal con el rol interno admin. Por ello NO ampliar ahora esa allowlist a
Mostrador/Reparto: daría acceso amplio, no las restricciones acordadas.
Implementar antes autorización propia para estos roles o un portal de negocio
con endpoints restringidos y DocuSeal como motor de firma. Mantener la consola
de DocuSeal restringida a administradores. No depender de roles comerciales de
pago ni eludir controles de licencia; toda implementación nueva será abierta
y conservará las obligaciones AGPLv3.

Relacionar el usuario con (issuer, sub) estable. Cuando sea necesario cruzarlo
con BC/Entra, utilizar un mapeo explícito a la identidad corporativa; no asumir
que sub de Authentik, ID de usuario BC y oid de Entra son iguales. El correo no
basta para autorizar y debe verificarse antes de cualquier vinculación inicial.

## Encargo para el conector

Repositorio local: /home/dielca-server/Dielca-Firma-Conector.

1. Separar la identidad de servicio del conector de la identidad humana que
   solicita/consulta un documento. La credencial compartida del conector no
   demuestra que una persona sea Admins, Mostrador o Reparto.
2. Definir un contrato autenticado para emisor/sub del solicitante, documento,
   empresa BC y ámbito/delegación. No fiarse de role, groups o site enviados
   como JSON sin verificación de origen. No incluir tokens en logs o enlaces.
3. Exigir permisos en servidor antes de reservar/crear/entregar enlaces, acceder
   a PDF/auditoría o permitir una acción administrativa. No basta ocultar botones.
4. Mantener correlación BC ↔ importación ↔ envío DocuSeal, hash e idempotencia.
   No crear otra firma por cambios de grupo o reintentos. Conservar el circuito
   attachSignedFiles → copia autorizada → markCopySent de solicitudes firmadas.
5. Registrar rechazos con códigos y correlación técnica, sin correos, DNI, JWT,
   enlaces de firma o datos del documento. No enviar avisos por esta provisión.
6. Acordar los tipos soportados: PostedShipment es albarán, SalesOrder pedido y
   PostedInvoice factura. Las ofertas requieren SalesQuote explícito y, si no
   está soportado en el contrato desplegado, una ampliación revisada; nunca
   tratarlas silenciosamente como pedidos. Mantener reportId y perfiles A4/A5
   independientes: 50000 albarán, 50001 factura, 50002 pedido. El informe de
   oferta necesita su propio identificador/perfil revisado, sin inventarlo.

## Encargo para el proyecto de Firmas e Informes / BC

Portal: /home/dielca-server/DocuSeal-Dielca.
Extensión BC local: /home/dielca-server/Dielca-Firma-Digital.

1. Consumir los grupos anteriores desde la identidad autenticada y construir
   una única política de autorización de rol + delegación + documento.
2. Aplicarla también a consultas, listados, búsquedas, descarga, auditorías,
   APIs, URLs conocidas y acciones de reintento/administración. Reparto no
   obtiene acceso a una factura aunque conozca su ID.
3. Mostrador incluye comerciales y recogidas en mostrador: no clasificar todo
   albarán como entrega de transportista. Conservar el canal/recogida de BC.
4. Mantener separados el empleado que tramita y el cliente/autorizado que firma.
   El rol del empleado no convierte a una persona en autorizado del cliente.
5. BC debe aplicar sus propios permission sets y filtros por documento/delegación.
   Crear grupos en Authentik no asigna automáticamente permisos de BC Online.
   Revisar los contratos y permission sets realmente desplegados: el checkout
   local de la extensión puede ser anterior a la versión activa.
6. No activar correos de alta. No crear usuarios generales como admin nativo de
   DocuSeal para simular RBAC. No cambiar proxy ni otros servicios compartidos.

## Validación antes de activar los permisos en las aplicaciones

Probar con usuarios y documentos ficticios: admin del ámbito; mostrador con
pedido/albarán/factura; reparto con albarán Delivery; denegación de reparto sobre
pedido/factura/oferta; denegación entre delegaciones; acceso por URL directa;
retirada del grupo; sesión caducada y token inválido. Confirmar que un usuario
sin rol no obtiene un rol por defecto. Verificar que ninguna acción de provisión
mande correo y que el flujo de firma existente no se interrumpa.

Los nombres/miembros reales y el respaldo operativo se conservan fuera de Git.
Sin push ni despliegue automático; entregar cambios revisables en los repos de
DIELCA, nunca PR a docusealco/docuseal.


## Adaptación BC 0.4.1.0

Ver [BC_041_METADATOS_Y_ACCESO.md](BC_041_METADATOS_Y_ACCESO.md) para cambios
locales, variables privadas, compatibilidad de reintentos y límites pendientes.
Compilar BC no acredita su publicación: confirmar 0.4.1.0 publicada en Pruebas
antes de activar la autorización de empleados. No ampliar la allowlist nativa.
