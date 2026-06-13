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
  <img src="https://img.shields.io/badge/Firebase-Auth%20%2B%20Firestore-FFCA28?logo=firebase" alt="Firebase"/>
  <img src="https://img.shields.io/badge/License-Private-lightgrey" alt="License"/>
  <img src="https://img.shields.io/badge/Version-1.16.0-orange" alt="Version"/>
</p>

---

## 📖 ¿Qué es Atril?

**Atril** es una aplicación Flutter pensada para músicos que necesitan gestionar, leer y anotar partituras PDF con total fiabilidad durante una performance en vivo. Toda la biblioteca, anotaciones y configuración viven en el dispositivo. La autenticación y el control de acceso se gestionan mediante **Firebase Auth + Firestore**, permitiendo un sistema de suscripciones y pruebas gratuitas.

---

## ✨ Funcionalidades

### 🔐 Autenticación y Acceso
- **Login con Google** (Android, iOS, Web) y **email/contraseña** con verificación por correo.
- **Onboarding** para usuarios nuevos: el perfil se crea en Firestore y se notifica al administrador.
- **Sistema de permisos** basado en roles (`admin`, `pendiente`, suscripción activa).
- **Período de prueba gratuito** de 30 días, activable desde la app.
- **Pantalla de acceso pendiente** con opciones de prueba, suscripción y reintento.
- Recuperación de contraseña por email.

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
- Thumbnails renderizados progresivamente desde el PDF (pdfrx + package:image).
- Regeneración de PDF en background con progreso global.
- Accesible desde el **menú contextual** de la biblioteca y desde el **visor PDF**.

### 📄 Lector PDF
- Motor de renderizado rápido (`pdfrx`) con scroll vertical continuo.
- **Scrubber vertical** para saltar rápidamente entre páginas.
- Navegación entre documentos dentro de una sesión de lectura.
- **Inversión de colores**: simula modo nocturno para partituras con fondo blanco.
- **Pantalla siempre encendida** (wakelock) para evitar bloqueos durante la performance.

### ✏️ Anotaciones No Destructivas
- **Lápiz**, **Resaltador** y **Borrador (Whiteout)** con grosor y color personalizables.
- **Texto** insertable con tap sobre la página.
- **Sellos** rápidos (iconos musicales: coda, segno, etc.).
- Persistencia por página y por documento. Soporte futuro para capas por setlist.
- **Undo / Redo** global y borrado de página.
- Preferencias de herramientas (último color/grosor usado) guardadas automáticamente.

### 🎵 Setlists
- Crea listas de reproducción ordenadas con tus partituras.
- **Modo Vivo**: navegación fluida entre partituras con un solo tap, ideal para conciertos.
- Reordenamiento con drag & drop.
- **Compartir como ZIP**: archivos ordenados con nombre legible (`01 - Tema.pdf`).
- **Compartir como `.setlist`**: formato propietario reimportable por otros usuarios de Atril.

### 🗑️ Papelera de Reciclaje
- Los elementos eliminados se ocultan de la interfaz principal (Soft Delete).
- **Restauración rápida** preservando metadatos y anotaciones.
- **Auto-limpieza**: eliminación física automática tras 30 días.
- Accesible desde Configuración.

### 💾 Backup y Exportación
- **Backup completo** (`.atril`): empaqueta la base de datos + todos los PDFs en un solo archivo comprimido.
- **Importación de backup**: agrega el contenido de un backup a la biblioteca existente sin reemplazar.
- **Restauración destructiva**: reemplaza toda la biblioteca con un backup anterior.
- **Exportación para PC**: genera un ZIP legible con la estructura de carpetas y nombres originales.
- Todo procesado con **Isolates** y barras de progreso en tiempo real.

### 📤 Compartir / Importar (100% Offline)
- **Compartir PDF individual** desde el menú contextual (⋮) con nombre de display.
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
                       ┌──────────────────────┐
                       │   Firebase Auth       │
                       │   (Google / Email)     │
                       └──────────┬───────────┘
                                  │
                       ┌──────────▼───────────┐
                       │     AuthGate          │
                       │  PermissionChecker    │◄── Cloud Firestore
                       │  (roles, trial, sub)  │    (usuarios, consultas_web)
                       └──────────┬───────────┘
                                  │ acceso concedido
                                  │
UI (Screens & Widgets)            ▼
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
│       └── pdf_manipulator.dart         # Edición estructural de PDFs (reorder, delete, insert)
├── models/
│   ├── score.dart             # Modelo de partitura
│   ├── folder.dart            # Modelo de carpeta
│   ├── setlist.dart           # Modelo de setlist
│   ├── setlist_nav_context.dart # Contexto de navegación en setlist
│   ├── annotation_stroke.dart # Modelo de trazo/anotación
│   └── app_data_types.dart    # Tipos compartidos (BackgroundTaskStatus, etc.)
├── screens/
│   ├── auth_gate.dart         # Flujo de autenticación y verificación de permisos
│   ├── login_screen.dart      # Login (Google + email/contraseña)
│   ├── onboarding_screen.dart # Registro de perfil para usuarios nuevos
│   ├── home_shell.dart        # Shell con NavigationBar (Biblioteca / Setlists)
│   ├── library/               # Pantallas de biblioteca, scanner, editor de imagen, editor de páginas PDF
│   ├── reader/                # Visor PDF, capa de anotaciones, toolbar
│   ├── setlists/              # CRUD de setlists, detalle, modo vivo
│   ├── settings/              # Configuración general
│   └── trash/                 # Papelera de reciclaje
└── widgets/                   # Componentes reutilizables (breadcrumbs, diálogos, etc.)
```

---

## 🛠️ Tech Stack

| Componente | Tecnología |
|:---|:---|
| **Framework** | Flutter (Dart) • Material 3 |
| **Autenticación** | Firebase Auth (Google Sign-In + Email/Password) |
| **Cloud** | Cloud Firestore (perfiles, permisos, notificaciones admin) |
| **Base de datos local** | Drift (SQLite) con migraciones tipadas |
| **Visor PDF** | `pdfrx` (renderizado rápido) |
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

# 2. Instalar dependencias
flutter pub get

# 3. Configurar Firebase (si no existe firebase_options.dart)
flutterfire configure

# 4. Generar código de Drift (si es necesario)
dart run build_runner build --delete-conflicting-outputs

# 5. Ejecutar la app
flutter run
```

### Requisitos
- Flutter SDK ≥ 3.0.0
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

Atril utiliza **Firebase Auth** y **Cloud Firestore** exclusivamente para:
- Autenticación del usuario (login y registro).
- Verificación de permisos y suscripciones.
- Notificaciones al administrador (onboarding, activación de trial).

**La biblioteca de partituras, anotaciones y configuración se almacenan localmente en el dispositivo** y nunca se sincronizan con servidores. Atril no utiliza servicios de análisis ni publicidad.

> Para más detalles, consultá [`privacy_policy.html`](privacy_policy.html).

---

## 📬 Contacto

Desarrollado por **Saroo** — [randazzofederico@gmail.com](mailto:randazzofederico@gmail.com)

---

<p align="center">
  <em>Diseñado para músicos que necesitan fiabilidad en el escenario. 🎶</em>
</p>
