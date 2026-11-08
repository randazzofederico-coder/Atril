import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'annotation_layer.dart';
import '../../models/annotation_stroke.dart';
import '../../data/app_data.dart';
import '../../models/score.dart';
import '../../models/setlist.dart';

/// Modo Vivo: reproducción de un setlist en escena.
///
/// Usa el mismo motor que el lector (pdfrx), así que las anotaciones se
/// dibujan pegadas a cada página, escalan con el zoom y se invierten junto
/// con el PDF.
///
/// Controles:
/// - Tap en la partitura: muestra/oculta el HUD.
/// - Botones: tema anterior/siguiente y página anterior/siguiente.
/// - Teclado o pedal Bluetooth: →, ↓, PageDown, Espacio = avanzar;
///   ←, ↑, PageUp = retroceder. Avanzar en la última página pasa al tema
///   siguiente; retroceder en la primera vuelve al tema anterior.
class LiveSetlistScreen extends StatefulWidget {
  final Setlist setlist;

  /// Tema con el que arranca (0 = primero).
  final int initialIndex;

  const LiveSetlistScreen({
    super.key,
    required this.setlist,
    this.initialIndex = 0,
  });

  @override
  State<LiveSetlistScreen> createState() => _LiveSetlistScreenState();
}

class _LiveSetlistScreenState extends State<LiveSetlistScreen> {
  late final List<Score> _scores;
  int _scoreIndex = 0;

  PdfViewerController? _controller;

  /// Se incrementa en cada apertura: fuerza un visor nuevo (también si el
  /// mismo tema aparece dos veces seguidas).
  int _viewerGen = 0;
  int _currentPage = 1;
  int _pagesCount = 0;

  bool _hudVisible = true;
  final FocusNode _focusNode = FocusNode(debugLabel: 'live_keys');

  static const _invertMatrix = ColorFilter.matrix([
    -1,  0,  0, 0, 255,
     0, -1,  0, 0, 255,
     0,  0, -1, 0, 255,
     0,  0,  0, 1,   0,
  ]);

  @override
  void initState() {
    super.initState();
    // En escena: pantalla siempre encendida y modo inmersivo.
    AppData.settings.acquireScreenOn();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scores = AppData.materializeSetlist(widget.setlist);
    if (_scores.isNotEmpty) {
      _openScoreAt(widget.initialIndex);
    }
  }

  @override
  void dispose() {
    AppData.settings.releaseScreenOn();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _focusNode.dispose();
    super.dispose();
  }

  // --- REPRODUCCIÓN (PLAYLIST) ---

  Score? get _score => (_scores.isEmpty) ? null : _scores[_scoreIndex];

  void _openScoreAt(int newIndex) {
    if (_scores.isEmpty) return;
    newIndex = newIndex.clamp(0, _scores.length - 1);

    // Controller nuevo en el mismo frame que la key nueva: sin pantallas
    // intermedias. Siempre arranca en la página 1.
    setState(() {
      _scoreIndex = newIndex;
      _pagesCount = 0;
      _currentPage = 1;
      _viewerGen++;
      _controller = PdfViewerController();
      _hudVisible = true;
    });
  }

  // --- NAVEGACIÓN ---

  bool get _canGoPrevScore => _scores.isNotEmpty && _scoreIndex > 0;
  bool get _canGoNextScore => _scores.isNotEmpty && _scoreIndex < _scores.length - 1;

  void _goPrevScore() {
    if (_canGoPrevScore) _openScoreAt(_scoreIndex - 1);
  }

  void _goNextScore() {
    if (_canGoNextScore) _openScoreAt(_scoreIndex + 1);
  }

  bool get _controllerReady => _controller?.isReady ?? false;

  void _goPrevPage() {
    if (!_controllerReady) return;
    if (_currentPage > 1) {
      _controller!.goToPage(pageNumber: _currentPage - 1, anchor: PdfPageAnchor.top);
    }
  }

  void _goNextPage() {
    if (!_controllerReady) return;
    if (_pagesCount == 0 || _currentPage < _pagesCount) {
      _controller!.goToPage(pageNumber: _currentPage + 1, anchor: PdfPageAnchor.top);
    }
  }

  /// Pedal / teclado: al pasar el final o el principio cambia de tema.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final forward = key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space;
    final backward = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp;
    if (!forward && !backward) return KeyEventResult.ignored;

    if (forward) {
      if (_pagesCount > 0 && _currentPage >= _pagesCount) {
        _goNextScore();
      } else {
        _goNextPage();
      }
    } else {
      if (_currentPage <= 1) {
        _goPrevScore();
      } else {
        _goPrevPage();
      }
    }
    return KeyEventResult.handled;
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final controller = _controller;

