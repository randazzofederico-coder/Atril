import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'annotation_layer.dart';
import '../../models/annotation_stroke.dart';
import '../../data/app_data.dart';

class PdfViewerScreen extends StatefulWidget {
  final String docId;
  final String title;
  final String filePath;

  const PdfViewerScreen({
    super.key,
    required this.docId,
    required this.title,
    required this.filePath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfViewerController _controller;

  int _currentPage = 1;
  int _pagesCount = 0;

  // Stabilized chrome state: only controls app UI (top bar + FAB).
  bool _chromeVisible = true;

  final AnnotationLayerController _annotationController = AnnotationLayerController();

  bool _editMode = false;
  AnnotationTool _tool = AnnotationTool.pen;

  double get _toolWidth => _tool == AnnotationTool.highlighter ? 14.0 : 3.0;

  bool _pageHintVisible = false;
  Timer? _pageHintTimer;

  final Set<int> _activePointers = <int>{};

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();

    // Stabilizer: Never hide Android system UI. Keep edge-to-edge always.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  void dispose() {
    _pageHintTimer?.cancel();
    _controller.dispose();

    // Restore edge-to-edge (no immersive used, but keep consistent).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  void _setChromeVisible(bool visible) {
    if (_editMode) visible = true;
    if (_chromeVisible == visible) return;
    setState(() => _chromeVisible = visible);
  }

  void _toggleChrome() => _setChromeVisible(!_chromeVisible);

  void _showPageHint() {
    if (!_pageHintVisible) {
      setState(() => _pageHintVisible = true);
    }
    _pageHintTimer?.cancel();
    _pageHintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _pageHintVisible = false);
    });
  }

  Future<void> _confirmClearPage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar anotaciones de esta página'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _annotationController.clearPage();
    }
  }

  Future<void> _toggleEditMode() async {
    setState(() => _editMode = !_editMode);

    // Rule: edit mode locks chrome visible
    if (_editMode) {
      _setChromeVisible(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final safeBottom = math.max(mq.padding.bottom, mq.viewPadding.bottom);

    final topBarBaseHeight = topPadding + kToolbarHeight;
    final toolsHeight = _editMode ? 56.0 : 0.0;
    final topBarHeight = topBarBaseHeight + toolsHeight;

    return ValueListenableBuilder<bool>(
      valueListenable: AppData.settings.invertPdfColors,
      builder: (context, invertPdf, _) {
        final bg = invertPdf ? const Color(0xFF050505) : const Color(0xFFFAFAFA);
        
        return Scaffold(
          backgroundColor: bg,

          // FAB: visible only when app chrome is visible.
          floatingActionButton: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            opacity: (_chromeVisible) ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Padding(
                padding: EdgeInsets.only(bottom: safeBottom),
                child: FloatingActionButton.small(
                  heroTag: 'editFab',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  onPressed: _toggleEditMode,
                  child: Icon(_editMode ? Icons.edit_off : Icons.edit),
                ),
              ),
            ),
          ),

          body: Listener(
            onPointerDown: (e) {
              _activePointers.add(e.pointer);
              _showPageHint();

              // Optional Drive-like behavior: pinch hides app chrome.
              if (_activePointers.length >= 2 && !_editMode) {
                _setChromeVisible(false);
              }
            },
            onPointerUp: (e) {
              _activePointers.remove(e.pointer);
              _showPageHint();
            },
            onPointerCancel: (e) {
              _activePointers.remove(e.pointer);
              _showPageHint();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_editMode) return;
                _toggleChrome();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // AQUI ESTÁ EL REFACTOR: Usamos el Widget Delegado
                  ColorFiltered(
                    colorFilter: AppData.settings.invertPdfColors.value 
                      ? const ColorFilter.matrix([
                          -1,  0,  0, 0, 255,
                           0, -1,  0, 0, 255,
                           0,  0, -1, 0, 255,
                           0,  0,  0, 1,   0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                    child: Theme(
                      data: ThemeData.light().copyWith(
                        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
                        canvasColor: const Color(0xFFFAFAFA),
                      ),
                      child: SfPdfViewer.file(
                        File(widget.filePath),
                        controller: _controller,
                      canShowScrollHead: true,
                      canShowScrollStatus: true,
                      onDocumentLoaded: (details) {
                        setState(() {
                          _pagesCount = _controller.pageCount;
                          _currentPage = _controller.pageNumber;
                        });
                        _showPageHint();
                      },
                      onPageChanged: (details) {
                        setState(() => _currentPage = details.newPageNumber);
                        _showPageHint();
                      },
                      onZoomLevelChanged: (details) {
                        // Drive-like behavior: pinch hides app chrome (view mode only).
                        if (!_editMode && details.newZoomLevel != details.oldZoomLevel) {
                          _setChromeVisible(false);
                        }
                      },
                    ),
                  ),
                ),

                  // Page indicator bottom-left (safe)
                  Positioned(
                    left: 12,
                    bottom: 12 + safeBottom,
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        opacity: _pageHintVisible ? 1 : 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_currentPage / $_pagesCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Annotation overlay
                  Positioned.fill(
                    child: AnnotationLayer(
                      key: ValueKey('${widget.docId}_$_currentPage'),
                      controller: _annotationController,
                      docId: widget.docId,
                      pageIndex: _currentPage,
                      editable: _editMode,
                      tool: _tool,
                      width: _toolWidth,
                      ignorePointers: !_editMode,
                    ),
                  ),

                  // OPAQUE top bar that slides in/out
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: _chromeVisible ? 0 : -topBarHeight,
                    child: _TopBarWithEdit(
                      height: topBarHeight,
                      topPadding: topPadding,
                      title: widget.title,
                      editMode: _editMode,
                      tool: _tool,
                      onBack: () => Navigator.of(context).maybePop(),
                      onToggleEdit: _toggleEditMode,
                      onSelectTool: (t) => setState(() => _tool = t),
                      onUndo: () => _annotationController.undo(),
                      onRedo: () => _annotationController.redo(),
                      onClearPage: _confirmClearPage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBarWithEdit extends StatelessWidget {
  final double height;
  final double topPadding;

  final String title;
  final bool editMode;
  final AnnotationTool tool;

  final VoidCallback onBack;
  final VoidCallback onToggleEdit;
  final ValueChanged<AnnotationTool> onSelectTool;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClearPage;

  const _TopBarWithEdit({
    required this.height,
    required this.topPadding,
    required this.title,
    required this.editMode,
    required this.tool,
    required this.onBack,
    required this.onToggleEdit,
    required this.onSelectTool,
    required this.onUndo,
    required this.onRedo,
    required this.onClearPage,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black, // opaque
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Atrás',
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleEdit,
                      tooltip: editMode ? 'Salir de edición' : 'Editar',
                      icon: Icon(editMode ? Icons.edit_off : Icons.edit, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            if (editMode)
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Lapicera',
                      onPressed: () => onSelectTool(AnnotationTool.pen),
                      icon: Icon(
                        Icons.gesture,
                        color: tool == AnnotationTool.pen ? Colors.white : Colors.white54,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Resaltador',
                      onPressed: () => onSelectTool(AnnotationTool.highlighter),
                      icon: Icon(
                        Icons.highlight,
                        color: tool == AnnotationTool.highlighter ? Colors.white : Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Deshacer',
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Rehacer',
                      onPressed: onRedo,
                      icon: const Icon(Icons.redo, color: Colors.white),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Borrar página',
                      onPressed: onClearPage,
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
