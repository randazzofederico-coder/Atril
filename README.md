<p align="center">
  <img src="Atril_cropped.png" width="120" alt="Atril Logo"/>
</p>

<h1 align="center">Atril — Atril Digital para Músicos</h1>

<p align="center">
  <em>Tu biblioteca de partituras PDF, diseñada para el escenario.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Platform-Android%20|%20Windows%20|%20Web-green?logo=android" alt="Platform"/>
  <img src="https://img.shields.io/badge/Cuenta-opcional-FFCA28?logo=firebase" alt="Cuenta opcional"/>
  <img src="https://img.shields.io/badge/License-Private-lightgrey" alt="License"/>
  <img src="https://img.shields.io/badge/Version-2.0.0-orange" alt="Version"/>
</p>

---

## 📖 ¿Qué es Atril?

**Atril** es una aplicación Flutter pensada para músicos que necesitan gestionar, leer y anotar partituras PDF con total fiabilidad durante una performance en vivo. Toda la biblioteca, anotaciones y configuración viven en el dispositivo. La **cuenta es opcional** (ecosistema de apps de Federico Randazzo, igual que Afinador, Metrónomo y Tone Generator): sin cuenta todo funciona offline.

---

## ✨ Funcionalidades

### 👤 Cuenta (opcional)
- **Sin login obligatorio**: la app abre directo en la biblioteca y funciona 100% offline.
- **Cuenta del ecosistema** (`fede_apps_core`): "Continuar con Google" desde Ajustes (Android/iOS/web); misma cuenta que Afinador, Metrónomo y Tone Generator.
- **Más apps**: acceso a las otras apps del ecosistema desde Ajustes.
- Métricas de uso **solo locales** (no se envían a ningún servidor).
### 📚 Biblioteca de Partituras
- **Carpetas anidables infinitas** con CRUD completo (crear, renombrar, mover, eliminar).
- **Búsqueda global** por título de partitura.
- **Importación flexible**: archivos sueltos, carpetas recursivas, o desde la cámara.

### 📷 Escáner de Partituras (Cámara → PDF)
- Captura o importa múltiples páginas a **resolución nativa completa** del celular y genera un PDF multi-página.
- **Corrección de perspectiva** con homografía 3×3: 4 handles independientes para rectificar ángulos de cámara con precisión profesional.
- **Resolución adaptativa**: output a 300 DPI (A4) para fotos de 12MP+, 250 DPI para 5-8MP, 200 DPI mínimo.
- **Interpolación bicúbica** en el warp de perspectiva para líneas de pentagrama nítidas.
- **Procesamiento en segundo plano**: el usuario vuelve a la lista de páginas inmediatamente mientras la perspectiva se procesa en un Isolate, con barra de progreso y porcentaje en cada tile.
- **Creación de PDF en background**: al confirmar, la app vuelve a la biblioteca y muestra progreso global por página.
- **Compresión inteligente**: pass-through directo de JPEGs sin re-codificar para evitar degradación; solo re-procesa imágenes que exceden 300 DPI.
- **Procesamiento de imagen**: rotación, blanco/negro con umbral configurable, brillo y contraste.
- Soporte nativo para fotos con rotación EXIF (`bakeOrientation`).

### ✂️ Editor de Páginas PDF
- **Reordenar páginas** con drag & drop (misma UX que el escáner).
- **Eliminar páginas** individuales de un PDF existente.
- **Agregar páginas** desde cámara, galería, u otro PDF de la biblioteca.
- **Preservación sin pérdida**: las páginas originales se copian via `PdfTemplate` de Syncfusion, sin re-codificar.
- **Las anotaciones acompañan a sus páginas**: al reordenar se mueven con ellas; al eliminar una página se borran sus anotaciones. Las páginas anotadas se marcan en el editor.
- **Deshacer en el editor**: historial completo (mover, eliminar, agregar, re-editar), con atajo "Deshacer" al eliminar.
- **Deshacer la última edición guardada**: se conserva una versión previa (PDF + anotaciones) por documento, restaurable desde el aviso posterior al guardado o desde el editor.
- **Guardado seguro**: si algo falla al guardar, PDF y anotaciones vuelven automáticamente al estado anterior.
- Thumbnails renderizados progresivamente desde el PDF (pdfrx + package:image).
- Regeneración de PDF en background con progreso global; el visor se recarga solo si el documento abierto fue editado.
- Accesible desde el **menú contextual** de la biblioteca y desde el **visor PDF**.

