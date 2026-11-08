import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

part 'image_edit_processing.dart';

part 'image_edit_painters.dart';

/// Holds all edit parameters so they can be restored when re-editing.
class ImageEditParams {
  final int rotation;
  final bool grayscale;
  final double threshold;
  final double brightness;
  final double contrast;
  // Perspective crop: 4 independent corners, normalized 0..1
  final Offset cropTL, cropTR, cropBL, cropBR;

  const ImageEditParams({
    this.rotation = 0,
    this.grayscale = false,
    this.threshold = 128.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.cropTL = const Offset(0, 0),
    this.cropTR = const Offset(1, 0),
    this.cropBL = const Offset(0, 1),
    this.cropBR = const Offset(1, 1),
  });

  bool get isDefault =>
      rotation == 0 && !grayscale && threshold == 128.0 &&
      brightness == 0.0 && contrast == 0.0 &&
      cropTL == const Offset(0, 0) && cropTR == const Offset(1, 0) &&
      cropBL == const Offset(0, 1) && cropBR == const Offset(1, 1);
}

/// Result returned by the editor.
///
/// For perspective warps, the editor returns immediately with the original
/// image path and sets [needsBackgroundProcessing] = true. The caller can
/// invoke [backgroundProcessor] to run the heavy Isolate work without
/// blocking the editor UI.
class ImageEditResult {
  final String editedPath;
  final ImageEditParams params;

  /// If true, [editedPath] is a temporary/original path and the real
  /// processed image will be produced by [backgroundProcessor].
  final bool needsBackgroundProcessing;

  /// Callback that runs the heavy perspective warp in an Isolate.
  /// Accepts an optional [onProgress] callback (0.0–1.0) for UI updates.
  /// Returns the final processed image path.
  final Future<String> Function(void Function(double progress) onProgress)? backgroundProcessor;

  const ImageEditResult(
    this.editedPath,
    this.params, {
    this.needsBackgroundProcessing = false,
    this.backgroundProcessor,
  });
}

/// Image editor with Rotate, B/W, Brightness/Contrast, and Perspective Crop tools.
class ImageEditScreen extends StatefulWidget {
  final String imagePath;
  final ImageEditParams? initialParams;

  const ImageEditScreen({
    super.key,
    required this.imagePath,
    this.initialParams,
  });

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

enum _EditTool { rotate, bw, brightness, crop }

class _ImageEditScreenState extends State<ImageEditScreen> {
  late int _rotation;
  late bool _grayscale;
  late double _threshold;
  late double _brightness;
  late double _contrast;

  // Perspective crop: 4 corners normalized 0..1
  late Offset _cropTL;
  late Offset _cropTR;
  late Offset _cropBL;
  late Offset _cropBR;

  _EditTool _activeTool = _EditTool.rotate;
  bool _isProcessing = false;

  // Original loaded image (never mutated)
  ui.Image? _loadedImage;
  bool _imageLoading = true;

  // Pre-rendered B/W preview (software-rendered, no GPU precision issues)
  ui.Image? _bwPreviewImage;
  bool _bwPreviewDirty = true;

  @override
  void initState() {
    super.initState();
    final p = widget.initialParams ?? const ImageEditParams();
    _rotation = p.rotation;
    _grayscale = p.grayscale;
    _threshold = p.threshold;
    _brightness = p.brightness;
    _contrast = p.contrast;
    _cropTL = p.cropTL;
    _cropTR = p.cropTR;
    _cropBL = p.cropBL;
    _cropBR = p.cropBR;

    _loadImage();
  }

