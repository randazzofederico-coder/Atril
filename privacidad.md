Política de Privacidad de Atril
Última actualización: 11 de noviembre de 2026

Esta Política de Privacidad describe cómo Atril (en adelante, "la Aplicación"), desarrollada por Federico Randazzo (Saroo), recopila, utiliza y protege la información de sus usuarios. Atril está diseñada como una herramienta de fiabilidad para músicos en el escenario, y nuestra política de manejo de datos refleja ese compromiso con la privacidad y el rendimiento local.

Al utilizar Atril, aceptas las prácticas descritas en este documento.

1. Información que recopilamos y cómo la utilizamos
Atril minimiza estrictamente la recopilación de datos en la nube. La información se divide en dos categorías principales: datos gestionados en la nube (exclusivamente para acceso) y datos gestionados localmente.

A. Datos gestionados en la nube (Firebase)
Utilizamos Firebase Auth y Cloud Firestore con el único propósito de gestionar la identidad del usuario y los permisos de uso de la Aplicación. Los datos recopilados incluyen:

Información de Autenticación: Dirección de correo electrónico, nombre y foto de perfil (si se utiliza el inicio de sesión con Google) o credenciales de email y contraseña.

Datos de Perfil y Permisos: Información básica del perfil creada durante el onboarding, roles de usuario (ej. administrador, pendiente), estado de la suscripción y estado del período de prueba gratuito.

Notificaciones de Sistema: Eventos de registro de nuevos usuarios o activaciones de pruebas gratuitas que se notifican al administrador del sistema para la gestión de accesos.

Uso de esta información: Estos datos se utilizan exclusivamente para autenticar tu ingreso, validar tu suscripción o período de prueba, y garantizar el acceso autorizado a la Aplicación.

B. Datos almacenados localmente (En tu dispositivo)
Todo tu contenido musical y de trabajo vive en tu dispositivo (en la versión web/PWA, en el almacenamiento del navegador de ese dispositivo). Atril no sube ni comparte esta información con ningún servidor propio ni de terceros, salvo que actives el backup opcional en tu propio Google Drive (ver punto C).

Biblioteca de Partituras: Todos los archivos PDF importados o escaneados.

Anotaciones: Trazos de lápiz, resaltador, sellos y textos añadidos a las partituras.

Setlists y Estructura: La organización de tus carpetas y listas de reproducción.

Configuraciones de la App: Preferencias como el modo oscuro/claro, escala de la interfaz visual, inversión de colores y opciones de wakelock (pantalla siempre encendida).

Archivos de Backup: Los archivos de exportación y copias de seguridad (.atril, .setlist, .atrilfolder o .zip) generados por el usuario.

C. Backup opcional en tu Google Drive
Si lo activás desde Ajustes, Atril guarda una copia de tu biblioteca (partituras, anotaciones, carpetas, setlists y una base de datos con esa organización) en una carpeta oculta de TU propia cuenta de Google Drive ("appDataFolder"), usando el permiso drive.appdata. Con ese permiso Atril solo puede ver y modificar los archivos que él mismo creó: no accede al resto de tu Drive.

Estos respaldos no pasan por servidores nuestros: van directamente de tu dispositivo a tu Drive y ocupan espacio de tu cuenta. Cada dispositivo guarda su propio respaldo, que podés traer desde otro dispositivo con la misma cuenta. El respaldo es de un solo sentido: lo que pase en Drive nunca modifica ni borra la biblioteca de tu dispositivo.

Podés pausarlo, desactivarlo y borrar todos los respaldos desde la misma pantalla de la app, o revocar el acceso de Atril a tu Drive en cualquier momento desde la configuración de seguridad de tu cuenta de Google.

2. Permisos del Dispositivo
Para funcionar correctamente, Atril puede solicitar los siguientes permisos en tu dispositivo:

Cámara: Requerido exclusivamente para la función de Escáner de Partituras, permitiendo capturar imágenes para convertirlas en archivos PDF locales.

Almacenamiento / Acceso a Archivos: Necesario para importar partituras en PDF desde tu dispositivo, así como para guardar y restaurar copias de seguridad de tu biblioteca.

3. Servicios de Terceros
Atril utiliza los siguientes servicios de terceros para su infraestructura base:

Google (Firebase Auth y Cloud Firestore): Para la gestión de usuarios, autenticación y base de datos de permisos. Podés consultar la Política de Privacidad de Google aquí.

Google Drive (solo si activás el backup): Para guardar los respaldos en la carpeta oculta de la app en tu propia cuenta. Se rige por la Política de Privacidad de Google.

Exclusión de Analíticas y Publicidad:
Atril no integra SDKs de publicidad, no rastrea tu comportamiento dentro de la aplicación mediante servicios de analíticas (como Google Analytics) y no vende ni cede tus datos a terceros bajo ninguna circunstancia.

4. Seguridad de los Datos
Nos tomamos muy en serio la seguridad de tu información. La autenticación y la gestión de bases de datos en la nube se manejan a través de la infraestructura segura de Firebase. Por otro lado, la seguridad de tus partituras y anotaciones depende de la seguridad general de tu propio dispositivo, ya que residen en el almacenamiento local (mediante bases de datos locales y el sistema de archivos de tu sistema operativo).

5. Retención y Eliminación de Datos
Datos locales: Podés eliminar tus partituras y datos utilizando la función de Papelera de Reciclaje de la aplicación, la cual realiza una auto-limpieza (eliminación física) después de 30 días, o podés desinstalar la Aplicación para borrar todo el almacenamiento local.

Datos de la cuenta: Si deseás eliminar tu cuenta de usuario, perfil y los datos de suscripción almacenados en Cloud Firestore, podés solicitarlo comunicándote directamente con nosotros.

6. Cambios en esta Política de Privacidad
Es posible que actualicemos esta Política de Privacidad de vez en cuando para reflejar cambios en nuestras prácticas o por razones operativas, legales o reglamentarias. Cualquier cambio será notificado actualizando la fecha de "Última actualización" en la parte superior de este documento.

7. Contacto
Si tenés alguna pregunta, inquietud o solicitud relacionada con esta Política de Privacidad o el manejo de tus datos, no dudes en ponerte en contacto:

Desarrollador: Federico Randazzo (Saroo)

Correo electrónico: randazzofederico@gmail.com