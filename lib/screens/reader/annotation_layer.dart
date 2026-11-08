import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../models/annotation_stroke.dart';
import '../../models/annotation_style.dart';

/// Página concreta de un documento (para notificar recargas).
class AnnotationPageRef {
  final String docId;
  final int pageIndex;
  const AnnotationPageRef(this.docId, this.pageIndex);
}

enum _HistoryType { add, clear }

class _HistoryEntry {
  final _HistoryType type;

  /// add: un solo trazo. clear: todos los trazos borrados de la página.
  final List<AnnotationStroke> strokes;
  final String docId;
  final int pageIndex;

  _HistoryEntry.add(AnnotationStroke s)
      : type = _HistoryType.add,
        strokes = [s],
        docId = s.docId,
        pageIndex = s.pageIndex;

  _HistoryEntry.clear(this.docId, this.pageIndex, this.strokes) : type = _HistoryType.clear;
}

/// Controlador imperativo de las capas de anotación de UN documento a la vez.
///
/// - Mantiene el historial de deshacer/rehacer. El historial pertenece a un
///   solo documento: [reset] se debe llamar al cambiar de documento o cuando
///   las páginas del documento cambian (edición de páginas), para que
///   deshacer nunca toque trazos de otro PDF ni de páginas reubicadas.
/// - Serializa las operaciones contra la DB (tocar Deshacer varias veces
///   rápido no genera escrituras concurrentes).
class AnnotationLayerController {
  final StreamController<AnnotationPageRef> _refreshController =
      StreamController<AnnotationPageRef>.broadcast();
  Stream<AnnotationPageRef> get onPageRefresh => _refreshController.stream;

  final List<_HistoryEntry> _history = [];
  final List<_HistoryEntry> _redoStack = [];

  Future<void> _queue = Future<void>.value();

  /// Ejecuta [op] después de las operaciones anteriores (en orden).
  Future<void> _run(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.catchError((Object e) => debugPrint('Annotation op error: $e'));
    return next;
  }

  void _notify(String docId, int pageIndex) {
    if (!_refreshController.isClosed) {
      _refreshController.add(AnnotationPageRef(docId, pageIndex));
    }
  }

  /// Descarta el historial (al cambiar de documento o tras editar páginas).
  void reset() {
    _history.clear();
    _redoStack.clear();
  }

  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Registra un trazo nuevo (la capa ya lo muestra de forma optimista).
  Future<void> addStroke(AnnotationStroke stroke) => _run(() async {
        await AppData.insertAnnotationStroke(stroke);
        _history.add(_HistoryEntry.add(stroke));
        _redoStack.clear();
      });

  Future<void> undo() => _run(() async {
        if (_history.isEmpty) return;
        final entry = _history.last;
        switch (entry.type) {
          case _HistoryType.add:
            await AppData.deleteAnnotationStroke(entry.strokes.first.id);
            break;
          case _HistoryType.clear:
            for (final s in entry.strokes) {
              await AppData.insertAnnotationStroke(s);
            }
            break;
        }
        _history.removeLast();
        _redoStack.add(entry);
        _notify(entry.docId, entry.pageIndex);
      });

  Future<void> redo() => _run(() async {
        if (_redoStack.isEmpty) return;
        final entry = _redoStack.last;
        switch (entry.type) {
          case _HistoryType.add:
            await AppData.insertAnnotationStroke(entry.strokes.first);
            break;
          case _HistoryType.clear:
            for (final s in entry.strokes) {
              await AppData.deleteAnnotationStroke(s.id);
            }
            break;
        }
        _redoStack.removeLast();
        _history.add(entry);
        _notify(entry.docId, entry.pageIndex);
      });

  /// Borra todos los trazos de una página. Se puede deshacer.
  Future<void> clearPage(String docId, int pageIndex) => _run(() async {
        final strokes = await AppData.getAnnotationStrokesForPage(
          docId: docId,
          pageIndex: pageIndex,
        );
        if (strokes.isEmpty) return;
        await AppData.deleteAnnotationStrokesForPage(docId: docId, pageIndex: pageIndex);
        _history.add(_HistoryEntry.clear(docId, pageIndex, strokes));
        _redoStack.clear();
        _notify(docId, pageIndex);
      });

