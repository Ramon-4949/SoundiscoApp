# Preparación de SounDisco para App Store

Revisión: 31 de octubre de 2026.

Actualización: 1 de noviembre de 2026. Nombre legal confirmado: SOUND DISCO FR EIRL. Soporte: soundiscomedia@gmail.com. El usuario confirmó haber ejecutado el SQL de seguridad. Las páginas públicas están publicadas; faltan las pruebas finales y los pasos de App Store Connect. Este informe no sustituye la validación de Apple ni la revisión de los documentos por la empresa.

URLs para App Store Connect:

- Política de privacidad: https://soundisco-privacidad-soporte.soundiscomedia.chatgpt.site/privacidad/
- Soporte: https://soundisco-privacidad-soporte.soundiscomedia.chatgpt.site/soporte/
- Términos: https://soundisco-privacidad-soporte.soundiscomedia.chatgpt.site/terminos/

## Cambios implementados

| Área | Resultado |
| --- | --- |
| Manifiesto | `SoundiscoApp/PrivacyInfo.xcprivacy`: sin seguimiento publicitario; declara datos ligados a la cuenta y el uso de UserDefaults con CA92.1. |
| Documentos | Política y términos incluidos en el paquete, legibles sin conexión desde registro, login y perfil. Se retiró el aviso de documento no disponible. |
| Soporte | Pantalla accesible antes de iniciar sesión y desde el perfil; muestra versión, correo de contacto y enlace al centro de soporte público. |
| Contenido | Reportes de notas por motivo, cola administrativa paginada, retirada de notas, filtro básico de expresiones para notas y comunicados. |
| Accesos | Suspensión de cuentas aprobadas desde el panel administrativo; puede revertirse aprobando la cuenta desde Rechazadas. El servidor protege las cuentas administradoras frente a esta acción. |
| Información | Nombre visible SounDisco y localización principal española. Se corrigieron los textos sobre eliminación y cierre de sesión para describir la implementación real. |
| Cifrado | `ITSAppUsesNonExemptEncryption=false` para el uso actual de HTTPS, autenticación y seguridad del sistema. Revisar la declaración si se añaden funciones de cifrado no exentas. |

## Activación del backend

Ejecutar completo `Supabase/app_store_safety.sql` en el SQL Editor del proyecto SoundiscoApp, después de los scripts existentes de accesos y notas. Puede repetirse.

El script añade una tabla privada de reportes, funciones restringidas y filtros. No modifica los horarios de recordatorios, las confirmaciones ni los datos existentes. El usuario confirmó su ejecución.

Los usuarios pueden reportar desde el menú de cada nota. Los administradores revisan en Perfil > Reportes de contenido y retiran notas o marcan reportes como revisados. La suspensión está en Perfil > Panel de control > Aprobadas. Las cuentas administradoras requieren gestión por el responsable del sistema; el servidor no permite suspenderlas desde este panel.

El filtro de expresiones es básico y no detecta todas las formas de abuso. Administración debe revisar los reportes y mantener la lista `moderation_private.blocked_phrases`. No hay un sistema de moderación humana automática ni un compromiso de tiempo de respuesta configurado.

Esta versión incorpora UI y requiere un nuevo build de TestFlight/App Store. El worker de Render no cambió. Las funciones nuevas son compartidas por iOS y Android; el cliente Android necesita su propia UI para reportar y moderar.

## Privacidad y documentos pendientes

Los documentos están en `SoundiscoApp/Resources/Legal/PrivacyPolicy.txt` y `TermsOfService.txt`. El contenido refleja las funciones revisadas y ya identifica al responsable legal y al correo confirmados por el usuario. La empresa debe revisar contratos de los proveedores, políticas reales de conservación y cualquier tratamiento externo que el código no permita verificar.

Las páginas públicas están alojadas en Sites y no requieren login ni dominio propio. Introducir las URLs anteriores en App Store Connect. El documento incluido dentro de la app no reemplaza el campo URL pública de política.

Completar App Privacy en App Store Connect de acuerdo con el uso real, incluidos proveedores:

| Categoría identificada | Ejemplos en esta app | Propósito |
| --- | --- | --- |
| Datos de contacto | Nombre, email, teléfono | Funcionalidad y cuenta |
| Identificador de usuario | UUID y nombre de usuario | Autenticación y permisos |
| Identificadores del dispositivo | Instalación y token push | Entrega de notificaciones |
| Contenido del usuario | Notas, incidencias, comunicados y reportes | Coordinación y moderación |
| Interacción con el producto | Confirmaciones, horarios y lectura | Funcionalidad y métricas operativas |
| Otros datos | Cargo y participación laboral | Funcionalidad |

Los datos anteriores están ligados a la cuenta. No se identificaron SDKs publicitarios ni seguimiento entre apps; no se añadió un diálogo ATT. Los datos biométricos permanecen bajo control del sistema operativo. Las ubicaciones escritas de eventos no son GPS del dispositivo. Revisar también los logs técnicos y direcciones IP de los proveedores antes de completar la declaración final; el manifiesto no completa App Privacy automáticamente.

## Cuenta y eliminación

