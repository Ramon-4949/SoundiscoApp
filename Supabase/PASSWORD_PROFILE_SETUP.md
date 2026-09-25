# Configuración

1. Ejecutar profile_editing.sql en Supabase SQL Editor después de las migraciones de perfiles y cargos.
2. En Authentication > Email Templates > Reset Password, establecer el asunto «Código de recuperación de SounDisco» y pegar el contenido de templates/recovery.html.
3. Configurar SMTP en Supabase para enviar a direcciones de usuarios reales y revisar los límites de envío. El correo predeterminado de pruebas no sustituye un proveedor SMTP de producción.
4. Configurar la longitud del OTP en seis dígitos y su expiración en Authentication. La app también admite pegar códigos de hasta diez dígitos. La vigencia y los intentos los valida Supabase.
5. Mantener la configuración actual de confirmación de correo del registro. La recuperación no requiere habilitar confirmaciones de registro.
6. Compilar la app y verificar recuperación con un correo real, código incorrecto, código vencido, reenvío, actualización y acceso con la nueva contraseña.
7. Probar cambio con contraseña actual incorrecta y correcta. Probar edición del perfil y rechazo de un UPDATE directo del nombre completo con un usuario autenticado.

El proceso de recuperación mantiene su sesión únicamente en memoria y vuelve al acceso tras actualizar la contraseña. El cambio desde el perfil verifica la contraseña actual en una sesión temporal y actualiza la contraseña con esa sesión reautenticada. Las contraseñas nunca se almacenan en tablas públicas ni se envían a una RPC.

[Plantillas de correo](https://supabase.com/docs/guides/auth/auth-email-templates)
[Verificación OTP en Swift](https://supabase.com/docs/reference/swift/auth-verifyotp)

