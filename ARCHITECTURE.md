# ARCHITECTURE.md — Atril Digital (Flutter)

**Estado del Proyecto:** Consolidación — **v1.16.0 (Compartir/Importar Setlists)**
**Fecha de Análisis:** Junio 2026
**Objetivo:** Compartir PDFs y setlists offline, importar archivos `.setlist` recibidos.

---

## 1. Filosofía Central

**"Seguridad en el Escenario"**
Nada importa más que la estabilidad durante una performance.
* **Robustez:** El código debe ser predecible. Preferimos soluciones probadas a experimentales.
* **Feedback:** El usuario siempre debe saber qué está pasando (loading states, confirmaciones).
* **Persistencia Agresiva:** Todo cambio se guarda inmediatamente. Si la app crashea, al volver debe estar todo ahí.

---

## 2. Arquitectura de Software

El proyecto sigue una arquitectura en capas con un **Patrón de Fachada (Facade)** centralizado para la gestión de estado y lógica de negocio.

### 2.1. Diagrama Conceptual

```mermaid
graph TD
    UI[UI Screens & Widgets] -->|Llamadas| Actions[Action Delegates]
    UI -->|Lectura Reactiva| AD[AppData (Facade)]
    Actions -->|Ejecución| AD
    AD -->|Orquesta| Repos[Repositories]
    Repos -->|Persistencia| DB[(Drift Database)]
    Repos -->|Archivos| LS[LibraryStorage]
    Repos -->|Configs| SP[SharedPreferences]
```

### 2.2. Capas

#### **A. Capa de Presentación (UI)**
* **Screens:** Agrupadas por dominio (`screens/library`, `screens/reader`, `screens/setlists`).
* **Delegates:** Clases estáticas como `LibraryActions` que manejan la lógica de UI "sucia" (Diálogos, TextControllers, SnackBar confirms) para mantener los Widgets `build()` limpios.
* **Estado:** Se consume principalmente a través de `AppData` (listas estáticas refrescadas) y `ValueNotifiers` globales para señales de actualización (`libraryRevision`, `setlistsRevision`).

#### **B. Capa de Aplicación (AppData)**
* **Rol:** Fachada Global y Fuente de la Verdad en Memoria.
* **Responsabilidades:**
    * Mantiene las listas cacheadas (`library`, `folders`, `setlists`) para acceso síncrono en UI.
    * Expone métodos estáticos que delegan a los Repositorios.
    * Centraliza la inicialización de la app (`init()`).

#### **C. Capa de Dominio / Repositorios**
Contiene la lógica de negocio pura. Ubicación: `lib/data/repositories/`.
* **`LibraryRepository`:** CRUD de archivos, carpetas y metadata.
* **`SetlistRepository`:** Gestión de listas de reproducción y ordenamiento.
* **`ImportRepository`:** Lógica compleja de ingesta de PDFs y estructuras de carpetas.
* **`AnnotationRepository`:** Gestión de trazos de tinta y capas de dibujo.
* **`SettingsRepository`:** Preferencias de usuario (Tema, Escala UI).
* **`BackupManager`:** Lógica de compresión/descompresión (ZIP), exportación e importación de backups completos (`.atril`).
* **`ExportManager`:** Compartir PDFs individuales y setlists (ZIP o `.setlist` propietario) vía `share_plus`. Importación de archivos `.setlist` recibidos con descompresión en Isolate.
* **`FileReceiverChannel`:** Canal de plataforma (`MethodChannel`) para recibir archivos abiertos desde otras apps. Maneja cold start y hot resume.
* **`PdfGenerator`:** Generación de PDFs multi-página desde imágenes usando Syncfusion.
* **`PdfManipulator`:** Manipulación de estructura de PDFs existentes: renderizado de thumbnails (pdfrx), reordenamiento y eliminación de páginas (Syncfusion templates), inserción de nuevas páginas de imagen.

#### **D. Capa de Persistencia**
* **Base de Datos:** `drift` (SQLite). Esquema tipado y migraciones.
* **Archivos:** `LibraryStorage` maneja paths relativos vs absolutos y operaciones de FileSystem (mover, borrar, listar).
* **Settings:** `shared_preferences` para configuraciones ligeras.

---

## 3. Modelo de Datos (Esquema BD)

La base de datos (`AppDatabase`) define la estructura core:

| Tabla | Descripción |
| :--- | :--- |
| **`DocsTable`** | Archivos PDF. metadata básica (Título, Autor, Path relativo). `folder_id` referencia al `parent`. Soporta **Soft Delete** (`isDeleted`, `deletedAt`). |
| **`FoldersTable`** | Jerarquía de carpetas. `parent_id` permite anidamiento infinito. Soporta **Soft Delete** (`isDeleted`, `deletedAt`). |
| **`SetlistsTable`** | Cabeceras de listas de reproducción (Nombre, Notas). |
| **`SetlistItemsTable`** | Tabla pivote (Many-to-Many) ordenada. Vincula `Setlist` <-> `Doc`. |
| **`AnnotationStrokesTable`** | Trazos de tinta vectoriales. Vinculados a `docId` + `pageIndex`. Opcionalmente a `setlistId` (capa no destructiva). |
| **`DocStateTable`** | Estado de lectura por archivo (ej. última página vista). |

