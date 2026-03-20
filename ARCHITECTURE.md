# ARCHITECTURE.md — Atril Digital (Flutter)

**Estado del Proyecto:** Consolidación — **v1.14.0 (Recycle Bin & Trash Management)**
**Fecha de Análisis:** Marzo 2026
**Objetivo:** Importación desde cámara con rectificación proyectiva real (Homografía 3x3).

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
* **`PdfGenerator`:** Generación de PDFs multi-página desde imágenes usando Syncfusion.

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
    * Lista de páginas reordenable con persistencia.
    * **Editor con Corrección Proyectiva (Homografía 3x3)**:
        * 4 handles independientes para rectificación de perspectiva real.
        * Procesamiento en segundo plano (**Isolates / `compute`**) para evitar bloqueos de UI.
        * **Bake Orientation**: Soporte nativo para fotos con rotación EXIF.
        * Filtros optimizados de B/N, Umbral, Brillo y Contraste.
    * Generación de PDF multi-página.
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
│   └── library_storage.dart# Abstracción de FileSystem
├── models/                 # POJOs y Entidades (Score, Setlist, Stroke)
├── screens/                # Library, Reader, Setlists, Settings
└── widgets/                # UI Components Reutilizables
```