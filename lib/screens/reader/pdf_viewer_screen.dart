import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'annotation_layer.dart';
import 'annotation_toolbar.dart';
import '../../models/annotation_stroke.dart';
import '../../models/score.dart';
import '../../data/app_data.dart';

class PdfViewerScreen extends StatefulWidget {
  final List<Score> sourceScores;
  final int initialIndex;

  const PdfViewerScreen({
    super.key,
    required this.sourceScores,
    required this.initialIndex,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _currentIndex;
  PdfViewerController? _controller;
  final AnnotationLayerController _annotationController = AnnotationLayerController();

  // UI State
  bool _chromeVisible = true;
  bool _editMode = false;
  AnnotationTool _tool = AnnotationTool.pen;
  
  // Page Indicator state
  int _currentPage = 1;
  int _totalPages = 0;
  bool _pageHintVisible = false;
  Timer? _pageHintTimer;

  // Navigation helpers
  bool get _canGoNextDoc => _currentIndex < widget.sourceScores.length - 1;
  bool get _canGoPrevDoc => _currentIndex > 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _openScore(_currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  void dispose() {
    _pageHintTimer?.cancel();
    // _controller?.dispose(); // Not required/available in pdfrx
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // --- Logic ---

  Score get _currentScore => widget.sourceScores[_currentIndex];

  void _openScore(int index) {
      if (index < 0 || index >= widget.sourceScores.length) return;
      
      // Cleanup old controller to ensure fresh state (zoom, etc)
      // final oldCtrl = _controller; // Unused
      setState(() {
         _currentIndex = index;
         _currentPage = 1;
         _totalPages = 0;
         _controller = null; // Unmount current viewer
      });

      // Post-frame to create new controller and mount new viewer
      WidgetsBinding.instance.addPostFrameCallback((_) {
          // oldCtrl?.dispose(); // Not required in pdfrx
          if (mounted) {
             setState(() => _controller = PdfViewerController());
          }
      });
  }

  void _goNextDoc() => _openScore(_currentIndex + 1);
  void _goPrevDoc() => _openScore(_currentIndex - 1);

  void _goNextPage() {
    if (_controller != null && _currentPage < _totalPages) {
       _controller!.goToPage(pageNumber: _currentPage + 1);
    }
  }

  void _goPrevPage() {
    if (_controller != null && _currentPage > 1) {
       _controller!.goToPage(pageNumber: _currentPage - 1);
    }
  }

  // --- UI Helpers ---

  void _setChromeVisible(bool visible) {
    if (_editMode) visible = true; // Force visible in edit mode
    if (_chromeVisible == visible) return;
    setState(() => _chromeVisible = visible);
  }

  void _toggleChrome() => _setChromeVisible(!_chromeVisible);

  void _showPageHint() {
    if (!_pageHintVisible) setState(() => _pageHintVisible = true);
    _pageHintTimer?.cancel();
    _pageHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pageHintVisible = false);
    });
  }

  Future<void> _toggleEditMode() async {
    setState(() => _editMode = !_editMode);
    if (_editMode) {
      _setChromeVisible(true);
    }
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
        await _annotationController.clearPage(_currentScore.docId, _currentPage, null);
      }
  }

  double get _toolWidth {
    if (_tool == AnnotationTool.highlighter) return 14.0;
    if (_tool == AnnotationTool.whiteout) return 10.0;
    return 3.0; 
  }

