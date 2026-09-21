# Rendimiento de empleados

## Instalacion

1. Mantener aplicadas las migraciones de aprobacion de cuentas y `assignment_sla_setup.sql`.
2. Ejecutar completo `admin_performance_setup.sql` en el SQL Editor de Supabase. Es repetible; no modifica confirmaciones ni asignaciones.
3. Compilar la app e iniciar sesion con un administrador aprobado.
4. Abrir Perfil > Rendimiento y seleccionar un empleado para consultar su detalle.

La app consulta la RPC `admin_employee_performance`. Solo los administradores aprobados pueden ejecutarla con exito; ocultar la opcion en SwiftUI no es la barrera de seguridad. No requiere modificar el worker APNs.

## Definiciones

- Mes: calendario de America/Santo_Domingo. Los filtros de cargo se obtienen de los perfiles aprobados no administradores.
- Cumplimiento: (temprano + a_tiempo) / (temprano + a_tiempo + tardio + sin_confirmar). Sin observaciones se muestra un guion, no 0% ni 100%.
- Los hitos se atribuyen al mes de su horario programado. Los pendientes solo entran al denominador cuando termina su tolerancia de 15 minutos. Se utiliza el equipo congelado por SLA para identificar confirmaciones faltantes.
- Un hito futuro ya confirmado se incluye en su mes programado. La evaluacion se toma del registro individual persistido, no del estado global del hito.
- Retraso medio: minutos posteriores al fin de la tolerancia, solo entre confirmaciones tardias.
- Notas: registros creados por el empleado en el mes. S1 son los dias 1-7, S2 los dias 8-14, y asi sucesivamente. No son semanas ISO.
- Carga mensual: asignaciones cuyo intervalo coincide con el mes, vinculadas por equipo actual, participantes SLA o confirmaciones. Los estados mostrados son los actuales, no una fotografia del cierre historico del mes.
- No se calcula capacidad maxima porque no existe una capacidad individual configurada.

## Limites del historial

Las metricas dependen de los registros conservados. No se inventan participantes ni confirmaciones anteriores a la migracion SLA. Las eliminaciones en cascada existentes pueden retirar datos del historial; un dashboard historico inmutable requerira una politica de archivo separada.

## Verificacion

`Supabase/tests/admin_performance.test.mjs` verifica autorizacion, clasificacion SLA, faltantes, notas semanales, empleados sin actividad, intervalos mensuales, paginacion y ejecucion repetida de la migracion usando PGlite.

Prueba manual: comprobar lista y detalle con un admin, cambiar mes, buscar por nombre/cargo y probar los temas claro/oscuro. Con una cuenta de empleado la opcion no debe aparecer y la RPC debe rechazar la consulta.