  void dispose() {
    _refreshController.close();
  }
}

/// Capa (overlay) que muestra y, opcionalmente, edita las anotaciones de UNA
/// página. Las coordenadas se guardan normalizadas [0..1] respecto de la
/// página, así que son estables entre dispositivos, resoluciones y zoom.
class AnnotationLayer extends StatefulWidget {
  final AnnotationLayerController? controller;

  final String docId;
  final int pageIndex; // 1-based
  final bool editable;

  final AnnotationTool tool;
  final double width;
  final Color color;

  /// If true, the layer will ignore pointer events (display-only).
  final bool ignorePointers;

  /// Tamaño de la página en puntos PDF (sin zoom).
  ///
  /// pdfrx dibuja los overlays en coordenadas de pantalla (el canvas crece
  /// con el zoom). Con este dato el painter escala grosores, texto y sellos
  /// junto con la página, de modo que el trazo "pertenece" al papel.
  /// Si es null, se dibuja sin escalar (1 unidad = 1 px lógico).
  final Size? pageSize;

  const AnnotationLayer({
    super.key,
    this.controller,
    required this.docId,
    required this.pageIndex,
    required this.editable,
    required this.tool,
    required this.width,
    required this.color,
    this.ignorePointers = false,
    this.pageSize,
  });

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  /// Lista inmutable: se reemplaza (no se muta) para que el painter detecte
  /// el cambio y repinte.
  List<AnnotationStroke> _strokes = const <AnnotationStroke>[];
  
  // stroke being drawn (normalized points)
  List<Offset>? _draftPoints;
  int _draftRevision = 0;

  // Pointer tracking: con 2+ dedos se cancela el trazo en curso.
  final Set<int> _activePointers = <int>{};
  bool _allowDrawing = true;

  StreamSubscription<AnnotationPageRef>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  void _subscribe() {
    _refreshSub?.cancel();
    _refreshSub = widget.controller?.onPageRefresh.listen((ref) {
      if (ref.docId == widget.docId && ref.pageIndex == widget.pageIndex) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscribe();
    }
    if (oldWidget.docId != widget.docId || oldWidget.pageIndex != widget.pageIndex) {
      _load();
    }
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final docId = widget.docId;
    final pageIndex = widget.pageIndex;
    final rows = await AppData.getAnnotationStrokesForPage(
      docId: docId,
      pageIndex: pageIndex,
    );
    // Si mientras tanto cambió la página/doc, descartamos el resultado viejo.
    if (!mounted || docId != widget.docId || pageIndex != widget.pageIndex) return;
    setState(() {
      _strokes = List.unmodifiable(rows);
    });
  }

  Future<void> _persist(AnnotationStroke stroke) async {
    // Optimista: se muestra ya; la persistencia sigue en segundo plano.
    setState(() => _strokes = List.unmodifiable([..._strokes, stroke]));

    try {
      if (widget.controller != null) {
        await widget.controller!.addStroke(stroke);
      } else {
        await AppData.insertAnnotationStroke(stroke);
      }
    } catch (e) {
      debugPrint('Error guardando anotación: $e');
      if (mounted) {
        setState(() => _strokes =
            List.unmodifiable(_strokes.where((s) => s.id != stroke.id)));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la anotación')),
        );
      }
    }
  }

