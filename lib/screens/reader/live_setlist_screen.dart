import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'annotation_layer.dart';
import '../../models/annotation_stroke.dart';
import '../../data/app_data.dart';
import '../../models/score.dart';
import '../../models/setlist.dart';


class LiveSetlistScreen extends StatefulWidget {
  final Setlist setlist;
  const LiveSetlistScreen({
    super.key,
    required this.setlist,
  });

  @override
  State<LiveSetlistScreen> createState() => _LiveSetlistScreenState();
}

class _LiveSetlistScreenState extends State<LiveSetlistScreen> {
  late final List<Score> _scores;
  int _scoreIndex = 0;
  
  // Controlador PDF
  PdfViewerController? _controller;
  int _currentPage = 1;
  int _pagesCount = 0;

  // UI State
  bool _hudVisible = true;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();
    _scores = AppData.materializeSetlist(widget.setlist);
    if (_scores.isNotEmpty) {
      _openScoreAt(0);
    }
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // --- LÓGICA DE REPRODUCCIÓN (PLAYLIST) ---

  Score? get _score => (_scores.isEmpty) ? null : _scores[_scoreIndex];

  void _showHudTemporarily() {
    if (!mounted) return;
    setState(() => _hudVisible = true);
    // User requested no timer auto-hide.
    // _hudTimer?.cancel();
    // _hudTimer = Timer(...)
  }