  void _resetAll() {
    setState(() {
      _rotation = 0;
      _grayscale = false;
      _threshold = 128.0;
      _brightness = 0.0;
      _contrast = 0.0;
      _cropTL = const Offset(0, 0);
      _cropTR = const Offset(1, 0);
      _cropBL = const Offset(0, 1);
      _cropBR = const Offset(1, 1);
      _bwPreviewDirty = true;
    });
    _rebuildBWPreviewIfNeeded();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _loadedImage = frame.image;
        _imageLoading = false;
        _bwPreviewDirty = true;
      });
      _rebuildBWPreviewIfNeeded();
    }
  }

  ImageEditParams get _currentParams => ImageEditParams(
        rotation: _rotation,
        grayscale: _grayscale,
        threshold: _threshold,
        brightness: _brightness,
        contrast: _contrast,
        cropTL: _cropTL,
        cropTR: _cropTR,
        cropBL: _cropBL,
        cropBR: _cropBR,
      );

  // --- B/W preview rendering (software path, avoids GPU fp16 precision issues) ---

  Future<void> _rebuildBWPreviewIfNeeded() async {
    if (!_bwPreviewDirty || !_grayscale) return;
    final srcImg = _loadedImage;
    if (srcImg == null) return;

    _bwPreviewDirty = false;

    // Apply color matrix (grayscale + threshold) via software path
    List<double> bwMatrix = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    const rx = 0.2126;
    const gx = 0.7152;
    const bx = 0.0722;
    bwMatrix = _multiplyMatrix(bwMatrix, [
      rx, gx, bx, 0, 0,
      rx, gx, bx, 0, 0,
      rx, gx, bx, 0, 0,
      0, 0, 0, 1, 0,
    ]);

    const thresholdScale = 50.0;
    final t = _threshold / 255.0;
    final offset = (-t * thresholdScale + 0.5) * 255.0;
    bwMatrix = _multiplyMatrix(bwMatrix, [
      thresholdScale, 0, 0, 0, offset,
      0, thresholdScale, 0, 0, offset,
      0, 0, thresholdScale, 0, offset,
      0, 0, 0, 1, 0,
    ]);

    final recorder = ui.PictureRecorder();
    final w = srcImg.width.toDouble();
    final h = srcImg.height.toDouble();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    final paint = Paint()..colorFilter = ColorFilter.matrix(bwMatrix);
    canvas.drawImage(srcImg, Offset.zero, paint);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(srcImg.width, srcImg.height);

    if (mounted) {
      setState(() => _bwPreviewImage = rendered);
    }
  }

  static List<double> _multiplyMatrix(List<double> a, List<double> b) {
    final result = List<double>.filled(20, 0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 5; col++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) sum += a[row * 5 + 4];
        result[row * 5 + col] = sum;
      }
    }
    return result;
  }

  // --- Process and Confirm ---

  Future<void> _confirmEdit() async {
    final uiImg = _loadedImage;
    if (uiImg == null) return;

    final bool needsPerspective = !_isRectCrop && !_isFullCrop;

    if (needsPerspective) {
      // Perspective warp: return immediately, process in background.
      // We pass the original image path as a placeholder; the caller
      // will invoke backgroundProcessor() to get the real output.
      final params = _currentParams;
      final sourcePath = widget.imagePath;
      final srcW = uiImg.width;
      final srcH = uiImg.height;

      Navigator.of(context).pop(ImageEditResult(
        sourcePath, // placeholder — will be replaced after bg processing
        params,
        needsBackgroundProcessing: true,
        backgroundProcessor: (onProgress) => _runPerspectiveInBackground(
          sourcePath: sourcePath,
          srcW: srcW,
          srcH: srcH,
          params: params,
          onProgress: onProgress,
        ),
      ));
    } else {
      // Rect crop: fast path, process inline.
      setState(() => _isProcessing = true);
      try {
        final editedPath = await _renderRectCrop(uiImg);
        if (mounted) {
          Navigator.of(context).pop(ImageEditResult(editedPath, _currentParams));
        }
      } catch (e, stack) {
        debugPrint('Error procesando imagen: $e\n$stack');
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  bool get _isRectCrop =>
      _cropTL.dx == _cropBL.dx && _cropTR.dx == _cropBR.dx &&
      _cropTL.dy == _cropTR.dy && _cropBL.dy == _cropBR.dy;

  bool get _isFullCrop =>
      _cropTL == const Offset(0, 0) && _cropTR == const Offset(1, 0) &&
      _cropBL == const Offset(0, 1) && _cropBR == const Offset(1, 1);

  /// Runs the perspective warp in a background Isolate.
  /// This is a static-compatible helper so it can be called after the
  /// editor screen has already been popped.
  static Future<String> _runPerspectiveInBackground({
    required String sourcePath,
    required int srcW,
    required int srcH,
    required ImageEditParams params,
    required void Function(double progress) onProgress,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempPath = '${tempDir.path}/atril_edit_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final isolateParams = _PerspectiveProcessParams(
      sourcePath: sourcePath,
      tempPath: tempPath,
      srcW: srcW,
      srcH: srcH,
      rotation: params.rotation,
      grayscale: params.grayscale,
      threshold: params.threshold,
      brightness: params.brightness,
      contrast: params.contrast,
      cropTL: params.cropTL, cropTR: params.cropTR,
      cropBL: params.cropBL, cropBR: params.cropBR,
    );

    // Use Isolate.spawn + ReceivePort so we can get progress updates
    // from the pixel warp loop in real time.
    final receivePort = ReceivePort();
    final completer = Completer<String>();

    // onError/onExit: si el isolate muere (p. ej. sin memoria con fotos muy
    // grandes) el future termina con error en lugar de quedar colgado.
    await Isolate.spawn(
      _processPerspectiveWithProgress,
      _IsolateMessage(isolateParams, receivePort.sendPort),
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
    );

    receivePort.listen((message) {
      if (completer.isCompleted) return;
      if (message is double) {
        // Progress update (0.0 – 1.0)
        onProgress(message);
      } else if (message is String) {
        // Final result path
        completer.complete(message);
        receivePort.close();
      } else if (message is List) {
        // ['error', msg] propio, o [error, stack] de onError
        completer.completeError(Exception(message.length > 1 && message.first == 'error'
            ? message.last
            : message.first));
        receivePort.close();
      } else if (message == null) {
        // onExit sin resultado
        completer.completeError(Exception('El procesamiento de la imagen terminó inesperadamente.'));
        receivePort.close();
      }
    });

    return completer.future;
  }

  /// Fast path for simple rectangular crops using dart:ui (native/GPU).
  Future<String> _renderRectCrop(ui.Image sourceImg) async {
    final srcW = sourceImg.width;
    final srcH = sourceImg.height;
    final cropL = (_cropTL.dx * srcW).round();
    final cropT = (_cropTL.dy * srcH).round();
    final cropR = (_cropBR.dx * srcW).round();
    final cropB = (_cropBR.dy * srcH).round();
    final cropW = cropR - cropL;
    final cropH = cropB - cropT;

    if (cropW <= 0 || cropH <= 0) throw Exception('Área de recorte inválida');

    final bool rotated90 = _rotation % 2 == 1;
    final int outW = rotated90 ? cropH : cropW;
    final int outH = rotated90 ? cropW : cropH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));
    canvas.translate(outW / 2.0, outH / 2.0);
    canvas.rotate(_rotation * math.pi / 2.0);
    canvas.translate(-cropW / 2.0, -cropH / 2.0);

    // Color Matrix
    List<double> matrix = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
    if (_brightness != 0) {
      final b = _brightness * 2.55;
      matrix = _multiplyMatrix(matrix, [1,0,0,0,b, 0,1,0,0,b, 0,0,1,0,b, 0,0,0,1,0]);
    }
    if (_contrast != 0) {
      final c = _contrast / 100.0 + 1.0;
      final t = 128.0 * (1.0 - c);
      matrix = _multiplyMatrix(matrix, [c,0,0,0,t, 0,c,0,0,t, 0,0,c,0,t, 0,0,0,1,0]);
    }
    if (_grayscale) {
      const rx = 0.2126; const gx = 0.7152; const bx = 0.0722;
      matrix = _multiplyMatrix(matrix, [rx,gx,bx,0,0, rx,gx,bx,0,0, rx,gx,bx,0,0, 0,0,0,1,0]);
      const ts = 50.0;
      final offset = (- (_threshold / 255.0) * ts + 0.5) * 255.0;
      matrix = _multiplyMatrix(matrix, [ts,0,0,0,offset, 0,ts,0,0,offset, 0,0,ts,0,offset, 0,0,0,1,0]);
    }

    final paint = Paint()..colorFilter = ColorFilter.matrix(matrix);
    canvas.drawImageRect(
      sourceImg,
      Rect.fromLTRB(cropL.toDouble(), cropT.toDouble(), cropR.toDouble(), cropB.toDouble()),
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      paint,
    );

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(outW, outH);
    // Encode as JPEG quality 95 instead of PNG to keep file size reasonable
    // while preserving quality for sheet music.
    final byteData = await renderedImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('Null byteData');

    // Convert raw RGBA to JPEG via package:image
    final rawImg = img.Image.fromBytes(
      width: outW, height: outH,
      bytes: byteData.buffer,
      order: img.ChannelOrder.rgba,
    );
    final jpegBytes = img.encodeJpg(rawImg, quality: 95);

    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/atril_edit_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(jpegBytes, flush: true);
    return tempFile.path;
  }

  // --- UI Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Editar Imagen'),
        actions: [
          if (!_isProcessing) ...[
            IconButton(
              onPressed: _resetAll,
              icon: const Icon(Icons.refresh, color: Colors.white54),
              tooltip: 'Resetear todo',
            ),
            TextButton.icon(
              onPressed: _confirmEdit,
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              label: const Text('Confirmar', style: TextStyle(color: Colors.greenAccent)),
            ),
          ]
        ],
      ),
      body: _imageLoading || _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _isProcessing ? 'Procesando perspectiva...' : 'Cargando...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(child: _buildPreview()),
                _buildToolControls(),
                _buildToolBar(),
              ],
            ),
    );
  }

  Widget _buildPreview() {
    final previewImg = (_grayscale && _bwPreviewImage != null) ? _bwPreviewImage! : _loadedImage;
    if (previewImg == null) return const SizedBox.shrink();

    // Live matrix for brightness/contrast
    List<double> matrix = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
    if (_brightness != 0) {
      final b = _brightness * 2.55;
      matrix = _multiplyMatrix(matrix, [1,0,0,0,b, 0,1,0,0,b, 0,0,1,0,b, 0,0,0,1,0]);
    }
    if (_contrast != 0) {
      final c = _contrast / 100.0 + 1.0;
      final t = 128.0 * (1.0 - c);
      matrix = _multiplyMatrix(matrix, [c,0,0,0,t, 0,c,0,0,t, 0,0,c,0,t, 0,0,0,1,0]);
    }
    final colorFilter = ColorFilter.matrix(matrix);

    if (_activeTool == _EditTool.crop) {
      return Center(child: _buildCropPreview(_loadedImage!, colorFilter));
    }

    return Center(
      child: RotatedBox(
        quarterTurns: _rotation,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = _fitSize(previewImg.width.toDouble(), previewImg.height.toDouble(), constraints.maxWidth, constraints.maxHeight);
            return CustomPaint(
              painter: _ImagePreviewPainter(image: previewImg, colorFilter: colorFilter),
              size: size,
            );
          },
        ),
      ),
    );
  }

  Size _fitSize(double imgW, double imgH, double maxW, double maxH) {
    final imgAspect = imgW / imgH;
    return (imgAspect > maxW / maxH) ? Size(maxW, maxW / imgAspect) : Size(maxH * imgAspect, maxH);
  }

  Widget _buildCropPreview(ui.Image uiImg, ColorFilter colorFilter) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displaySize = _fitSize(uiImg.width.toDouble(), uiImg.height.toDouble(), constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _ImagePreviewPainter(image: uiImg, colorFilter: colorFilter))),
              Positioned.fill(child: CustomPaint(painter: _PerspectiveCropOverlayPainter(cropTL:_cropTL, cropTR:_cropTR, cropBL:_cropBL, cropBR:_cropBR))),
              _buildCornerHandle(displaySize, _Corner.topLeft, _cropTL),
              _buildCornerHandle(displaySize, _Corner.topRight, _cropTR),
              _buildCornerHandle(displaySize, _Corner.bottomLeft, _cropBL),
              _buildCornerHandle(displaySize, _Corner.bottomRight, _cropBR),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCornerHandle(Size displaySize, _Corner corner, Offset pos) {
    const handleSize = 40.0;
    return Positioned(
      left: pos.dx * displaySize.width - handleSize / 2,
      top: pos.dy * displaySize.height - handleSize / 2,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final dx = details.delta.dx / displaySize.width;
            final dy = details.delta.dy / displaySize.height;
            switch (corner) {
              case _Corner.topLeft: _cropTL = Offset((_cropTL.dx+dx).clamp(0,1), (_cropTL.dy+dy).clamp(0,1)); break;
              case _Corner.topRight: _cropTR = Offset((_cropTR.dx+dx).clamp(0,1), (_cropTR.dy+dy).clamp(0,1)); break;
              case _Corner.bottomLeft: _cropBL = Offset((_cropBL.dx+dx).clamp(0,1), (_cropBL.dy+dy).clamp(0,1)); break;
              case _Corner.bottomRight: _cropBR = Offset((_cropBR.dx+dx).clamp(0,1), (_cropBR.dy+dy).clamp(0,1)); break;
            }
          });
        },
        child: Container(
          width: handleSize, height: handleSize,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.cyanAccent, width: 2), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)]),
        ),
      ),
    );
  }

  Widget _buildToolControls() {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: switch (_activeTool) {
        _EditTool.rotate => _buildRotateControls(),
        _EditTool.bw => _buildBWControls(),
        _EditTool.brightness => _buildBrightnessControls(),
        _EditTool.crop => _buildCropControls(),
      },
    );
  }

  Widget _buildRotateControls() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: () => setState(() => _rotation = (_rotation - 1) % 4), icon: const Icon(Icons.rotate_left, color: Colors.white, size: 32)),
      const SizedBox(width: 32),
      Text('${_rotation * 90}°', style: const TextStyle(color: Colors.white70, fontSize: 18)),
      const SizedBox(width: 32),
      IconButton(onPressed: () => setState(() => _rotation = (_rotation + 1) % 4), icon: const Icon(Icons.rotate_right, color: Colors.white, size: 32)),
    ]);
  }

  Widget _buildBWControls() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        const Icon(Icons.monochrome_photos, color: Colors.white54),
        const SizedBox(width: 12),
        const Text('Blanco y Negro', style: TextStyle(color: Colors.white)),
        const Spacer(),
        Switch(value: _grayscale, activeTrackColor: Colors.cyanAccent, onChanged: (v) {
          setState(() { _grayscale = v; _bwPreviewDirty = true; });
          _rebuildBWPreviewIfNeeded();
        }),
      ]),
      if (_grayscale) ...[
        const SizedBox(height: 4),
        Row(children: [
          const Text('Umbral', style: TextStyle(color: Colors.white54, fontSize: 13)),
          Expanded(child: Slider(value: _threshold, min: 50, max: 220, activeColor: Colors.cyanAccent, inactiveColor: Colors.white24, onChanged: (v) {
            setState(() { _threshold = v; _bwPreviewDirty = true; });
          }, onChangeEnd: (_) => _rebuildBWPreviewIfNeeded())),
          SizedBox(width: 36, child: Text('${_threshold.round()}', style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.right)),
        ]),
      ],
    ]);
  }

  Widget _buildBrightnessControls() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _buildSliderRow('Brillo', _brightness, -100, 100, (v) => setState(() => _brightness = v)),
      const SizedBox(height: 8),
      _buildSliderRow('Contraste', _contrast, -100, 100, (v) => setState(() => _contrast = v)),
    ]);
  }

  Widget _buildSliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Slider(value: value, min: min, max: max, activeColor: Colors.cyanAccent, inactiveColor: Colors.white24, onChanged: onChanged)),
      SizedBox(width: 36, child: Text('${value.round()}', style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.right)),
    ]);
  }

  Widget _buildCropControls() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.crop, color: Colors.white54),
      const SizedBox(width: 12),
      const Text('Arrastrá las esquinas', style: TextStyle(color: Colors.white70, fontSize: 14)),
      if (!_isFullCrop) ...[
        const SizedBox(width: 16),
        TextButton(onPressed: () => setState(() {
          _cropTL = const Offset(0,0); _cropTR = const Offset(1,0); _cropBL = const Offset(0,1); _cropBR = const Offset(1,1);
        }), child: const Text('Resetear', style: TextStyle(color: Colors.cyanAccent))),
      ],
    ]);
  }

  Widget _buildToolBar() {
    return Container(color: Colors.black, child: SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _toolBarItem(_EditTool.rotate, Icons.rotate_right, 'Rotar'),
      _toolBarItem(_EditTool.bw, Icons.monochrome_photos, 'B/N'),
      _toolBarItem(_EditTool.brightness, Icons.brightness_6, 'Brillo'),
      _toolBarItem(_EditTool.crop, Icons.crop, 'Recortar'),
    ])));
  }

  Widget _toolBarItem(_EditTool tool, IconData icon, String label) {
    final selected = _activeTool == tool;
    return InkWell(onTap: () => setState(() => _activeTool = tool), child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: selected ? Colors.cyanAccent : Colors.white54, size: 24),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: selected ? Colors.cyanAccent : Colors.white54, fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
    ])));
  }
}