  @override
  Widget build(BuildContext context) {
    // When switching docs, _controller is null briefly
    if (_controller == null) {
       return const Scaffold(
         backgroundColor: Colors.black,
         body: Center(child: CircularProgressIndicator(color: Colors.white)),
       );
    }

    final score = _currentScore;
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final topBarBaseHeight = topPadding + kToolbarHeight;
    final toolsHeight = _editMode ? 64.0 : 0.0;
    final topBarTotalHeight = topBarBaseHeight + toolsHeight;
    final safeBottom = math.max(MediaQuery.of(context).padding.bottom, MediaQuery.of(context).viewPadding.bottom);

    return ValueListenableBuilder<bool>(
      valueListenable: AppData.settings.invertPdfColors,
      builder: (context, invertPdf, _) {
        return Scaffold(
          backgroundColor: Colors.black, // Drive-like background
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. PDF Viewer with Overlay
              ColorFiltered(
                  colorFilter: AppData.settings.invertPdfColors.value 
                      ? const ColorFilter.matrix([
                          -1,  0,  0, 0, 255,
                           0, -1,  0, 0, 255,
                           0,  0, -1, 0, 255,
                           0,  0,  0, 1,   0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: PdfViewer.file(
                  score.filePath ?? '',
                  key: ValueKey(score.docId), // NEW VIEWER ON DOC CHANGE
                  controller: _controller,
                  params: PdfViewerParams(
                     panEnabled: !_editMode, // Disable navigation in edit mode
                     scaleEnabled: true,
                     // Continuous vertical scroll
                     layoutPages: (pages, params) {
                        final pageLayouts = <Rect>[];
                        double y = params.margin;
                        double maxWidth = 0;
                        for (final page in pages) {
                          pageLayouts.add(
                            Rect.fromLTWH(
                              params.margin, 
                              y, 
                              page.width, 
                              page.height
                            )
                          );
                          y += page.height + params.margin; // Vertical spacing
                          maxWidth = math.max(maxWidth, page.width);
                        }
                        
                        return PdfPageLayout(
                          pageLayouts: pageLayouts, 
                          documentSize: Size(
                             maxWidth + params.margin * 2,
                             y // Total height
                          ),
                        );
                     },
                     // Render annotation layer ON TOP of each page
                     pageOverlaysBuilder: (context, pageRect, page) {
                        final pageNumber = page.pageNumber;
                        return [
                          AnnotationLayer(
                            key: ValueKey('${score.docId}_$pageNumber'),
                            controller: _annotationController,
                            docId: score.docId,
                            pageIndex: pageNumber,
                            editable: _editMode,
                            tool: _tool,
                            width: _toolWidth,
                            ignorePointers: !_editMode, // Pass-through gestures if not editing
                          )
                        ];
                     },
                     // Handle document load
                     onDocumentChanged: (doc) {
                        if (mounted) setState(() => _totalPages = doc?.pages.length ?? 0);
                     },
                     // Handle page change (updates scroll/hint)
                     onPageChanged: (pageNumber) {
                        if (pageNumber != null && pageNumber != _currentPage) {
                           if (mounted) setState(() => _currentPage = pageNumber);
                           _showPageHint();
                        }
                     },
                  ),
                ),
              ),

              // Wrapper to capture tap for chrome toggle
              if (!_editMode)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent, // Allow scroll through
                    onTap: _toggleChrome,
                    onDoubleTap: () {}, // Let viewer handle double tap zoom?
                    child: Container(), // Transparent layer
                  ),
                ),

              // 2. Page Hint
              Positioned(
                left: 12,
                bottom: 12 + safeBottom,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: _pageHintVisible ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                         color: Colors.black.withValues(alpha: 0.7),
                         borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_currentPage / $_totalPages',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
              
              // 3. Navigation FABs (Bottom Right)
              if (_chromeVisible && !_editMode)
                  Positioned(
                    right: 16,
                    bottom: 16 + safeBottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         // Doc Nav
                         Padding(
                           padding: const EdgeInsets.only(bottom: 8),
                           child: FloatingActionButton.small(
                             heroTag: 'prevDoc',
                             onPressed: _canGoPrevDoc ? _goPrevDoc : null,
                             backgroundColor: _canGoPrevDoc ? Colors.grey[800] : Colors.grey[900],
                             foregroundColor: _canGoPrevDoc ? Colors.white : Colors.grey[600],
                             child: const Icon(Icons.skip_previous),
                           ),
                         ),
                         Padding(
                           padding: const EdgeInsets.only(bottom: 16),
                           child: FloatingActionButton.small(
                             heroTag: 'nextDoc',
                             onPressed: _canGoNextDoc ? _goNextDoc : null,
                             backgroundColor: _canGoNextDoc ? Colors.grey[800] : Colors.grey[900],
                             foregroundColor: _canGoNextDoc ? Colors.white : Colors.grey[600],
                             child: const Icon(Icons.skip_next),
                           ),
                         ),

                         // Page Nav (Visible if multi-page)
                         if (_totalPages > 1) ...[
                            FloatingActionButton(
                              heroTag: 'prevPage',
                              onPressed: _goPrevPage,
                              mini: true,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              child: const Icon(Icons.keyboard_arrow_up),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton(
                              heroTag: 'nextPage',
                              onPressed: _goNextPage,
                              mini: true,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              child: const Icon(Icons.keyboard_arrow_down),
                            ),
                         ],
                      ],
                    ),
                  ),

              // 4. Custom Top Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: 0, right: 0,
                top: _chromeVisible ? 0 : -topBarTotalHeight,
                child: Material(
                  color: Colors.black,
                  elevation: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // AppBar
                      SizedBox(
                        height: topBarBaseHeight,
                        child: Padding(
                          padding: EdgeInsets.only(top: topPadding),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      score.title,
                                      style: const TextStyle(color: Colors.white, fontSize: 18),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (widget.sourceScores.length > 1)
                                       Text(
                                         '${_currentIndex + 1} / ${widget.sourceScores.length}',
                                         style: const TextStyle(color: Colors.white70, fontSize: 12),
                                       ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _toggleEditMode,
                                icon: Icon(_editMode ? Icons.edit_off : Icons.edit, color: Colors.white),
                                tooltip: _editMode ? 'Salir' : 'Editar',
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tools
                      if (_editMode)
                        SizedBox(
                          height: toolsHeight,
                          child: AnnotationToolbar(
                            selectedTool: _tool,
                            onTypeChanged: (t) => setState(() => _tool = t),
                            onUndo: () => _annotationController.undo(),
                            onRedo: () => _annotationController.redo(),
                            onClear: _confirmClearPage,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