### 📄 Lector PDF
- Motor de renderizado rápido (`pdfrx`) con scroll vertical continuo.
- **Scrubber vertical** para saltar rápidamente entre páginas.
- Navegación entre documentos dentro de una sesión de lectura.
- **Inversión de colores**: simula modo nocturno para partituras con fondo blanco.
- **Pantalla siempre encendida** mientras se lee una partitura o se usa el Modo Vivo (independiente del ajuste global).

### ✏️ Anotaciones No Destructivas
- **Lápiz**, **Resaltador** y **Borrador (Whiteout)** con grosor y color personalizables.
- **Texto** insertable con tap sobre la página.
- **Sellos** rápidos (iconos musicales: coda, segno, etc.).
- Persistencia por página y por documento (una capa por partitura).
- **Exportables**: se pueden compartir/exportar "quemadas" sobre el PDF o como datos editables (`.setlist`).
- **Borrador**: borra lo que toca (trazos, texto, sellos), con tamaño ajustable y zona de acción visible.
- **Tamaños finos**: selector logarítmico (0.3 a 40) para lapicera, resaltador, tapadera y borrador.
- **Undo / Redo** por documento (nunca afecta a otro PDF) y "borrar página" que también se puede deshacer.
- Preferencias de herramientas (último color/grosor usado) guardadas automáticamente.

### 🎵 Setlists
- Crea listas de reproducción ordenadas con tus partituras.
- **Modo Vivo**: pantalla completa robusta para el escenario, con el mismo motor que el lector (`pdfrx`): anotaciones pegadas a cada página, colores invertidos, pantalla siempre encendida.
  - **Pedal Bluetooth / teclado**: flechas, PageUp/PageDown y Espacio; al pasar la última página va al tema siguiente.
  - Botón ▶ en cada tema del setlist para arrancar el Vivo desde ese tema.
- **Reordenar**: mantener presionado un tema activa la edición y ya lo arrastra.
- Reordenamiento con drag & drop.
- **Compartir como ZIP**: archivos ordenados con nombre legible (`01 - Tema.pdf`), con o sin anotaciones aplicadas.
- **Compartir como `.setlist`**: formato propietario reimportable por otros usuarios de Atril; opcionalmente incluye las anotaciones **editables**.

### 🗑️ Papelera de Reciclaje
- Los elementos eliminados se ocultan de la interfaz principal (Soft Delete).
- **Restauración rápida** preservando metadatos y anotaciones. Si la carpeta original sigue en la papelera, el elemento vuelve a la raíz.
- **Purga segura**: nunca elimina partituras activas; al purgar una carpeta, lo que siga activo adentro se rescata a la raíz. Al purgar se borran también sus anotaciones.
- **Auto-limpieza**: eliminación física automática tras 30 días.
- Accesible desde Configuración.

### 💾 Backup y Exportación
- **Backup completo** (`.atril`): empaqueta la base de datos (snapshot consistente con `VACUUM INTO`) + todos los PDFs en un solo archivo comprimido.
- **Importación de backup**: agrega el contenido de un backup a la biblioteca existente sin reemplazar (carpetas, partituras, **anotaciones y setlists**). Es transaccional: si falla no deja nada a medias.
- **Restauración destructiva**: reemplaza toda la biblioteca con un backup anterior. El backup se **valida antes** de tocar nada y, si algo falla, la biblioteca anterior se recupera automáticamente.
- **Exportación para PC**: genera un ZIP legible con la estructura de carpetas y nombres originales, **con o sin anotaciones** aplicadas sobre los PDFs (títulos repetidos en una carpeta se desambiguan como `Título (2).pdf`).
- Todo procesado con **Isolates** y barras de progreso en tiempo real.
- Protección contra archivos maliciosos (zip-slip / rutas fuera del destino) y limpieza automática de temporales.

