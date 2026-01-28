import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../models/annotation_stroke.dart';

/// Overlay layer that displays and (optionally) edits non-destructive annotations.
///
/// v1 scope:
/// - Global layer only (setlistId = null).
/// - Freehand strokes (pen + highlighter).
///
/// Coordinates are normalized [0..1] relative to the viewport used for drawing.
/// This keeps annotations stable across devices and resolutions.
/// Imperative controller for [AnnotationLayer].
///
/// Useful to trigger undo/redo/clear from an external toolbar.
/// Action types for Undo/Redo
enum _HistoryRef { add } // 'buffer' implies cleared page dump (omitting for now, v1 only undoes Adds)

class _HistoryEntry {
  final _HistoryRef type;
  final AnnotationStroke stroke;
  _HistoryEntry(this.type, this.stroke);
}

/// Overlay layer that displays and (optionally) edits non-destructive annotations.
///
/// v1 scope:
/// - Global layer only (setlistId = null).
/// - Freehand strokes (pen + highlighter).
///
/// Coordinates are normalized [0..1] relative to the viewport used for drawing.
/// This keeps annotations stable across devices and resolutions.
/// Imperative controller for [AnnotationLayer].
///
/// Useful to trigger undo/redo/clear from an external toolbar.
class AnnotationLayerController {
  // Key: PageIndex, Value: ignored (just notifies)
  final StreamController<int> _refreshController = StreamController<int>.broadcast();
  Stream<int> get onPageRefresh => _refreshController.stream;

  final List<_HistoryEntry> _history = [];
  final List<_HistoryEntry> _redoStack = [];

  // Registers a new stroke (committed by UI)
  Future<void> addStroke(AnnotationStroke stroke) async {
     await AppData.insertAnnotationStroke(stroke);
     _history.add(_HistoryEntry(_HistoryRef.add, stroke));
     _redoStack.clear();
     _refresh(); // Notify listeners
  }

  Future<void> undo() async {
    if (_history.isEmpty) return;
    final entry = _history.removeLast();
    _redoStack.add(entry);

    if (entry.type == _HistoryRef.add) {
      await AppData.deleteAnnotationStroke(entry.stroke.id);
      _refreshController.add(entry.stroke.pageIndex);
    }
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _history.add(entry);

    if (entry.type == _HistoryRef.add) {
       await AppData.insertAnnotationStroke(entry.stroke);
       _refreshController.add(entry.stroke.pageIndex);
    }
  }
  
  // For now, Clear Page is destructive (cannot undo easily without dumping all strokes to memory).
  // We will just clear DB and history references to that page.
  Future<void> clearPage(String docId, int pageIndex, String? setlistId) async {
    await AppData.deleteAnnotationStrokesForPage(
      docId: docId,
      pageIndex: pageIndex,
      setlistId: setlistId,
    );
    // Remove history entries for this page to avoid "undoing" a ghost stroke
    _history.removeWhere((e) => e.stroke.pageIndex == pageIndex && e.stroke.docId == docId);
    _redoStack.removeWhere((e) => e.stroke.pageIndex == pageIndex && e.stroke.docId == docId);
    
    _refreshController.add(pageIndex);
  }
  
  void _refresh() {
     // Notify all (or could accept pagenum to optimize)
     // Since addStroke is specific to a page, we usually know. 
     // But for now, let's just assume the last stroke knows its page.
     if (_history.isNotEmpty) {
       _refreshController.add(_history.last.stroke.pageIndex);
     }
  }
}

class AnnotationLayer extends StatefulWidget {
  final AnnotationLayerController? controller;

  final String docId;
  final String? setlistId; // future layer
  final int pageIndex; // 1-based
  final bool editable;

  final AnnotationTool tool;
  final double width;

  /// If true, the layer will ignore pointer events (display-only).
  final bool ignorePointers;

  const AnnotationLayer({
    super.key,
    this.controller,
    required this.docId,
    required this.pageIndex,
    required this.editable,
    required this.tool,
    required this.width,
    this.setlistId,
    this.ignorePointers = false,
  });

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  final List<AnnotationStroke> _strokes = <AnnotationStroke>[];
  // Local redo stack removed - handled by GLOBAL controller
  
