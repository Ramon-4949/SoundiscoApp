# Despliegue de check-in individual e incidencias

1. Ejecutar completo `Supabase/assignment_sla_setup.sql` en el SQL Editor de Supabase,
   después de las migraciones de cuentas y vencimiento ya instaladas. Es transaccional
   y puede repetirse. No volver a ejecutar las migraciones antiguas después.
2. Verificar el cron:

```sql
select jobname, schedule, active from cron.job
where jobname in ('assignment-sla-every-minute','expire-assignments-every-minute');
select public.process_assignment_sla();
```

3. Compilar la nueva versión de iOS. No requiere cambios ni secretos nuevos en Render.
4. Probar con dos empleados, un hito programado para ahora y otro posterior: el
   primero confirma y ve Confirmado; el segundo sigue viendo su propio botón.
   Cuando ambos confirman, avanza el hito global. Repetir dejando uno pendiente
   hasta después de 15 minutos: el cron avanza si alguien confirmó, y el ausente
   todavía puede confirmar como tardío. El cron puede tardar hasta un minuto.
5. Probar un único responsable, una confirmación anticipada, reintentos y notas.

## Reglas adoptadas

- `hora_programada` es TIMESTAMPTZ, columna generada desde `fecha_programada` para
  mantener compatibles los formularios actuales. No se escribe directamente.
  Se conserva la fecha completa, zona horaria y segundos; `hora_estimada` es legado.
- La hora válida la fija Supabase con `clock_timestamp()`, nunca el teléfono.
  Desde la hora programada hasta +15 minutos inclusive es `a_tiempo`; después es
  `tardio`. Las confirmaciones anteriores al horario se permiten y se registran
  como `temprano`; desde el horario hasta +15 minutos inclusive son `a_tiempo`.
- El equipo y horario quedan congelados al abrir cada hito habilitado (cron o RPC).
  Nuevos responsables añadidos después participarán en hitos todavía no abiertos.
  No pueden cambiarse horario ni orden de ventanas abiertas; crear otro hito para
  cambios posteriores. La eliminación explícita conserva el comportamiento previo:
  borrar asignaciones/hitos elimina sus registros relacionados por cascada.
- Un grupo avanza cuando todos confirman, incluso anticipadamente, o después de +15 minutos con al menos
  una confirmación. Cero confirmaciones no se interpreta como trabajo completado.
  El avance global respeta la secuencia; un empleado puede recuperar check-ins de
  hitos anteriores mientras siga asignado y pertenezca al equipo registrado.
- Un único responsable avanza al confirmar. Los registros individuales no se
  cambian cuando avanza el grupo. Los faltantes no cuentan como tardíos hasta confirmar.
- `vencida` sigue siendo una etiqueta de plazo; ya no bloquea el check-in. Una
  asignación puede terminar globalmente con confirmaciones individuales pendientes.
- Los hitos completados antes de instalar esta migración conservan su historial;
  no se inventan autores ni evaluaciones. Sus comentarios antiguos permanecen en
  la BD, pero las notas nuevas se almacenan exclusivamente en `notas_asignacion`.
- Notas: autor y fecha impuestos por servidor, contenido entre 1 y 4000 caracteres,
  UUID de reintento para evitar duplicados. Solo usuarios aprobados con acceso a
  la asignación pueden publicar o leer. El administrador puede leer confirmaciones
  del equipo; cada empleado solo sus propias confirmaciones.
- Eliminar una cuenta elimina sus confirmaciones y notas mediante FK en cascada.

## Archivos iOS

- `Features/Assignments/Models/AssignmentActivity.swift`: confirmaciones y notas.
- `Features/Assignments/Models/Assignment.swift`: indicador de ventana SLA abierta.
- `Features/Assignments/ViewModels/AssignmentDetailViewModel.swift`: carga paginada,
  check-in y publicación de notas mediante RPC; sin bloqueo por vencimiento.
- `Features/Assignments/Views/AssignmentChecklistView.swift`: Confirmado individual,
  evaluación, sin comentario; consulta periódica mientras la pantalla está abierta.
- `Features/Assignments/Views/AssignmentDetailView.swift`: listado y acceso permanente.
- `Features/Assignments/Views/AssignmentNoteEditor.swift`: editor independiente.

## Verificación y futura analítica

```sql
select asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion
from public.confirmaciones_hitos order by created_at desc;
select asignacion_id,usuario_id,contenido,created_at
from public.notas_asignacion order by created_at desc;
```

Para métricas de ausencia, comparar `sla_private.participants` con confirmaciones;
para puntualidad, agrupar evaluaciones por usuario; para comunicación, contar notas.
El snapshot privado no es accesible desde iOS: el futuro dashboard debe usar una
RPC exclusiva de administradores para consultar esos denominadores.

Pruebas locales: `Supabase/tests/assignment_sla.test.mjs` usa PGlite, con el cron
simulado; no constituye una prueba de APNs, pg_cron real ni de la BD de producción.