    return ValueListenableBuilder<bool>(
      valueListenable: AppData.settings.invertPdfColors,
      builder: (context, invertPdf, _) {
        final bg = invertPdf ? const Color(0xFF050505) : const Color(0xFFFAFAFA);

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Scaffold(
            backgroundColor: bg,
            extendBodyBehindAppBar: true, // Para que la AppBar flote sobre el PDF sin moverlo
            appBar: _hudVisible ? _buildAppBar(score) : null,
            body: SafeArea(
              top: false, // Permitir que el PDF suba detrás del AppBar
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. CONTENIDO PRINCIPAL
                  if (_scores.isEmpty)
                    _EmptyLiveState(setlistName: widget.setlist.name)
                  else if (score == null || score.filePath == null || score.filePath!.isEmpty)
                    _MissingFileState(
                      title: score?.title ?? 'Archivo',
                      subtitle: 'No hay ruta de PDF para este tema.',
                    )
                  else if (controller != null)
                    _buildViewer(score, controller, invertPdf, bg),

                  // Tap para mostrar/ocultar el HUD (deja pasar el scroll)
                  if (_scores.isNotEmpty)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() => _hudVisible = !_hudVisible),
                        child: const SizedBox.expand(),
                      ),
                    ),

                  // 2. CONTROLES DE NAVEGACIÓN (FABs)
                  if (_hudVisible && _scores.isNotEmpty) _buildControls(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(Score? score) {
    return AppBar(
      backgroundColor: Colors.black.withValues(alpha: 0.7),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Column(
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
    );
  }

  Widget _buildViewer(Score score, PdfViewerController controller, bool invertPdf, Color bg) {
    final viewer = PdfViewer.file(
      score.filePath!,
      key: ValueKey('${score.docId}_$_viewerGen'),
      controller: controller,
      params: PdfViewerParams(
        backgroundColor: invertPdf ? Colors.white : bg, // se invierte junto con el PDF
        scaleEnabled: true,
        // Scroll vertical continuo (igual que el lector)
        layoutPages: (pages, params) {
          final pageLayouts = <Rect>[];
          double y = params.margin;
          double maxWidth = 0;
          for (final page in pages) {
            maxWidth = math.max(maxWidth, page.width);
          }
          for (final page in pages) {
            pageLayouts.add(Rect.fromLTWH(
              params.margin + (maxWidth - page.width) / 2, // centradas
              y,
              page.width,
              page.height,
            ));
            y += page.height + params.margin;
          }
          return PdfPageLayout(
            pageLayouts: pageLayouts,
            documentSize: Size(maxWidth + params.margin * 2, y),
          );
        },
        // Anotaciones (solo lectura) pegadas a cada página
        pageOverlaysBuilder: (context, pageRect, page) => [
          AnnotationLayer(
            key: ValueKey('${score.docId}_${page.pageNumber}'),
            docId: score.docId,
            pageIndex: page.pageNumber,
            editable: false,
            tool: AnnotationTool.pen,
            width: 3.0,
            color: Colors.black,
            ignorePointers: true,
            pageSize: Size(page.width, page.height),
          ),
        ],
        onDocumentChanged: (doc) {
          if (mounted) setState(() => _pagesCount = doc?.pages.length ?? 0);
        },
        onPageChanged: (pageNumber) {
          if (pageNumber != null && pageNumber != _currentPage && mounted) {
            setState(() => _currentPage = pageNumber);
          }
        },
      ),
    );

    // Anotaciones dentro del filtro: con colores invertidos se invierten
    // junto con la partitura.
    return invertPdf ? ColorFiltered(colorFilter: _invertMatrix, child: viewer) : viewer;
  }

  Widget _buildControls() {
    final enabledBg = Colors.grey[200];
    final disabledBg = Colors.grey[700];
    return Positioned(
      bottom: 16,
      right: 16,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'prevScore',
              onPressed: _canGoPrevScore ? _goPrevScore : null,
              backgroundColor: _canGoPrevScore ? enabledBg : disabledBg,
              foregroundColor: _canGoPrevScore ? Colors.black : Colors.white54,
              tooltip: 'Tema Anterior',
              child: const Icon(Icons.skip_previous),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'nextScore',
              onPressed: _canGoNextScore ? _goNextScore : null,
              backgroundColor: _canGoNextScore ? enabledBg : disabledBg,
              foregroundColor: _canGoNextScore ? Colors.black : Colors.white54,
              tooltip: 'Siguiente Tema',
              child: const Icon(Icons.skip_next),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'prevPage',
              onPressed: _goPrevPage,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              tooltip: 'Página Anterior',
              child: const Icon(Icons.keyboard_arrow_up),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'nextPage',
              onPressed: _goNextPage,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              tooltip: 'Siguiente Página',
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
      ),
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
          style: const TextStyle(color: Colors.grey, fontSize: 16), // legible en fondo claro u oscuro
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
              style: const TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