  // stroke being drawn (normalized points)
  List<Offset>? _draftPoints;

  // pointer tracking to allow 2-finger pinch/zoom to reach the PDF viewer
  final Set<int> _activePointers = <int>{};
  bool _allowDrawing = true;

  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    // Listen for global events (Undo/Redo affects this page?)
    _refreshSub = widget.controller?.onPageRefresh.listen((pageIndex) {
       if (pageIndex == widget.pageIndex) {
         _load();
       }
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant AnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docId != widget.docId ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.setlistId != widget.setlistId) {
      _load();
    }
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await AppData.getAnnotationStrokesForPage(
      docId: widget.docId,
      pageIndex: widget.pageIndex,
      setlistId: widget.setlistId,
    );
    if (!mounted) return;
    setState(() {
      _strokes
        ..clear()
        ..addAll(rows);
      _draftPoints = null;
    });
  }

  Future<void> _commitStroke(List<Offset> pointsNorm) async {
    if (pointsNorm.length < 2) return;

    final stroke = AnnotationStroke(
      id: AppData.newId(prefix: 'stk'),
      docId: widget.docId,
      setlistId: widget.setlistId,
      pageIndex: widget.pageIndex,
      tool: widget.tool,
      width: widget.width,
      pointsNorm: pointsNorm,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    // Delegate to Global Controller (handles DB + History)
    if (widget.controller != null) {
      await widget.controller!.addStroke(stroke);
    } else {
      // Fallback for no controller (shouldn't happen in app)
      await AppData.insertAnnotationStroke(stroke);
      if (mounted) setState(() => _strokes.add(stroke));
    }
  }
  
  // Undo/Redo/Clear are now handled by controller calling _load() via stream


  Offset _normalize(Offset local, Size size) {
    return Offset(local.dx / size.width, local.dy / size.height);
  }
  
  bool get _isTextOrStamp => widget.tool == AnnotationTool.text || widget.tool == AnnotationTool.stamp;

  @override
  Widget build(BuildContext context) {
    final displayOnly = widget.ignorePointers || !widget.editable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        
        Widget painted = CustomPaint(
          painter: _AnnotationPainter(
            strokes: _strokes,
            draftPoints: _draftPoints,
            draftTool: widget.tool,
            draftWidth: widget.width,
          ),
          size: Size.infinite,
        );
        
        if (displayOnly) {
           return IgnorePointer(child: painted);
        }
        // Standard Listener - always gets events, non-competitive
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
                   _draftPoints = <Offset>[_normalize(e.localPosition, size)];
                   setState(() {});
                }
             }
          },
          onPointerMove: (e) {
             if (!_allowDrawing || !_isStrokeTool || _draftPoints == null) return;
             final pts = _draftPoints!;
             pts.add(_normalize(e.localPosition, size));
             setState(() {});
          },
          onPointerUp: (e) {
             _activePointers.remove(e.pointer);

             if (_isStrokeTool && _draftPoints != null) {
                 _commitStroke(List<Offset>.from(_draftPoints!));
                 setState(() => _draftPoints = null);
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
        builder: (ctx) {
           final ctrl = TextEditingController();
           return AlertDialog(
             title: const Text('Insertar Texto'),
             content: TextField(
               controller: ctrl,
               autofocus: true,
               decoration: const InputDecoration(hintText: 'Escribe aquí...'),
               textCapitalization: TextCapitalization.sentences,
             ),
             actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
               FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Insertar')),
             ],
           );
        }
      );
      if (text != null && text.isNotEmpty) {
        // Commit text
        await _commitItem(pos, text, widget.tool);
      }
    } else if (widget.tool == AnnotationTool.stamp) {
        // For v1, we just cycle a default stamp or show a mini-picker?
        // Let's use a default "Star" for now or a mini-dialog.
        // Doing a quick mini-picker for demo.
        final stampId = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Seleccionar Sello'),
            children: [
               SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'coda'), child: const Icon(Icons.music_note, size: 32)),
               SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'segno'), child: const Icon(Icons.repeat, size: 32)),
               SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'warning'), child: const Icon(Icons.warning_amber_rounded, size: 32)),
               SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'star'), child: const Icon(Icons.star, size: 32)),
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
      setlistId: widget.setlistId,
      pageIndex: widget.pageIndex,
      tool: tool,
      width: 0, // Not used for text/stamp
      pointsNorm: [pos],
      color: Colors.black, // Default color for now
      content: content,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    if (widget.controller != null) {
      await widget.controller!.addStroke(stroke);
    } else {
      await AppData.insertAnnotationStroke(stroke);
      if (mounted) setState(() => _strokes.add(stroke));
    }
  }
}



