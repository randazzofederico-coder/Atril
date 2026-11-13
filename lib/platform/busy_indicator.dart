import 'busy_indicator_stub.dart' if (dart.library.js_interop) 'busy_indicator_web.dart' as impl;

/// Web: muestra/oculta una línea animada arriba de todo, dibujada por el
/// navegador (CSS) y no por Flutter, así sigue moviéndose aunque la página
/// esté ocupada (copiando archivos grandes, etc.). No-op fuera de web.
void setWebBusy(bool busy) => impl.setWebBusy(busy);