### 📤 Compartir / Importar (100% Offline)
- **Compartir PDF individual** desde el menú contextual (⋮) o desde el **visor PDF**, con nombre de display.
- **Con o sin anotaciones**: si el documento tiene anotaciones, Atril pregunta si incluirlas. "Con anotaciones" las dibuja sobre una **copia** del PDF (vectorial para trazos y texto); el original nunca se modifica. Si no hay anotaciones, comparte directo.
- **Compartir Setlist** como ZIP universal o `.setlist` propietario.
- **Importar `.setlist`**: al tocar un archivo recibido (WhatsApp, email, etc.), Atril lo abre automáticamente, crea una carpeta en la biblioteca con todos los PDFs y genera el setlist.
- **Detección inteligente**: identifica el tipo de archivo por contenido (header ZIP + `data.json`), no por extensión.
- Registro nativo de tipo de archivo en **Android** e **iOS** para asociación automática con la app.
- Soporte para **cold start** (app cerrada) y **hot resume** (app en background) via `MethodChannel`.

### ⚙️ Configuración
- **Modo Oscuro / Claro** con Material 3.
- **Escala de UI** configurable (80% – 150%).
- Inversión de colores PDF y pantalla siempre encendida.

---

## 🏗️ Arquitectura

El proyecto sigue una arquitectura en capas con un **Patrón de Fachada** centralizado:

```
UI (Screens & Widgets)
     │                      ┌──────────┐
     ├── Action Delegates   │ HomeShell │
     │   (lógica de UI)     └──────────┘
     │
     └── AppData (Facade) ← Source of Truth en memoria
              │
              ├── LibraryRepository
              ├── SetlistRepository
              ├── ImportRepository
              ├── AnnotationRepository
              ├── SettingsRepository
              ├── BackupManager
              ├── ExportManager ── PdfAnnotationFlattener
              ├── PageEditRepository ── PdfManipulator
              └── PdfGenerator
                       │
              ┌────────┴────────┐
              │                 │
        Drift (SQLite)    LibraryStorage (FileSystem)
```

### Estructura del Código

```
lib/
├── main.dart                  # Entry point, Firebase init, MaterialApp reactivo
├── firebase_options.dart      # Configuración Firebase (generado por FlutterFire CLI)
├── data/
│   ├── app_data.dart          # Fachada Global (cache, IDs, delegación)
│   ├── app_database.dart      # Schema Drift (SQLite) con migraciones
│   ├── library_storage.dart   # Abstracción de FileSystem
│   ├── temp_cleanup.dart      # Limpieza de temporales al iniciar
│   ├── backup_manager.dart    # Lógica de backup/restore/export con Isolates
│   ├── export_manager.dart    # Compartir/Importar PDFs y Setlists con Isolates
│   ├── file_receiver_channel.dart # MethodChannel para archivos entrantes
│   └── repositories/
│       ├── library_repository.dart      # CRUD de docs y carpetas, soft delete
│       ├── setlist_repository.dart      # Gestión de listas de reproducción
│       ├── import_repository.dart       # Ingesta de PDFs y carpetas
│       ├── annotation_repository.dart   # Trazos de tinta vectoriales
│       ├── settings_repository.dart     # Preferencias (tema, escala, etc.)
│       ├── pdf_generator.dart           # Generación de PDF desde imágenes
│       ├── pdf_manipulator.dart         # Edición estructural de PDFs (reorder, delete, insert)
│       ├── page_edit_repository.dart    # Edición de páginas preservando anotaciones + deshacer
│       └── pdf_annotation_flattener.dart # "Quema" anotaciones sobre una copia del PDF para exportar
├── models/
│   ├── score.dart             # Modelo de partitura
│   ├── folder.dart            # Modelo de carpeta
│   ├── setlist.dart           # Modelo de setlist
│   ├── annotation_stroke.dart # Modelo de trazo/anotación
│   └── annotation_style.dart  # Estilo visual de anotaciones (compartido visor/exportación)
├── screens/
│   ├── home_shell.dart        # Shell con NavigationBar (Biblioteca / Setlists)
│   ├── library/               # Biblioteca, scanner, editor de imagen, editor de páginas PDF, acciones de exportación
│   ├── reader/                # Visor PDF, capa de anotaciones, toolbar
│   ├── setlists/              # CRUD de setlists, detalle, modo vivo
│   ├── settings/              # Configuración general
│   └── trash/                 # Papelera de reciclaje
└── widgets/                   # Componentes reutilizables (breadcrumbs, diálogos de exportación, etc.)
```

