# ARCHITECTURE.md — Atril Digital (Flutter)

**Estado del Proyecto:** Consolidación — **v1.18.0 (Blindaje de datos: papelera, backup/restore, importaciones, anotaciones)**
**Fecha de Análisis:** Noviembre 2026
**Objetivo:** Ninguna operación (papelera, restore, importación, edición de páginas, deshacer) puede perder datos; cada camino crítico tiene tests de punta a punta.

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
* **`PageEditRepository`:** Orquesta la edición de páginas: genera el PDF (vía `PdfManipulator`), reubica las anotaciones según el nuevo orden (`remapAnnotationPages`, transaccional) y guarda un punto de restauración (PDF + anotaciones) en `atril/page_edit_undo/<docId>/` para deshacer. Si falla el guardado, restaura automáticamente. Notifica a los visores (`editRevision`) para que recarguen.
* **`PdfAnnotationFlattener`:** "Quema" las anotaciones sobre una **copia** del PDF para exportar (Syncfusion, en Isolate). Trazos y texto Latin-1 como vectores; sellos y texto no Latin-1 rasterizados en el main isolate. Respeta `/Rotate`. Comparte estilo con el visor vía `AnnotationStyle`.

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
| **`AnnotationStrokesTable`** | Trazos de tinta vectoriales. Vinculados a `docId` + `pageIndex` (una capa por documento). La columna `setlistId` se conserva solo por compatibilidad (siempre null). Índice `(doc_id, page_index)`. |
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
    * **Anotaciones preservadas:** se mueven con sus páginas; las de páginas eliminadas se borran. Páginas anotadas marcadas en el editor.
    * **Deshacer:** historial en el editor + deshacer la última edición guardada (un nivel por documento, PDF + anotaciones).
    * El visor abierto se recarga automáticamente tras editar/deshacer.
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
        * Restaurar un elemento cuyo contenedor sigue borrado lo lleva a la raíz; la purga nunca borra partituras activas (las rescata) y elimina también sus anotaciones. Todo en transacciones.
* **Compartir / Exportar (Offline):**
    * **Compartir PDF individual** desde el menú contextual (⋮) o el visor PDF, con nombre de display.
    * **Con o sin anotaciones** (`ExportActions` + `askIncludeAnnotations`): solo se pregunta si hay anotaciones involucradas. "Con anotaciones" usa `PdfAnnotationFlattener` sobre copias temporales; el original nunca se modifica.
    * **Exportar biblioteca para PC** (ZIP) con o sin anotaciones; nombres duplicados desambiguados.
    * **Compartir Setlist como ZIP**: Archivos ordenados con zero-padding (`01 - Tema.pdf`).
    * **Compartir Setlist como `.setlist`**: Formato propietario con `data.json` + PDFs. Opcionalmente incluye `annotations` por item (editables al importar; retrocompatible).
    * Compresión en **Isolate** con barra de progreso en tiempo real.
    * Accesible desde menú ⋮ de PDFs, lista de setlists y detalle de setlist.
* **Importar Setlists (`.setlist`):**
    * Registro de tipo de archivo en **Android** (`intent-filter`) e **iOS** (`CFBundleDocumentTypes` + UTI).
    * Recepción vía `MethodChannel` con soporte para **cold start** y **hot resume**.
    * **Detección por contenido** (no por extensión): verifica header ZIP + presencia de `data.json`.
    * Descompresión en Isolate → importación de PDFs en carpeta dedicada → creación de setlist.
    * Código nativo: `MainActivity.kt` (Android) + `AppDelegate.swift` (iOS).
* **Importar Backup (merge):** ahora migra también las anotaciones (capa global) de los documentos importados.
* **Autenticación y Acceso Offline (`AuthGate` / `_PermissionChecker`):**
    * Verificación online contra Firestore (`usuarios/{uid}`, `Source.server`, timeout 15 s). El resultado se cachea en `SettingsRepository` (`PermissionCache`).
    * Si la verificación falla, se usa el caché (válido 30 días). Con ≤5 días restantes se muestra `_OfflineWarningWrapper`.
    * **Revalidación automática:** mientras está en modo offline reintenta en silencio cada 2 minutos (`Timer.periodic`) y al volver a primer plano (`WidgetsBindingObserver`), sin pantalla de carga. Si falla, conserva el estado actual.
    * **Reintento manual:** botón "Reintentar" en el aviso; si falla muestra el error real (`FirebaseException.code`) en un SnackBar.
    * **Parseo tolerante** de `trial_atril_inicio` (Timestamp/DateTime/String/int), `suscripciones_apps` y `rol`: un tipo inesperado en Firestore ya no se confunde con "sin conexión".

### 🔮 Próximos Pasos
* **Nuevas Herramientas de Anotación:** Texto enriquecido, Formas geométricas, Sellos musicales.
* **Sincronización Cloud:** Soporte opcional para Drive/Dropbox.

---

### 🛡️ Garantías de integridad (v1.18.0)
* **Restore destructivo seguro:** valida el .atril (PRAGMA integrity_check + lectura con el esquema actual) antes de tocar nada; resguarda DB y docs/ como *.restore_bak; si algo falla vuelve a la biblioteca anterior; la DB siempre queda abierta.
* **Backup consistente:** VACUUM INTO en lugar de copiar el SQLite en caliente.
* **Importaciones transaccionales** (backup merge y .setlist): se copian los PDFs, se escribe todo en una transacción y, si falla, se borran los PDFs copiados.
* **Zip-slip / rutas:** los workers de descompresión, data.json y MainActivity no permiten escribir fuera del destino.
* **Anotaciones:** historial de deshacer por documento (se reinicia al cambiar de doc o editar páginas); "borrar página" deshacible; deshacer una edición de páginas reubica las anotaciones hechas después (solo se pierden las de páginas agregadas por esa edición, con aviso).
* **Memoria/DB consistentes:** efreshLibrary atómico y serializado; los setlists persisten antes de tocar la memoria.
* **Arranque robusto:** la auto-limpieza de papelera y de temporales no puede impedir que la app arranque.
* **Migración v5:** purga anotaciones huérfanas + índices; la migración v1→v4 ya no falla por columnas duplicadas.
* **Tests:** 44 (papelera, backup/restore e importaciones de punta a punta con isolates reales, migraciones, anotaciones, setlists).

## 5. Estructura de Directorios Clave

```text
lib/
├── data/
│   ├── repositories/       # Lógica (Library, Setlist, Import, PdfGenerator, PageEdit, AnnotationFlattener, etc.)
│   ├── app_data.dart       # Fachada Global (Orquestador)
│   ├── app_database.dart   # Definición de Schema Drift
│   ├── library_storage.dart# Abstracción de FileSystem
│   ├── backup_manager.dart # Backup/Restore con Isolates
│   ├── export_manager.dart # Compartir/Importar PDFs y Setlists
│   └── file_receiver_channel.dart # MethodChannel para archivos entrantes
├── models/                 # POJOs y Entidades (Score, Setlist, Stroke, AnnotationStyle)
├── screens/                # Library, Reader, Setlists, Settings
└── widgets/                # UI Components Reutilizables
```