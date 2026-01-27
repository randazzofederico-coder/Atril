# ARCHITECTURE.md — Atril Digital (Flutter)

**Estado del Proyecto:** Canon — **v1.9.0 (Metadata & Structure Polish)**
**Prioridad Actual:** [UX] Setlists & Modo Vivo.
**Fecha última actualización:** Enero 2026

---

## 1. Filosofía Central (Prime Directive)

**"Seguridad en el Escenario"**
La estabilidad es innegociable.
* **Robustez:** Preferimos código aburrido, probado y modular.
* **Feedback:** El usuario nunca debe adivinar si la app se colgó o si una acción terminó.

---

## 2. Arquitectura General

* **Core:** Flutter (Material 3).
* **Persistencia:** `drift` (SQLite) + `LibraryStorage` (FS local).
* **Organización de Código (Refactor v1.9.0):**
    * `data/repositories/`: Lógica de negocio pura (DB + Storage).
    * `screens/<feature>/`: Pantallas agrupadas por dominio (library, setlists, reader).
* **Lógica y Datos:** Patrón **Fachada (Facade)**.
    * **`AppData`:** Orquestador de Estado Global y Caché en Memoria.
    * **Repositorios:** `LibraryRepository`, `SetlistRepository`, `ImportRepository`, `AnnotationRepository`.

### Nuevos Patrones de UI
* **Actions Delegates:** `LibraryActions` maneja la lógica de diálogos (renombrar, borrar, mover), separándola del `build` de la pantalla.
* **Visual Context:** Uso de elementos deshabilitados ("fantasmas") para dar contexto en selectores de movimiento.

---

## 3. Definiciones de UI y Navegación

### 3.1. Estándar de AppBar (Library)
* **Zona Izquierda:** Root ("Biblioteca") o Back + Breadcrumbs (Indicador de ruta).
* **Zona Derecha:** Search, Import (+), New Folder, Settings.

### 3.2. Modos de Interacción
* **Modo Edición (3 Puntos):** Acciones individuales (Renombrar, Editar Autor, Detalles).
* **Modo Selección (Mantener apretado):** Acciones en masa (Mover, Borrar, Crear Setlist).
* **Modo Picker (FolderPicker):** Muestra partituras grisadas para contexto, pero solo permite seleccionar carpetas.

---

## 4. Log de Sesiones

### Sesión Actual (v1.9.0 - Metadata & Folder Structure)
**Objetivo:** Limpieza visual del proyecto y enriquecimiento de datos.
* **Estructura:** Reorganización masiva de archivos en carpetas semánticas (`data/repositories`, `screens/library`, etc.).
* **Feature:** Implementación de edición de **Título y Autor** (Metadata) en base de datos y UI.
* **UX:** Mejoras en `FolderPickerScreen` mostrando archivos grisados (disabled) para dar contexto al mover items.
* **Fix:** Implementación faltante de `renameFolder` en `LibraryActions`.

### Sesión Previa (v1.8.0 - AppData Purity Refactor)
* **Refactor:** `AppData` transformado en orquestador puro; lógica movida a Repositorios.
* **Refactor:** `LibraryRepository` absorbió utilidades de PDF.

---

## 5. Roadmap / Próximos Pasos

1.  **[UX] Experiencia Setlist y Modo Vivo (Prioridad Alta):**
    * Revisar el flujo de uso en el escenario.
    * Mejorar la transición entre temas y la visibilidad de controles.

2.  **[Fix/Redesign] Sistema de Backup:**
    * *Investigación:* El sistema actual de Import/Export (.atril ZIP) presenta fallos.
    * *Propuesta:* Debuggear o imaginar una alternativa más robusta (ej: exportación plana de carpetas o sincronización).

3.  **[Feature] Configuraciones de UI:**
    * **Modo Nocturno:** Toggle para invertir colores en la interfaz (no en el PDF).
    * **Escala de UI:** Opción para agrandar textos/botones (accesibilidad en escenario).

4.  **[UX] Breadcrumbs Inteligentes:**
    * Manejo de rutas largas en la barra superior.
    * Implementar truncado visual: `Biblioteca / ... / Autores / Bach`.

5.  **[Feature] Zoom y Pan en Anotaciones:**
    * Mejorar la capa de dibujo para soportar zoom mientras se edita (actualmente bloquea gestos).