Ya existe Perfil > Eliminar cuenta, también accesible a cuentas pendientes o rechazadas desde Mi perfil. El cliente llama a `delete_my_account`, limpia su sesión y registro local push. Se revisó la función instalada y las claves foráneas: elimina el usuario Auth y su perfil, y se propaga a confirmaciones, notas, membresías y dispositivos. Las asignaciones y comunicados compartidos permanecen.

No se eliminó ninguna cuenta de producción para probar este flujo. Antes del envío debe probarse con una cuenta desechable, primero pendiente y luego aprobada, confirmando que ya no permite entrar y que se retiran sus registros personales. El borrado también elimina sus reportes por cascada. Los ciclos de backup y retención de logs deben confirmarse con los proveedores.

## Acceso para App Review

Preparar cuentas de prueba aprobadas de empleado y administrador con datos ficticios, sin información de clientes ni empleados reales. El empleado debe tener al menos una asignación con hitos. Facilitar credenciales en App Review Information, contacto atendido y las instrucciones de navegación. No utilizar el admin real de la empresa.

Se preparó `Supabase/admin_content_ownership.sql` para vincular cada asignación y comunicado al administrador que lo creó, sin un entorno demo separado. **Pendiente de aplicar en producción y validar desde la app.** El usuario confirmó a `yankee_admin@gmail.com` como creador de todos los registros anteriores y el script ya está configurado con ese correo. Instrucciones: `Supabase/ADMIN_CONTENT_OWNERSHIP.md`. La lista de cuentas y los avisos de registro siguen compartidos; este cambio no convierte al admin de pruebas en una cuenta aislada de todos los datos personales.

El revisor no debe esperar la aprobación de una cuenta recién creada. No hay bypass de autenticación ni permisos especiales para Apple. Mantener Supabase y Render disponibles durante la revisión.

Texto base para Review Notes, una vez activado el SQL:

> SounDisco es una herramienta de coordinación laboral para equipos de producción audiovisual. El acceso requiere una cuenta aprobada. Proporcionamos credenciales de demostración de empleado y administrador en App Review Information. El empleado consulta sus asignaciones, confirma hitos y añade o reporta notas; el administrador gestiona asignaciones, accesos, métricas y reportes. Perfil > Eliminar cuenta permite eliminar la cuenta. Las notificaciones y la biometría son opcionales. No incluye compras ni suscripciones.

## Distribución y ficha

Por el público actual de colaboradores de una empresa, evaluar distribución no listada mediante enlace o Custom App mediante Apple Business. No se cambió el método de distribución de la cuenta. La opción pública debe describir honestamente la audiencia y el requisito de aprobación.

Completar antes del envío:

- Nombre, subtítulo, descripción y categoría acordes con una app de coordinación de trabajo, sin referencias a beta o prototipo.
- Capturas reales para iPhone y iPad: el target actual soporta ambas familias. Verificar también orientación horizontal y tamaños de texto grandes.
- URL de privacidad, URL de soporte, contacto de revisión y titular de los derechos.
- Cuestionario actualizado de clasificación por edad, declarando contenido de usuarios conforme corresponda.
- App Privacy, cifrado, países y disponibilidad; estado de comerciante para los países donde corresponda.
- Número de build superior al último subido en App Store Connect; el proyecto conserva 1.0 (2), porque no se conoce el último número remoto.
- Archive firmado con distribución y validación desde Organizer. Se comprobó compilación Release sin firma, no una subida ni una validación de Apple.

## Comprobaciones realizadas

- Compilación Release arm64 para dispositivo con Xcode 27.1 y SDK iOS 27.1: exitosa.
- El paquete incluye `PrivacyInfo.xcprivacy`, ambos documentos y el icono compilado de Icon Composer.
- Info.plist compilado: APNs `production`, nombre SounDisco, idioma `es`, cifrado no exento `false`.
- El proyecto mantiene iOS 26.5 mínimo. Cumple el mínimo de Apple, pero excluye dispositivos con versiones anteriores; decidir si esa cobertura es la deseada antes de publicar.
- Plists y formato de diff verificados.
- Pruebas SQL locales con Postgres/PGlite: reportes privados, acceso por participación, permisos admin, deduplicación, borrado en cascada, suspensión y limpieza de dispositivos iOS/Android, filtro de texto.
- No se verificó UI en un simulador activo: no había ninguno abierto. La compilación no reemplaza una prueba en iPhone/iPad reales.
- Persisten advertencias previas de aislamiento de modelos Decodable y resultados de filtros no usados. No bloquean el build actual en Swift 5; requieren revisión antes de migrar a Swift 6 estricto. No se refactorizaron todos los modelos durante esta auditoría.

## Fuentes oficiales consultadas

- [App Review Guidelines: privacidad, contenido, acceso y permisos](https://developer.apple.com/app-store/review/guidelines/)
- [Eliminación de cuentas](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
- [APIs que requieren una razón declarada](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [App Privacy](https://developer.apple.com/app-store/app-privacy-details/)
- [Requisitos de SDK y edad vigentes](https://developer.apple.com/news/upcoming-requirements/)
- [Cifrado y documentación de exportación](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Distribución no listada](https://developer.apple.com/support/unlisted-app-distribution/)
- [Distribución Custom App](https://developer.apple.com/support/volume-purchase-and-custom-apps/)