---

## 4. Estado Actual de Features

### ✅ Implementado y Estable
* **Sistema de Biblioteca:**
    * Carpetas anidables infinitas y CRUD completo.
    * Importación de archivos sueltos y carpetas recursivas.
* **Photo Scanner (Cámara → PDF):**
    * Captura a resolución nativa completa (sin límites de `maxWidth`/`imageQuality`).
    * Lista de páginas reordenable con progreso en tiempo real por tile.
    * **Editor con Corrección Proyectiva (Homografía 3x3)**:
        * 4 handles independientes para rectificación de perspectiva real.
        * **Resolución adaptativa**: 300 DPI (12MP+), 250 DPI (5-8MP), 200 DPI mínimo.
        * **Interpolación bicúbica** para líneas de pentagrama nítidas.
        * Procesamiento diferido en `Isolate.spawn` con `SendPort` para progreso en tiempo real.
        * **Bake Orientation**: Soporte nativo para fotos con rotación EXIF.
        * Filtros optimizados de B/N, Umbral, Brillo y Contraste.
    * **PdfGenerator** con compresión inteligente: pass-through de JPEGs sin re-codificar, solo re-procesa si excede 300 DPI.
    * Creación de PDF en background con progreso global (`AppData.backgroundTaskProgress`).
* **Editor de Páginas PDF (Edición Estructural):**
    * **Reordenar** páginas con drag & drop (`ReorderableListView`).
    * **Eliminar** páginas individuales con un tap.
    * **Agregar páginas** desde cámara, galería, u otro PDF de la biblioteca.
    * Thumbnails renderizados progresivamente desde el PDF original (pdfrx + package:image).
    * Preservación sin pérdida de páginas originales via `PdfTemplate` de Syncfusion.
    * Regeneración de PDF en background con progreso global.
    * Accesible desde el menú contextual de la biblioteca y desde el visor PDF.
* **Lector PDF (**`pdfrx`**):**
    * Navegación entre documentos y **Scrubber Vertical** (throttled).
    * Soporte para anotaciones con Lápiz y Resaltador por página/setlist.
* **Setlists:**
    * CRUD y Modo "Vivo" (navegación fluida).
* **Gestión de Archivos:**
    * Feedback de progreso y validaciones de integridad.
    * **Papelera de Reciclaje (Soft Delete)**:
        * Los archivos borrados se ocultan de la interfaz principal.
        * Restauración rápida con preservación de metadatos y anotaciones.
        * **Auto-cleanup**: Eliminación física automática tras 30 días.
        * Integración inteligente con backups e importaciones.
* **Compartir / Exportar (Offline):**
    * **Compartir PDF individual** desde el menú contextual (⋮) con nombre de display.
    * **Compartir Setlist como ZIP**: Archivos ordenados con zero-padding (`01 - Tema.pdf`).
    * **Compartir Setlist como `.setlist`**: Formato propietario con `data.json` + PDFs.
    * Compresión en **Isolate** con barra de progreso en tiempo real.
    * Accesible desde menú ⋮ de PDFs, lista de setlists y detalle de setlist.
* **Importar Setlists (`.setlist`):**
    * Registro de tipo de archivo en **Android** (`intent-filter`) e **iOS** (`CFBundleDocumentTypes` + UTI).
    * Recepción vía `MethodChannel` con soporte para **cold start** y **hot resume**.
    * **Detección por contenido** (no por extensión): verifica header ZIP + presencia de `data.json`.
    * Descompresión en Isolate → importación de PDFs en carpeta dedicada → creación de setlist.
    * Código nativo: `MainActivity.kt` (Android) + `AppDelegate.swift` (iOS).

### 🔮 Próximos Pasos
* **Nuevas Herramientas de Anotación:** Texto enriquecido, Formas geométricas, Sellos musicales.
* **Sincronización Cloud:** Soporte opcional para Drive/Dropbox.

---

## 5. Estructura de Directorios Clave

```text
lib/
├── data/
│   ├── repositories/       # Lógica (Library, Setlist, Import, PdfGenerator, etc.)
│   ├── app_data.dart       # Fachada Global (Orquestador)
│   ├── app_database.dart   # Definición de Schema Drift
│   ├── library_storage.dart# Abstracción de FileSystem
│   ├── backup_manager.dart # Backup/Restore con Isolates
│   ├── export_manager.dart # Compartir/Importar PDFs y Setlists
│   └── file_receiver_channel.dart # MethodChannel para archivos entrantes
├── models/                 # POJOs y Entidades (Score, Setlist, Stroke)
├── screens/                # Library, Reader, Setlists, Settings
└── widgets/                # UI Components Reutilizables
```