# SounDisco: MVVM por funcionalidades

## Estructura

- `SoundiscoApp/App`: entrada de la app, sesion compartida y seleccion del flujo principal.
- `SoundiscoApp/Core/Networking`: configuracion unica del cliente Supabase.
- `SoundiscoApp/Core/DesignSystem`: componentes y colores compartidos.
- `SoundiscoApp/Core/Formatting`: conversion y presentacion de fechas.
- `SoundiscoApp/Features/Authentication`: modelos, vistas y ViewModels de acceso, registro, sesion y recuperacion.
- `SoundiscoApp/Features/Assignments`: modelos, vistas y ViewModel de asignaciones, busqueda y filtros.
- `SoundiscoApp/Features/Bulletins`: comunicados de solo lectura.
- `SoundiscoApp/Features/Notifications`: notificaciones del empleado.
- `SoundiscoApp/Features/Calendar`: calendario y seleccion de asignaciones por fecha.
- `SoundiscoApp/Features/Profile`: perfil y su carga independiente.
- `SoundiscoApp/Features/Home`: composicion de las pestanas principales.

## Responsabilidades

Las Views presentan estado y envian acciones a sus ViewModels. Los ViewModels son `ObservableObject` aislados en `MainActor`; contienen validaciones, carga, errores y transformaciones de presentacion. Los modelos representan el contrato de datos y sus reglas de dominio. Los ViewModels que consultan Supabase aceptan un cliente inyectado; el cliente compartido se configura en Core.

La navegacion, los sheets, el ojo de la contrasena y otros estados puramente visuales permanecen en las vistas. Las vistas estaticas de detalle y las composiciones de navegacion no necesitan ViewModels vacios.

No se realizan consultas Supabase ni se importan SDKs de red desde las Views. La sesion pertenece a `SessionViewModel`, compartido desde App; los datos del empleado se destruyen al cambiar de usuario mediante la identidad del Home.

## Registro

Esta version espera registro directo sin confirmacion de correo. Desactivar Confirm Email en el proveedor Email de Supabase. Un registro sin sesion se trata como fallo de configuracion, nunca como acceso exitoso. Se conserva la recuperacion de contrasena por correo.

Los cargos elegidos se envian como metadatos informativos. Los roles y las politicas de acceso se definen en el servidor.