  Future<void> _commitStroke(List<Offset> pointsNorm) async {
    if (pointsNorm.length < 2) return;

    final stroke = AnnotationStroke(
      id: AppData.newId(prefix: 'stk'),
      docId: widget.docId,
      pageIndex: widget.pageIndex,
      tool: widget.tool,
      width: widget.width,
      color: widget.color,
      pointsNorm: pointsNorm,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist(stroke);
  }

  Offset _normalize(Offset local, Size size) {
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _addDraftPoint(Offset p) {
    _draftPoints!.add(p);
    _draftRevision++;
  }
  
  bool get _isTextOrStamp => widget.tool == AnnotationTool.text || widget.tool == AnnotationTool.stamp;

  @override
  Widget build(BuildContext context) {
    final displayOnly = widget.ignorePointers || !widget.editable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        
        Widget painted = RepaintBoundary(
          child: CustomPaint(
            painter: _AnnotationPainter(
              strokes: _strokes,
              draftPoints: _draftPoints,
              draftRevision: _draftRevision,
              draftTool: widget.tool,
              draftWidth: widget.width,
              draftColor: widget.color,
              pageSize: widget.pageSize,
            ),
            size: Size.infinite,
          ),
        );
        
        if (displayOnly) {
           return IgnorePointer(child: painted);
        }
        // Standard Listener - always gets events, non-competitive.
        // Nota: en modo edición la capa captura los toques (no hay pinch-zoom
        // sobre la página); con 2+ dedos se cancela el trazo en curso.
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
             _activePointers.add(e.pointer);
             
             if (_activePointers.length > 1) {
                // Multi-touch: Cancel drawing immediately
                _allowDrawing = false;
                setState(() => _draftPoints = null);
             } else {
                _allowDrawing = true;
                if (_isStrokeTool) {
                   setState(() {
                     _draftPoints = <Offset>[_normalize(e.localPosition, size)];
                     _draftRevision++;
                   });
                }
             }
          },
          onPointerMove: (e) {
             if (!_allowDrawing || !_isStrokeTool || _draftPoints == null) return;
             setState(() => _addDraftPoint(_normalize(e.localPosition, size)));
          },
          onPointerUp: (e) {
             _activePointers.remove(e.pointer);

             if (_isStrokeTool && _draftPoints != null) {
                 final points = List<Offset>.from(_draftPoints!);
                 setState(() => _draftPoints = null);
                 _commitStroke(points);
             }
             
             if (_activePointers.isEmpty) {
               _allowDrawing = true;
             }
          },
          onPointerCancel: (e) {
             _activePointers.remove(e.pointer);
             setState(() => _draftPoints = null);
             if (_activePointers.isEmpty) {
               _allowDrawing = true;
             }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) async {
                if (_isTextOrStamp) {
                  final pos = _normalize(details.localPosition, size);
                  await _handleTapPlacement(context, pos);
                }
            },
            child: painted,
          ),
        );
      },
    );
  }
  
  bool get _isStrokeTool => 
      !_isTextOrStamp;

  Future<void> _handleTapPlacement(BuildContext context, Offset pos) async {
    if (widget.tool == AnnotationTool.text) {
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => const _InsertTextDialog(),
      );
      if (text != null && text.isNotEmpty) {
        await _commitItem(pos, text, widget.tool);
      }
    } else if (widget.tool == AnnotationTool.stamp) {
        final stampId = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Seleccionar Sello'),
            children: [
               for (final id in const ['coda', 'segno', 'warning', 'star'])
                 SimpleDialogOption(
                   onPressed: () => Navigator.pop(ctx, id),
                   child: Icon(AnnotationStyle.stampIcon(id), size: 32),
                 ),
            ],
          )
        );
        if (stampId != null) {
          await _commitItem(pos, stampId, widget.tool);
        }
    }
  }

  Future<void> _commitItem(Offset pos, String content, AnnotationTool tool) async {
    final stroke = AnnotationStroke(
      id: AppData.newId(prefix: 'stk'),
      docId: widget.docId,
      pageIndex: widget.pageIndex,
      tool: tool,
      width: 0, // Not used for text/stamp
      pointsNorm: [pos],
      color: widget.color,
      content: content,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    await _persist(stroke);
  }
}

/// Diálogo para insertar texto (dueño de su TextEditingController).
class _InsertTextDialog extends StatefulWidget {
  const _InsertTextDialog();

  @override
  State<_InsertTextDialog> createState() => _InsertTextDialogState();
}

