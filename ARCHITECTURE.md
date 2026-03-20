# ARCHITECTURE.md — Atril Digital (Flutter)

**Estado del Proyecto:** Consolidación — **v1.12.0 (Photo Scanner & Image Editor)**
**Fecha de Análisis:** Marzo 2026
**Objetivo:** Importación desde cámara con edición de imagen pre-PDF.

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
| **`DocsTable`** | Archivos PDF. metadata básica (Título, Autor, Path relativo). `folder_id` referencia al `parent`. |
| **`FoldersTable`** | Jerarquía de carpetas. `parent_id` permite anidamiento infinito. |
| **`SetlistsTable`** | Cabeceras de listas de reproducción (Nombre, Notas). |
| **`SetlistItemsTable`** | Tabla pivote (Many-to-Many) ordenada. Vincula `Setlist` <-> `Doc`. |
| **`AnnotationStrokesTable`** | Trazos de tinta vectoriales. Vinculados a `docId` + `pageIndex`. Opcionalmente a `setlistId` (capa no destructiva). |
| **`DocStateTable`** | Estado de lectura por archivo (ej. última página vista). |

---

## 4. Estado Actual de Features

### ✅ Implementado y Estable
* **Sistema de Biblioteca:**
    * Carpetas anidables infinitas.
    * Breadcrumbs de navegación.
    * CRUD completo (Renombrar, Mover, Borrar) para archivos y carpetas.
    * Importación de archivos sueltos y carpetas recursivas.
* **Photo Scanner (Cámara → PDF):**
    * Captura desde cámara y selección desde galería.
    * Lista de páginas reordenable con drag & drop.
    * **Editor de imagen pre-PDF** con 4 herramientas:
        * Rotación (90° incremental).
        * Blanco/Negro con umbral ajustable (pre-rendering software para uniformidad).
        * Brillo y Contraste (sliders independientes, -100 a +100).
        * Recorte con 4 handles arrastrables y overlay de regla de tercios.
    * Persistencia de parámetros de edición al re-editar páginas.
    * Generación de PDF multi-página vía `syncfusion_flutter_pdf`.
* **Lector PDF:**
    * Motor nativo rápido (**`pdfrx`**).
    * **Navegación Intuitiva:** 
        * Salto entre documentos (Siguiente/Anterior) manteniendo el contexto.
        * **Scrubber Vertical:** Barra de desplazamiento lateral para documentos largos, optimizada para rendimiento (throttling) y desacoplada del renderizado para evitar saltos visuales.
    * Scroll vertical continuo.
* **Anotaciones:**
    * Lápiz (color negro default, grosor ajustable 1–20px).
    * Resaltador (amarillo transparente, grosor ajustable).
    * Capas no destructivas por setlist.
* **Setlists:**
    * Creación y edición.
    * Modo "Vivo" (navegación continuada entre partituras).
* **Gestión de Archivos Robusta:**
    * **Feedback de Progreso:** Indicadores visuales precisos en operaciones de larga duración (Borrado recursivo, Importación masiva, Backups).
    * Validación de nombres duplicados y integridad referencial.

### 🔮 Próximos Pasos
* **B/N en tiempo real:** Optimizar el preview de umbral para que actualice durante el drag del slider (actualmente se renderiza al soltar).
* **Corrección de Perspectiva:** Crop con 4 puntos libres + homografía para corregir fotos tomadas en ángulo.
* **Nuevas Herramientas de Anotación:** Texto enriquecido, Formas geométricas, Sellos musicales.

---

## 5. Estructura de Directorios Clave

```text
lib/
├── data/
│   ├── repositories/       # Lógica de Negocio (Library, Setlist, Import, PdfGenerator, etc.)
│   ├── app_data.dart       # Fachada Global (Orquestador)
│   ├── app_database.dart   # Definición de Schema Drift
│   └── library_storage.dart# Abstracción de FileSystem
├── models/                 # POJOs y Entidades (Score, Setlist, Stroke)
├── screens/
│   ├── library/            # Biblioteca + LibraryActions + PhotoScanner + ImageEditor
│   ├── reader/             # Visor PDF + Capas de Anotación
│   ├── setlists/           # Gestión de Listas
│   └── settings/           # Configuración
└── widgets/                # UI Components Reutilizables
```