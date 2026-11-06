# Selector único y verificación de firmantes

Los nuevos envíos del conector usan `signer_mode=selectable`. El selector ofrece
los autorizados de la instantánea del cliente y, al final, «Otra persona (no está
en la lista)». Antes de elegirla se muestra cuántos autorizados tiene el cliente.
Sin autorizados, esa es la única opción no vacía.

Al elegir un autorizado se rellenan nombre y documento. Al elegir otra persona
se introducen en la confirmación existente, con DNI/NIE y letra validados por
`SpanishIdentity`. Los campos del PDF permanecen de solo lectura; la geometría,
la fecha del servidor y la política de copia no cambian. Cambiar de persona borra
la firma sin completar y exige confirmar de nuevo el correo. Las completadas
no admiten cambios.

La selección se guarda bajo bloqueo en `selected_signer_id` (`other` para otra
persona) y metadata `signer_selection=authorized|other`. La API de selección
expone `signer_selection` y `selected_signer_id=null` para otra persona. Nunca se
interpreta la ausencia de selección como permiso para escribir otra identidad.
La capacidad nueva es `selectable_signing=true`.

Compatibilidad: los envíos `free` y `authorized` conservan su comportamiento y
sus huellas de idempotencia. Para permitir desplegar portal antes que conector,
las importaciones antiguas conservan esos modos; solo las nuevas que solicitan
`selectable` usan el selector único. El modo nuevo participa en la huella y un
reintento con modo distinto no modifica la firma anterior.

BC 0.4.6.0 registra `Authorized` al revalidar el autorizado y
`PendingVerification` para otra persona, incluso con DNI válido. Administración
valida y autoriza para futuras firmas (`Verified`) o registra `Rejected` con
comentario. Un autorizado revocado nunca se convierte silenciosamente en otra
persona.

Despliegue: portal compatible con copia SQLite verificada primero; publicar BC
0.4.6.0 por el usuario en Pruebas301026; confirmar la publicación y después
actualizar el conector con copia de estado. Rollback de servicios con Docker.
La preselección en mostrador es opcional y queda pendiente. No se amplían grupos,
allowlists ni permisos de empleados. Se mantiene la atribución y licencia AGPLv3.
