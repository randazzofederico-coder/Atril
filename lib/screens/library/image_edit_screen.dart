import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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

/// Params passed to the background island for heavy image processing.
class _PerspectiveProcessParams {
  final String sourcePath;
  final String tempPath;
  final int srcW, srcH;
  final int rotation;
  final bool grayscale;
  final double threshold;
  final double brightness;
  final double contrast;
  final Offset cropTL, cropTR, cropBL, cropBR;

  _PerspectiveProcessParams({
    required this.sourcePath,
    required this.tempPath,
    required this.srcW, required this.srcH,
    required this.rotation,
    required this.grayscale,
    required this.threshold,
    required this.brightness,
    required this.contrast,
    required this.cropTL, required this.cropTR,
    required this.cropBL, required this.cropBR,
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

    await Isolate.spawn(
      _processPerspectiveWithProgress,
      _IsolateMessage(isolateParams, receivePort.sendPort),
    );

    receivePort.listen((message) {
      if (message is double) {
        // Progress update (0.0 – 1.0)
        onProgress(message);
      } else if (message is String) {
        // Final result path
        completer.complete(message);
        receivePort.close();
      } else if (message is List && message.first == 'error') {
        completer.completeError(Exception(message.last));
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

// --- Top-level Isolate Processing ---

/// Message wrapper to pass both params and a SendPort to the isolate.
class _IsolateMessage {
  final _PerspectiveProcessParams params;
  final SendPort sendPort;
  const _IsolateMessage(this.params, this.sendPort);
}

/// Isolate entry point that sends progress updates through the SendPort.
void _processPerspectiveWithProgress(_IsolateMessage msg) {
  try {
    final result = _runPerspectiveWarp(msg.params, msg.sendPort);
    msg.sendPort.send(result); // Send final path as String
  } catch (e) {
    msg.sendPort.send(['error', e.toString()]);
  }
}

/// Core perspective warp logic. Reports progress through [sendPort] if non-null.
String _runPerspectiveWarp(_PerspectiveProcessParams p, SendPort? sendPort) {
  final file = File(p.sourcePath);
  final bytes = file.readAsBytesSync();
  var source = img.decodeImage(bytes);
  if (source == null) throw Exception('No se pudo decodificar la imagen');

  // CRITICAL: Ensure orientation matches Flutter UI view
  source = img.bakeOrientation(source);
  final int realW = source.width;
  final int realH = source.height;

  sendPort?.send(0.05); // 5% — image decoded

  // Warp Quad points back to real pixel coordinates
  final tl = math.Point<double>(p.cropTL.dx * realW, p.cropTL.dy * realH);
  final tr = math.Point<double>(p.cropTR.dx * realW, p.cropTR.dy * realH);
  final bl = math.Point<double>(p.cropBL.dx * realW, p.cropBL.dy * realH);
  final br = math.Point<double>(p.cropBR.dx * realW, p.cropBR.dy * realH);

  // Adaptive output resolution based on source image size.
  final double sourceMegapixels = realW * realH / 1e6;
  final int outW, outH;
  if (sourceMegapixels >= 8) {
    outW = 2480; outH = 3508; // 300 DPI A4
  } else if (sourceMegapixels >= 4) {
    outW = 2067; outH = 2923; // 250 DPI A4
  } else {
    outW = 1654; outH = 2339; // 200 DPI A4
  }

  // 1. Calculate Homography Matrix H (3x3)
  final h = _calculateHomography(
    const math.Point(0.0, 0.0), math.Point(outW.toDouble(), 0.0),
    math.Point(outW.toDouble(), outH.toDouble()), math.Point(0.0, outH.toDouble()),
    tl, tr, br, bl,
  );

  // 2. Perform Perspective Warp with progress reporting
  //    The warp is ~80% of total processing time.
  final result = img.Image(width: outW, height: outH);
  final int progressInterval = (outH / 20).ceil(); // Report ~20 times
  for (int v = 0; v < outH; v++) {
    for (int u = 0; u < outW; u++) {
      final double denominator = h[6] * u + h[7] * v + 1.0;
      final double x = (h[0] * u + h[1] * v + h[2]) / denominator;
      final double y = (h[3] * u + h[4] * v + h[5]) / denominator;

      if (x >= 0 && x < realW - 1 && y >= 0 && y < realH - 1) {
        final pixel = source.getPixelInterpolate(x, y, interpolation: img.Interpolation.cubic);
        result.setPixel(u, v, pixel);
      }
    }
    // Report progress: 5% (decode) + 80% (warp) = 5..85%
    if (v % progressInterval == 0) {
      sendPort?.send(0.05 + 0.80 * (v / outH));
    }
  }

  sendPort?.send(0.85); // Warp complete

  // 3. Apply Filters
  if (p.brightness != 0 || p.contrast != 0) {
    img.adjustColor(
      result,
      brightness: 1.0 + (p.brightness / 100.0),
      contrast: 1.0 + (p.contrast / 100.0),
    );
  }

  if (p.grayscale) {
    img.grayscale(result);
    img.luminanceThreshold(result, threshold: p.threshold / 255.0);
  }

  sendPort?.send(0.90); // Filters done

  // Rotation (if needed)
  var finalResult = result;
  if (p.rotation != 0) {
    finalResult = img.copyRotate(result, angle: (p.rotation % 4) * 90);
  }

  // Save as JPEG quality 95
  final outBytes = img.encodeJpg(finalResult, quality: 95);
  final outFile = File(p.tempPath);
  outFile.writeAsBytesSync(outBytes);

  sendPort?.send(0.99); // Encoding done

  return p.tempPath;
}

/// Solves for the 8 coefficients of the 3x3 homography matrix (h22 = 1).
/// Maps (u,v) in target square to (x,y) in source quadrilateral.
List<double> _calculateHomography(
    math.Point<double> t0, math.Point<double> t1, math.Point<double> t2, math.Point<double> t3,
    math.Point<double> s0, math.Point<double> s1, math.Point<double> s2, math.Point<double> s3) {
  
  // Matrix A (8x8) and vector B (8x1) for the linear system A * h = B
  final List<List<double>> a = List.generate(8, (_) => List.filled(8, 0.0));
  final List<double> b = List.filled(8, 0.0);

  final targets = [t0, t1, t2, t3];
  final sources = [s0, s1, s2, s3];

  for (int i = 0; i < 4; i++) {
    final ui = targets[i].x;
    final vi = targets[i].y;
    final xi = sources[i].x;
    final yi = sources[i].y;

    // Equation for X: h00*u + h01*v + h02 - h20*u*x - h21*v*x = x
    a[i * 2][0] = ui; a[i * 2][1] = vi; a[i * 2][2] = 1.0;
    a[i * 2][6] = -ui * xi; a[i * 2][7] = -vi * xi;
    b[i * 2] = xi;

    // Equation for Y: h10*u + h11*v + h12 - h20*u*y - h21*v*y = y
    a[i * 2 + 1][3] = ui; a[i * 2 + 1][4] = vi; a[i * 2 + 1][5] = 1.0;
    a[i * 2 + 1][6] = -ui * yi; a[i * 2 + 1][7] = -vi * yi;
    b[i * 2 + 1] = yi;
  }

  // Solve using Gaussian elimination
  return _solveLinearSystem(a, b);
}

/// Simple 8x8 Gaussian elimination solver with pivoting.
List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
  final int n = b.length;
  for (int i = 0; i < n; i++) {
    // Pivot selection
    int max = i;
    for (int k = i + 1; k < n; k++) {
      if (a[k][i].abs() > a[max][i].abs()) max = k;
    }
    // Swap rows
    final tempA = a[i]; a[i] = a[max]; a[max] = tempA;
    final tempB = b[i]; b[i] = b[max]; b[max] = tempB;

    // Pivot
    for (int k = i + 1; k < n; k++) {
      final double factor = a[k][i] / a[i][i];
      b[k] -= factor * b[i];
      for (int j = i; j < n; j++) {
        a[k][j] -= factor * a[i][j];
      }
    }
  }

  // Back substitution
  final List<double> x = List.filled(n, 0.0);
  for (int i = n - 1; i >= 0; i--) {
    double sum = 0.0;
    for (int j = i + 1; j < n; j++) {
      sum += a[i][j] * x[j];
    }
    x[i] = (b[i] - sum) / a[i][i];
  }
  return x;
}

// --- Painters ---

class _ImagePreviewPainter extends CustomPainter {
  final ui.Image image; final ColorFilter colorFilter;
  _ImagePreviewPainter({required this.image, required this.colorFilter});
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..colorFilter = colorFilter;
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }
  @override bool shouldRepaint(_ImagePreviewPainter old) => old.image != image || old.colorFilter != colorFilter;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _PerspectiveCropOverlayPainter extends CustomPainter {
  final Offset cropTL, cropTR, cropBL, cropBR;
  _PerspectiveCropOverlayPainter({required this.cropTL, required this.cropTR, required this.cropBL, required this.cropBR});

  @override void paint(Canvas canvas, Size size) {
    final tl = Offset(cropTL.dx*size.width, cropTL.dy*size.height);
    final tr = Offset(cropTR.dx*size.width, cropTR.dy*size.height);
    final bl = Offset(cropBL.dx*size.width, cropBL.dy*size.height);
    final br = Offset(cropBR.dx*size.width, cropBR.dy*size.height);

    final quadPath = Path()..moveTo(tl.dx,tl.dy)..lineTo(tr.dx,tr.dy)..lineTo(br.dx,br.dy)..lineTo(bl.dx,bl.dy)..close();
    final fullPath = Path()..addRect(Rect.fromLTWH(0,0,size.width,size.height));
    final dimPath = Path.combine(PathOperation.difference, fullPath, quadPath);
    canvas.drawPath(dimPath, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawPath(quadPath, Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2.0);

    final guidePaint = Paint()..color = Colors.white.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (int i=1; i<=2; i++) {
       final t = i/3.0;
       canvas.drawLine(Offset.lerp(tl, bl, t)!, Offset.lerp(tr, br, t)!, guidePaint);
       canvas.drawLine(Offset.lerp(tl, tr, t)!, Offset.lerp(bl, br, t)!, guidePaint);
    }
  }
  @override bool shouldRepaint(_PerspectiveCropOverlayPainter old) => old.cropTL != cropTL || old.cropTR != cropTR;
}