class _InsertTextDialogState extends State<_InsertTextDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insertar Texto'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Escribe aquí...'),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Insertar')),
      ],
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset>? draftPoints;

  /// Cambia con cada punto agregado al trazo en curso (la lista se muta).
  final int draftRevision;
  final AnnotationTool? draftTool;
  final double? draftWidth;
  final Color? draftColor;
  final Size? pageSize;

  _AnnotationPainter({
    required this.strokes,
    required this.draftPoints,
    required this.draftRevision,
    this.draftTool,
    this.draftWidth,
    this.draftColor,
    this.pageSize,
  });

  @override
  void paint(Canvas canvas, Size screenSize) {
    // Pintamos en unidades de página (puntos PDF) y escalamos el canvas al
    // tamaño en pantalla: así grosor, texto y sellos acompañan al zoom.
    final ref = pageSize;
    final hasRef = ref != null && ref.width > 0 && ref.height > 0;
    final scale = hasRef ? screenSize.width / ref.width : 1.0;
    final size = hasRef ? ref : screenSize;

    canvas.save();
    canvas.scale(scale);
    
    for (final s in strokes) {
      _paintItem(canvas, size, s);
    }
    
    // Draw draft (only for strokes)
    final dp = draftPoints;
    if (dp != null && dp.length >= 2 && draftTool != null) {
       final tool = draftTool!;
       final width = draftWidth ?? 2.0;
       final color = draftColor ?? _defaultColorForTool(tool);

       _paintStroke(canvas, size, tool, width, dp, color);
    }

    canvas.restore();
  }

  void _paintItem(Canvas canvas, Size size, AnnotationStroke s) {
     final color = s.color ?? _defaultColorForTool(s.tool);
     switch (s.tool) {
       case AnnotationTool.text:
         if (s.pointsNorm.isEmpty) return;
         _paintText(canvas, size, s.pointsNorm.first, s.content ?? '', color);
         break;
       case AnnotationTool.stamp:
         if (s.pointsNorm.isEmpty) return;
         _paintStamp(canvas, size, s.pointsNorm.first, s.content ?? '', color);
         break;
       case AnnotationTool.pen:
       case AnnotationTool.highlighter:
       case AnnotationTool.whiteout:
         _paintStroke(canvas, size, s.tool, s.width, s.pointsNorm, color);
         break;
     }
  }

  Color _defaultColorForTool(AnnotationTool tool) =>
      AnnotationStyle.defaultColorForTool(tool);

  void _paintStroke(
    Canvas canvas,
    Size size,
    AnnotationTool tool,
    double width,
    List<Offset> pointsNorm,
    Color color,
  ) {
    if (pointsNorm.length < 2) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width // En puntos de página: escala con el zoom
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = tool == AnnotationTool.highlighter
          ? color.withValues(alpha: AnnotationStyle.highlighterAlpha)  // Highlighter always semi-transparent
          : color;

    final path = Path();
    final first = pointsNorm.first;
    path.moveTo(first.dx * size.width, first.dy * size.height);
    for (var i = 1; i < pointsNorm.length; i++) {
      final p = pointsNorm[i];
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  void _paintText(Canvas canvas, Size size, Offset normPos, String text, Color color) {
    final textPainter = AnnotationStyle.textPainter(text, color, maxWidth: size.width);
    
    final offset = Offset(normPos.dx * size.width, normPos.dy * size.height);
    textPainter.paint(canvas, offset);
  }

  void _paintStamp(Canvas canvas, Size size, Offset normPos, String stampId, Color color) {
     final painter = AnnotationStyle.stampPainter(stampId, color);
     
     final x = (normPos.dx * size.width) - (painter.width / 2);
     final y = (normPos.dy * size.height) - (painter.height / 2);
     painter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return !identical(oldDelegate.strokes, strokes) ||
           !identical(oldDelegate.draftPoints, draftPoints) ||
           oldDelegate.draftRevision != draftRevision ||
           oldDelegate.pageSize != pageSize ||
           oldDelegate.draftWidth != draftWidth ||
           oldDelegate.draftColor != draftColor ||
           oldDelegate.draftTool != draftTool;
  }
}