class _AnnotationPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset>? draftPoints;
  final AnnotationTool? draftTool;
  final double? draftWidth;

  _AnnotationPainter({
    required this.strokes,
    required this.draftPoints,
    this.draftTool,
    this.draftWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // No manual transform needed - handled by parent InteractiveViewer
    
    for (final s in strokes) {
      _paintItem(canvas, size, s);
    }
    
    // Draw draft (only for strokes)
    final dp = draftPoints;
    if (dp != null && dp.length >= 2 && draftTool != null) {
       final tool = draftTool!;
       final width = draftWidth ?? 2.0;
       final color = _defaultColorForTool(tool);

       _paintStroke(canvas, size, tool, width, dp, color);
    }
  }

  void _paintItem(Canvas canvas, Size size, AnnotationStroke s) {
     switch (s.tool) {
       case AnnotationTool.text:
         if (s.pointsNorm.isEmpty) return;
         _paintText(canvas, size, s.pointsNorm.first, s.content ?? '', s.color ?? Colors.black);
         break;
       case AnnotationTool.stamp:
         if (s.pointsNorm.isEmpty) return;
         _paintStamp(canvas, size, s.pointsNorm.first, s.content ?? '', s.color ?? Colors.red);
         break;
       default:
         // Strokes (Pen, Highlighter, Whiteout)
         final color = s.color ?? _defaultColorForTool(s.tool);
         _paintStroke(canvas, size, s.tool, s.width, s.pointsNorm, color);
         break;
     }
  }

  Color _defaultColorForTool(AnnotationTool tool) {
    switch (tool) {
      case AnnotationTool.pen: return Colors.redAccent;
      case AnnotationTool.highlighter: return Colors.yellow.withValues(alpha: 0.40);
      case AnnotationTool.whiteout: return Colors.white;
      default: return Colors.black;
    }
  }

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
      ..strokeWidth = width // Natural scaling (width zooms with page)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;
    
    // Whiteout logic
    if (tool == AnnotationTool.whiteout) {
      paint.blendMode = BlendMode.srcOver; 
    }

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
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);
    
    final offset = Offset(normPos.dx * size.width, normPos.dy * size.height);
    textPainter.paint(canvas, offset);
  }

  void _paintStamp(Canvas canvas, Size size, Offset normPos, String stampId, Color color) {
     IconData icon;
     switch(stampId) {
       case 'coda': icon = Icons.music_note; break; 
       case 'segno': icon = Icons.repeat; break;
       case 'warning': icon = Icons.warning_amber_rounded; break;
       default: icon = Icons.star;
     }

     final painter = TextPainter(
       text: TextSpan(
         text: String.fromCharCode(icon.codePoint),
         style: TextStyle(
           color: color, 
           fontSize: 32, 
           fontFamily: icon.fontFamily,
           package: icon.fontPackage,
         ),
       ),
       textDirection: TextDirection.ltr,
     );
     painter.layout();
     
     final x = (normPos.dx * size.width) - (painter.width / 2);
     final y = (normPos.dy * size.height) - (painter.height / 2);
     painter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return oldDelegate.strokes != strokes || 
           oldDelegate.draftPoints != draftPoints;
  }
}