---

## 🛠️ Tech Stack

| Componente | Tecnología |
|:---|:---|
| **Framework** | Flutter (Dart) • Material 3 |
| **Cuenta (opcional)** | `fede_apps_core` (Firebase Auth con Google, proyecto compartido del ecosistema) |
| **Cloud** | Solo el perfil de la cuenta opcional (`users/{uid}`); la biblioteca no se sube |
| **Base de datos local** | Drift (SQLite) con migraciones tipadas |
| **Visor PDF** | `pdfrx` (lector y Modo Vivo; un solo motor) |
| **PDF Generation** | Syncfusion Flutter PDF |
| **Procesamiento de imagen** | `image` package + homografía 3×3 custom |
| **Archivos** | `file_picker`, `path_provider`, `share_plus` |
| **Concurrencia** | `Isolate.spawn` con `SendPort` para progreso en tiempo real |
| **Preferencias** | `shared_preferences` |
| **Wakelock** | `wakelock_plus` |
| **URLs externas** | `url_launcher` |

---

## 🚀 Getting Started

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd pdf_setlist

# 2. fede_apps_core (paquete compartido del ecosistema) debe estar al lado:
#    ../fede_apps_core
# 3. Instalar dependencias
flutter pub get

# 4. Configurar Firebase (si no existe firebase_options.dart)
flutterfire configure

# 5. Generar código de Drift (si es necesario)
dart run build_runner build --delete-conflicting-outputs

# 6. Ejecutar la app
flutter run
```

### Requisitos
- Flutter SDK ≥ 3.38 (Dart ≥ 3.10)
- Android SDK (minSdk 21) para Android
- Proyecto Firebase configurado con Auth + Firestore habilitados
- Un dispositivo o emulador Android, o bien compilar para Windows/Web

### Plataformas soportadas

| Plataforma | Estado | Notas |
|:---|:---|:---|
| **Android** | ✅ Producción | Google Sign-In nativo, cámara, permisos de storage |
| **Windows** | ✅ Funcional | Instalador Inno Setup incluido (`installerscript.iss`) |
| **Web** | ⚠️ Parcial | Login funcional, funciones de cámara/storage limitadas |
| **iOS / macOS / Linux** | 🔧 Scaffolding | Directorios de plataforma presentes, no testeados |

---

## 🔒 Privacidad

Atril funciona sin cuenta. Si el usuario elige iniciar sesión (opcional), se usa **Firebase Auth** con Google y se guarda un perfil básico (nombre y email) en **Cloud Firestore**, compartido con las otras apps del ecosistema.
**La biblioteca de partituras, anotaciones y configuración se almacenan localmente en el dispositivo** y nunca se sincronizan con servidores. Atril no utiliza servicios de análisis ni publicidad.

> Para más detalles, consultá [`privacy_policy.html`](privacy_policy.html).

---

## 📬 Contacto

Desarrollado por **Saroo** — [randazzofederico@gmail.com](mailto:randazzofederico@gmail.com)

---

<p align="center">
  <em>Diseñado para músicos que necesitan fiabilidad en el escenario. 🎶</em>
</p>