  Future<void> _openScoreAt(int newIndex) async {
    if (_scores.isEmpty) return;

    newIndex = newIndex.clamp(0, _scores.length - 1);
    
    // 1. Guardar estado del anterior
    // 1. Guardar estado del anterior
    // final prevScore = _score;
    // if (prevScore != null) {
    //   // AppData.setLastPageForDocId(prevScore.docId, _currentPage); // DISABLED PERSISTENCE
    // }

    final next = _scores[newIndex];
    final path = next.filePath;

    // 2. Limpieza técnica del PDF Controller (Workaround para evitar crash de pdfx)
    final oldController = _controller;
    setState(() {
      _scoreIndex = newIndex;
      _pagesCount = 0;
      _currentPage = 1; // Always start at 1
      _controller = null; 
    });
    
    _showHudTemporarily();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController?.dispose();
    });

    if (path == null || path.isEmpty) return;

    // 3. Crear nuevo controlador
    final ctrl = PdfViewerController();
    
    // Syncfusion no tiene initialPage en el constructor del controller,
    // se maneja en onDocumentLoaded.
    
    if (!mounted) {
      // ctrl.dispose(); // Syncfusion controller no siempre necesita dispose inmediato si no se usó, pero bueno.
      return;
    }

    setState(() {
      _controller = ctrl;
    });

    // 4. Cargar contador de páginas (cache)
    unawaited(() async {
      final count = await AppData.getPagesCountForPath(path);
      if (!mounted) return;
      setState(() => _pagesCount = count);
      
      // A2 FIX: Si abrimos un score nuevo (y no es persistencia), 
      // queremos asegurar que se vea desde arriba.
      // Syncfusion por defecto mantiene el zoom y scroll si es el "mismo" viewer,
      // pero aquí estamos recreando el viewer (key distinta), así que debería resetearse.
      // Sin embargo, si la persistencia dice pag 1, saltamos a 1 para asegurar.
      if (_currentPage == 1 && _controller != null) {
         _controller!.jumpToPage(1);
      }
    }());
  }

  // --- NAVEGACIÓN ---

  bool get _canGoPrevScore => _scores.isNotEmpty && _scoreIndex > 0;
  bool get _canGoNextScore => _scores.isNotEmpty && _scoreIndex < _scores.length - 1;

  Future<void> _goPrevScore() async {
    if (!_canGoPrevScore) return;
    await _openScoreAt(_scoreIndex - 1);
  }

  Future<void> _goNextScore() async {
    if (!_canGoNextScore) return;
    await _openScoreAt(_scoreIndex + 1);
  }

  void _goPrevPage() {
    final ctrl = _controller;
    if (ctrl == null) return;
    // _showHudTemporarily(); // REMOVED
    // A2 FIX: Force beginning of page (jump instead of animate if desired, or ensure clean transition)
    ctrl.previousPage();
  }

  void _goNextPage() {
    final ctrl = _controller;
    if (ctrl == null) return;
    // _showHudTemporarily(); // REMOVED
    ctrl.nextPage();
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final controller = _controller;
    
    // Key única por documento para forzar la reconstrucción limpia del viewer
    final pdfKey = ValueKey<String>(score?.docId ?? 'no-score');

    return ValueListenableBuilder<bool>(
      valueListenable: AppData.settings.invertPdfColors,
      builder: (context, invertPdf, _) {
        final bg = invertPdf ? const Color(0xFF050505) : const Color(0xFFFAFAFA);
        
        return Scaffold(
          backgroundColor: bg,
        extendBodyBehindAppBar: true, // Para que la AppBar flote sobre el PDF sin moverlo
        appBar: _hudVisible
            ? AppBar(
                backgroundColor: Colors.black.withValues(alpha: 0.7),
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            score?.title ?? 'Cargando...',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Pág $_currentPage / ${_pagesCount == 0 ? "?" : _pagesCount}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.setlist.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Tema ${_scoreIndex + 1} / ${_scores.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null, // Ocultar AppBar si _hudVisible es false
        body: SafeArea(
          top: false, // Permitir que el PDF suba detrás del AppBar
          child: Stack(
            children: [
              // 1. CONTENIDO PRINCIPAL
              if (_scores.isEmpty)
                _EmptyLiveState(setlistName: widget.setlist.name)
              else if (score == null || score.filePath == null || score.filePath!.isEmpty)
                _MissingFileState(
                  title: score?.title ?? 'Archivo',
                  subtitle: 'No hay ruta de PDF para este score.',
                )
              else if (controller == null)
                Theme(
                  data: invertPdf ? ThemeData.dark() : ThemeData.light(),
                  child: Container(
                     // Use calculated bg for consistency
                     color: bg,
                     child: const Center(child: CircularProgressIndicator()),
                  ),
                )
              else
                // AQUI ESTÁ EL REFACTOR: Usamos el Widget Delegado
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      // A. Visor PDF
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
                            File(score.filePath!),
                            key: pdfKey,
                            controller: controller,
                            canShowScrollHead: false, 
                            enableDoubleTapZooming: false,
                            onTap: (details) {
                            // Toggle HUD visibility on tap
                            setState(() => _hudVisible = !_hudVisible);
                          },
                          onDocumentLoaded: (details) {
                            setState(() => _pagesCount = controller.pageCount);
                            // Always start at 1
                            /*if (_currentPage > 1) {
                              controller.jumpToPage(_currentPage);
                            }*/
                            _showHudTemporarily(); // Show initially when loading a NEW score
                          },
                          onPageChanged: (details) {
                            setState(() => _currentPage = details.newPageNumber);
                            // Persistence removed
                            // _showHudTemporarily(); // REMOVED: Do not auto-show on page change
                          },
                        ),
                      ),
                    ),
                      
                      // B. Capa de Anotaciones (Solo lectura en vivo)
                      Positioned.fill(
                        child: AnnotationLayer(
                          key: ValueKey('${_score?.docId ?? 'no_doc'}_$_currentPage'),
                          docId: _score?.docId ?? '',
                          pageIndex: _currentPage,
                          editable: false,
                          tool: AnnotationTool.pen,
                          width: 3.0,
                          ignorePointers: true, // Deja pasar los toques
                        ),
                      ),
                    ],
                  ),
  
              // 3. CONTROLES DE NAVEGACIÓN (FABs) - Bottom Right Column
              if (_hudVisible)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. PREV DOC
                        FloatingActionButton.small(
                          heroTag: 'prevScore',
                          onPressed: _canGoPrevScore ? _goPrevScore : null,
                          backgroundColor: _canGoPrevScore ? Colors.grey[200] : Colors.grey[800],
                          foregroundColor: Colors.black,
                          tooltip: 'Tema Anterior',
                          child: const Icon(Icons.skip_previous),
                        ),
                        const SizedBox(height: 12),
  
                        // 2. NEXT DOC
                        FloatingActionButton.small(
                          heroTag: 'nextScore',
                          onPressed: _canGoNextScore ? _goNextScore : null,
                          backgroundColor: _canGoNextScore ? Colors.grey[200] : Colors.grey[800],
                          foregroundColor: Colors.black,
                          tooltip: 'Siguiente Tema',
                          child: const Icon(Icons.skip_next),
                        ),
                        const SizedBox(height: 12),
                        
                        // 3. PREV PAGE
                        FloatingActionButton(
                          heroTag: 'prevPage',
                          onPressed: _goPrevPage,
                           // Can always try to go prev (viewer handles boundary)
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          tooltip: 'Página Anterior',
                          child: const Icon(Icons.keyboard_arrow_up),
                        ),
                        const SizedBox(height: 12),
  
                        // 4. NEXT PAGE
                        FloatingActionButton(
                          heroTag: 'nextPage',
                          onPressed: _goNextPage,
                          // Can always try to go next
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          tooltip: 'Siguiente Página',
                          child: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
     },
    );
  }
}


class _EmptyLiveState extends StatelessWidget {
  final String setlistName;
  const _EmptyLiveState({required this.setlistName});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '“$setlistName” no tiene temas para reproducir en vivo.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }
}

class _MissingFileState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _MissingFileState({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
