# Validaciones y protección de acceso

## Base de datos

Ejecutar `profile_roles_and_jobs.sql` y después `input_validation_setup.sql` en el SQL Editor. Ambos scripts son repetibles.

`input_validation_setup.sql` valida los datos de registro que llegan desde Supabase Auth y aplica límites a asignaciones, hitos, comunicados y notas. Las restricciones se crean como `NOT VALID`: protegen escrituras nuevas sin impedir la migración por datos históricos que todavía deban corregirse.

## Supabase Auth

El bloqueo de cinco intentos durante quince minutos que muestra la app se guarda por correo en el dispositivo. Es una protección de experiencia y no sustituye el control del servidor, porque puede evitarse reinstalando la aplicación o llamando directamente a la API.

En Authentication > configuración de seguridad del proyecto:

1. Mantener el rate limit del endpoint de inicio de sesión habilitado.
2. Configurar longitud mínima de contraseña en 8 caracteres o más, igual que la app.
3. Activar protección contra contraseñas filtradas si está disponible en el plan.
4. Activar CAPTCHA en registro e inicio de sesión antes de producción si el volumen o los intentos automatizados lo requieren.

La app exige mayúscula, minúscula, número, carácter especial, ausencia de espacios y máximo de 72 caracteres. El servidor de Auth debe conservar su propio rate limit aunque se cambien esos requisitos visuales.

## Límites principales

- Usuario: 3-30; letras ASCII, números, punto, guion y guion bajo.
- Nombre: 2-80; letras, espacios, apóstrofe y guion.
- Teléfono: 10-15 dígitos, permitiendo formato visual.
- Título de asignación: 3-120.
- Ubicación: 3-180.
- Hito: 2-100.
- Instrucciones: 2000.
- Comunicado: asunto 3-140 y cuerpo 10-4000.
- Nota o incidencia: 3-4000.

Los errores aparecen debajo del campo después del primer intento de envío y se actualizan mientras el usuario corrige el contenido.
