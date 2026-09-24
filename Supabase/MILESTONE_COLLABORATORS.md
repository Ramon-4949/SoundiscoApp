# Colaboradores por hito

## Despliegue

1. Ejecutar `milestone_collaborators.sql` completo en SQL Editor. Requiere las migraciones existentes de CRUD, disponibilidad, acceso, SLA, notificaciones y rendimiento.
2. Compilar y distribuir la nueva app. Las versiones anteriores no pueden crear o editar asignaciones porque no envian colaboradores por hito; el servidor solicita actualizar la app.
3. El worker APNs no necesita cambios: sigue consumiendo la misma cola.

La migracion es transaccional y se puede repetir. Conserva las confirmaciones anteriores y sus evaluaciones historicas; copia los responsables existentes a cada hito una sola vez. No inventa confirmaciones para miembros que nunca confirmaron. El cron recalcula el estado global segun las participaciones reales; antiguos hitos cerrados por timeout pueden volver a pendientes/vencidos si faltaban confirmaciones.

## Reglas de tiempo

- Antes de `fecha_programada`: `temprano`.
- Exactamente en `fecha_programada`: `a_tiempo`.
- Despues: `tardio`, siempre que no haya vencido el ultimo hito personal.
- El servidor usa `clock_timestamp()` una vez, despues de tomar el bloqueo de la asignacion. La hora del telefono no decide la evaluacion.
- El cierre personal ocurre cuando la hora actual es estrictamente posterior a la fecha del ultimo hito asignado a ese usuario, ordenado por `orden`.
- Por esta regla, el ultimo hito personal nunca admite una confirmacion tardia. Los hitos anteriores si, hasta ese cierre.
- Esta version sustituye la tolerancia anterior de 15 minutos. La igualdad exacta de timestamps es poco frecuente; casi todas las confirmaciones se clasificaran como temprano o tardio.
- El orden se exige solo entre los hitos del empleado. Puede confirmar sus siguientes hitos inmediatamente y no espera a sus companeros.
- Un hito global se completa exclusivamente cuando tiene participantes y todos confirmaron. El cron no completa por tiempo.

## Datos y seguridad

`hitos_colaboradores` es la fuente de permisos y confirmacion individual. Su clave compuesta evita duplicados. `confirmaciones_hitos` conserva una copia de auditoria compatible con las metricas existentes; ambas escrituras ocurren en la misma transaccion.

El cliente solo tiene SELECT sobre participaciones. `check_in_milestone` valida identidad, acceso aprobado, pertenencia al hito, orden personal y cierre. No acepta estado, usuario o timestamp proporcionados por la app.

RLS limita los hitos descargados por empleados a sus propias participaciones, incluso si una politica anterior permitia leer todo el evento. Administradores y supervisores asignados al evento ven todos los hitos y sus colaboradores. Ser supervisor no concede permisos CRUD ni permite confirmar por otra persona.

`asignacion_supervisores` guarda supervisores del evento; el administrador puede seleccionar uno o varios usuarios aprobados. `asignacion_equipo` se conserva como resumen derivado de colaboradores y supervisores para Home, notas y notificaciones. Los clientes antiguos no pueden cambiar este resumen a traves de las RPC de creacion/edicion sin especificar participaciones.

Las reservas se calculan desde el primer hasta el ultimo hito de cada colaborador (desde la creacion para tareas administrativas). Supervisores reservan el evento completo. El selector consulta el horario del hito; al guardar, la base verifica el intervalo personal completo mediante la exclusion existente, incluyendo conflictos concurrentes.

Horarios, posiciones y colaboradores con confirmaciones no pueden retirarse del historial mediante una edicion. Si se elimina el evento completo con la RPC administrativa, se eliminan sus dependencias como antes.

Las confirmaciones notifican solo a administradores. Los recordatorios de hitos y cierres personales se envian a los participantes correspondientes. Realtime publica cambios de `hitos_colaboradores` y respeta RLS; el checklist mantiene reconciliacion periodica para recuperarse de desconexiones.

## Archivos iOS

- `Models/Hito.swift`: modelos de participaciones, etiquetas y colaboradores en borradores.
- `Models/Asignacion.swift`: supervisores del evento.
- `Features/Admin/Views/AdminAssignmentFormView.swift`: selector dentro de cada tarjeta y selector de supervisores.
- `Features/Admin/ViewModels/AdminAssignmentCRUDViewModel.swift`: payload granular y lectura anidada.
- `Features/Assignments/Models/Assignment.swift`: progreso y fecha limite personales en Home.
- `Features/Assignments/ViewModels/AssignmentDetailViewModel.swift`: validacion local, RPC y Realtime.
- `Features/Assignments/Views/AssignmentChecklistView.swift`: seguimiento por colaborador, etiquetas y bloqueo actualizado cada segundo.

## Pruebas de aceptacion

1. Crear tres hitos: A para Ana y Bob, B solo para Ana, C solo para Bob; asignar a otra persona como supervisor.
2. Ana debe descargar A y B; Bob, A y C; supervisor y admin, los tres.
3. Ana confirma A anticipadamente y puede confirmar B de inmediato. A sigue pendiente hasta que Bob confirme.
4. Programar A en el pasado y B/C en el futuro: la confirmacion de A es tardia, con diferencia en minutos.
5. Dejar vencer B: Ana no puede confirmar A ni B aunque C siga en el futuro. Bob conserva su plazo.
6. Confirmar con dos dispositivos del mismo usuario: solo debe existir una confirmacion.
7. Mantener abierto el checklist del admin: las confirmaciones deben refrescar la lista sin salir de la pantalla.
8. Intentar consultar otro hito con la API como empleado: RLS no devuelve esa fila; intentar confirmarlo devuelve acceso denegado.

Pruebas SQL automatizadas: `PGLITE_PATH=/ruta/a/pglite/dist/index.js node Supabase/tests/milestone_collaborators.test.mjs`. Usa una base aislada, no Supabase remoto.
