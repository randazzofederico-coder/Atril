import 'dart:math' as math;
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
class AnnotationLayerController {
  _AnnotationLayerState? _state;

  Future<void> undo() async => _state?.undo() ?? Future.value();
  Future<void> redo() async => _state?.redo() ?? Future.value();
  Future<void> clearPage() async => _state?.clearPage() ?? Future.value();
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
  final List<AnnotationStroke> _redoStack = <AnnotationStroke>[];

  // stroke being drawn (normalized points)
  List<Offset>? _draftPoints;

  // pointer tracking to allow 2-finger pinch/zoom to reach the PDF viewer
  final Set<int> _activePointers = <int>{};
  bool _allowDrawing = true;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
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
    if (widget.controller?._state == this) {
      widget.controller!._state = null;
    }
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
      _redoStack.clear();
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

    await AppData.insertAnnotationStroke(stroke);
    if (!mounted) return;
    setState(() {
      _strokes.add(stroke);
      _redoStack.clear();
    });
  }

  Future<void> undo() async {
    if (_strokes.isEmpty) return;
    final last = _strokes.removeLast();
    _redoStack.add(last);
    setState(() {});
    await AppData.deleteAnnotationStroke(last.id);
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    final s = _redoStack.removeLast();
    setState(() => _strokes.add(s));
    await AppData.insertAnnotationStroke(s);
  }

  Future<void> clearPage() async {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.clear();
      _redoStack.clear();
      _draftPoints = null;
    });
    await AppData.deleteAnnotationStrokesForPage(
      docId: widget.docId,
      pageIndex: widget.pageIndex,
      setlistId: widget.setlistId,
    );
  }

  Offset _normalize(Offset local, Size size) {
    final dx = (local.dx / math.max(1.0, size.width)).clamp(0.0, 1.0);
    final dy = (local.dy / math.max(1.0, size.height)).clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

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
          ),
          size: Size.infinite,
        );

        if (displayOnly) {
          return IgnorePointer(child: painted);
        }

        // Editable: capture 1-finger pan to draw, but allow pinch/zoom (2 fingers)
        return Listener(
          onPointerDown: (e) {
            _activePointers.add(e.pointer);
            if (_activePointers.length > 1) {
              _allowDrawing = false;
              // cancel current draft if user starts a pinch
              if (_draftPoints != null) {
                setState(() => _draftPoints = null);
              }
            } else {
              _allowDrawing = true;
            }
          },
          onPointerUp: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.length <= 1) {
              _allowDrawing = true;
            }
          },
          onPointerCancel: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.length <= 1) {
              _allowDrawing = true;
            }
          },
          child: IgnorePointer(
            ignoring: !_allowDrawing,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                _draftPoints = <Offset>[_normalize(d.localPosition, size)];
                setState(() {});
              },
              onPanUpdate: (d) {
                final pts = _draftPoints;
                if (pts == null) return;
                pts.add(_normalize(d.localPosition, size));
                setState(() {});
              },
              onPanEnd: (_) async {
                final pts = _draftPoints;
                if (pts == null) return;
                setState(() => _draftPoints = null);
                await _commitStroke(List<Offset>.from(pts));
              },
              onPanCancel: () {
                setState(() => _draftPoints = null);
              },
              child: painted,
            ),
          ),
        );
      },
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset>? draftPoints;

  _AnnotationPainter({
    required this.strokes,
    required this.draftPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, size, s.tool, s.width, s.pointsNorm);
    }
    final dp = draftPoints;
    if (dp != null && dp.length >= 2) {
      _paintStroke(canvas, size, AnnotationTool.pen, 2.0, dp);
    }
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    AnnotationTool tool,
    double width,
    List<Offset> pointsNorm,
  ) {
    if (pointsNorm.length < 2) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // v1: fixed colors (can be made configurable later)
    switch (tool) {
      case AnnotationTool.pen:
        paint.color = Colors.redAccent;
        break;
      case AnnotationTool.highlighter:
        paint.color = Colors.yellow.withValues(alpha: 0.40);
        break;
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

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.draftPoints != draftPoints;
  }
}
