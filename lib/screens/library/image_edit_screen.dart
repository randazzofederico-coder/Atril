import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Holds all edit parameters so they can be restored when re-editing.
class ImageEditParams {
  final int rotation;
  final bool grayscale;
  final double threshold;
  final double brightness;
  final double contrast;
  final double cropLeft, cropTop, cropRight, cropBottom;

  const ImageEditParams({
    this.rotation = 0,
    this.grayscale = false,
    this.threshold = 128.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.cropLeft = 0.0,
    this.cropTop = 0.0,
    this.cropRight = 1.0,
    this.cropBottom = 1.0,
  });

  bool get isDefault =>
      rotation == 0 && !grayscale && threshold == 128.0 &&
      brightness == 0.0 && contrast == 0.0 &&
      cropLeft == 0.0 && cropTop == 0.0 &&
      cropRight == 1.0 && cropBottom == 1.0;
}

/// Result returned by the editor.
class ImageEditResult {
  final String editedPath;
  final ImageEditParams params;
  const ImageEditResult(this.editedPath, this.params);
}

/// Image editor with Rotate, B/W, Brightness/Contrast, and Crop tools.
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

  late double _cropLeft;
  late double _cropTop;
  late double _cropRight;
  late double _cropBottom;

  _EditTool _activeTool = _EditTool.rotate;
  bool _isProcessing = false;

  // Original loaded image (never mutated)
  ui.Image? _loadedImage;
  bool _imageLoading = true;

  // Pre-rendered B/W image (software-rendered, no GPU precision issues)
  ui.Image? _bwPreviewImage;
  bool _bwPreviewDirty = true; // Needs re-render when grayscale/threshold change

  @override
  void initState() {
    super.initState();
    final p = widget.initialParams ?? const ImageEditParams();
    _rotation = p.rotation;
    _grayscale = p.grayscale;
    _threshold = p.threshold;
    _brightness = p.brightness;
    _contrast = p.contrast;
    _cropLeft = p.cropLeft;
    _cropTop = p.cropTop;
    _cropRight = p.cropRight;
    _cropBottom = p.cropBottom;

    _loadImage();
  }

  void _resetAll() {
    setState(() {
      _rotation = 0;
      _grayscale = false;
      _threshold = 128.0;
      _brightness = 0.0;
      _contrast = 0.0;
      _cropLeft = 0.0;
      _cropTop = 0.0;
      _cropRight = 1.0;
      _cropBottom = 1.0;
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
        cropLeft: _cropLeft,
        cropTop: _cropTop,
        cropRight: _cropRight,
        cropBottom: _cropBottom,
      );

  // --- B/W preview rendering (software path, avoids GPU fp16 precision issues) ---

  /// Renders the B/W threshold effect via PictureRecorder.toImage().
  /// This uses the same code path as the final render, which the user
  /// confirmed produces correct/uniform results.
  Future<void> _rebuildBWPreviewIfNeeded() async {
    if (!_bwPreviewDirty || !_grayscale) return;
    final img = _loadedImage;
    if (img == null) return;

    _bwPreviewDirty = false;

    // Build grayscale + threshold matrix
    List<double> bwMatrix = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    // Grayscale
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    bwMatrix = _multiplyMatrix(bwMatrix, [
      r, g, b, 0, 0,
      r, g, b, 0, 0,
      r, g, b, 0, 0,
      0, 0, 0, 1, 0,
    ]);

    // Threshold
    const thresholdScale = 50.0;
    final t = _threshold / 255.0;
    final offset = (-t * thresholdScale + 0.5) * 255.0;
    bwMatrix = _multiplyMatrix(bwMatrix, [
      thresholdScale, 0, 0, 0, offset,
      0, thresholdScale, 0, 0, offset,
      0, 0, thresholdScale, 0, offset,
      0, 0, 0, 1, 0,
    ]);

    // Render via PictureRecorder (software path — produces correct results)
    final recorder = ui.PictureRecorder();
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final paint = Paint()..colorFilter = ColorFilter.matrix(bwMatrix);
    canvas.drawImage(img, Offset.zero, paint);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(img.width, img.height);

    if (mounted) {
      setState(() => _bwPreviewImage = rendered);
    }
  }

  // --- Color matrix for brightness/contrast ONLY (small values, GPU-safe) ---

  List<double> _buildLiveColorMatrix() {
    List<double> matrix = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    if (_brightness != 0) {
      final b = _brightness * 2.55;
      matrix = _multiplyMatrix(matrix, [
        1, 0, 0, 0, b,
        0, 1, 0, 0, b,
        0, 0, 1, 0, b,
        0, 0, 0, 1, 0,
      ]);
    }

    if (_contrast != 0) {
      final c = _contrast / 100.0;
      final scale = 1.0 + c;
      final translate = 128.0 * (1.0 - scale);
      matrix = _multiplyMatrix(matrix, [
        scale, 0, 0, 0, translate,
        0, scale, 0, 0, translate,
        0, 0, scale, 0, translate,
        0, 0, 0, 1, 0,
      ]);
    }

    // If NOT in B/W mode but grayscale is off, just return brightness/contrast
    // If in B/W mode, the B/W is already baked into _bwPreviewImage
    return matrix;
  }

  /// Full matrix for final rendering (used by _renderFinalImage only).
  List<double> _buildFullColorMatrix() {
    List<double> matrix = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    if (_brightness != 0) {
      final b = _brightness * 2.55;
      matrix = _multiplyMatrix(matrix, [
        1, 0, 0, 0, b,
        0, 1, 0, 0, b,
        0, 0, 1, 0, b,
        0, 0, 0, 1, 0,
      ]);
    }

    if (_contrast != 0) {
      final c = _contrast / 100.0;
      final scale = 1.0 + c;
      final translate = 128.0 * (1.0 - scale);
      matrix = _multiplyMatrix(matrix, [
        scale, 0, 0, 0, translate,
        0, scale, 0, 0, translate,
        0, 0, scale, 0, translate,
        0, 0, 0, 1, 0,
      ]);
    }

    if (_grayscale) {
      const r = 0.2126;
      const g = 0.7152;
      const b = 0.0722;
      matrix = _multiplyMatrix(matrix, [
        r, g, b, 0, 0,
        r, g, b, 0, 0,
        r, g, b, 0, 0,
        0, 0, 0, 1, 0,
      ]);

      const thresholdScale = 50.0;
      final t = _threshold / 255.0;
      final offset = (-t * thresholdScale + 0.5) * 255.0;
      matrix = _multiplyMatrix(matrix, [
        thresholdScale, 0, 0, 0, offset,
        0, thresholdScale, 0, 0, offset,
        0, 0, thresholdScale, 0, offset,
        0, 0, 0, 1, 0,
      ]);
    }

    return matrix;
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

  // --- Confirm ---

  Future<void> _confirmEdit() async {
    final img = _loadedImage;
    if (img == null) return;

    setState(() => _isProcessing = true);

    try {
      final editedPath = await _renderFinalImage(img);
      if (mounted) {
        Navigator.of(context).pop(ImageEditResult(editedPath, _currentParams));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error procesando imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String> _renderFinalImage(ui.Image sourceImg) async {
    final int srcW = sourceImg.width;
    final int srcH = sourceImg.height;

    final cropL = (_cropLeft * srcW).round();
    final cropT = (_cropTop * srcH).round();
    final cropR = (_cropRight * srcW).round();
    final cropB = (_cropBottom * srcH).round();
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

    // Use full matrix for final render (PictureRecorder uses software path)
    final matrix = _buildFullColorMatrix();
    final paint = Paint()..colorFilter = ColorFilter.matrix(matrix);

    canvas.drawImageRect(
      sourceImg,
      Rect.fromLTRB(cropL.toDouble(), cropT.toDouble(), cropR.toDouble(), cropB.toDouble()),
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      paint,
    );

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(outW, outH);
    final byteData = await renderedImage.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) throw Exception('No se pudo renderizar');

    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/atril_edit_${DateTime.now().millisecondsSinceEpoch}.png');
    await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

    return tempFile.path;
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Editar Imagen'),
        actions: [
          if (!_isProcessing)
            IconButton(
              onPressed: _resetAll,
              icon: const Icon(Icons.refresh, color: Colors.white54),
              tooltip: 'Resetear todo',
            ),
          if (!_isProcessing)
            TextButton.icon(
              onPressed: _confirmEdit,
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              label: const Text('Confirmar', style: TextStyle(color: Colors.greenAccent)),
            ),
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
                    _isProcessing ? 'Procesando...' : 'Cargando...',
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

  /// Gets the image to display: B/W pre-rendered or original.
  ui.Image? get _previewImage =>
      (_grayscale && _bwPreviewImage != null) ? _bwPreviewImage : _loadedImage;

  Widget _buildPreview() {
    final img = _previewImage;
    if (img == null) return const SizedBox.shrink();

    // Live color filter: only brightness/contrast (small GPU-safe values)
    final liveMatrix = _buildLiveColorMatrix();
    final colorFilter = ColorFilter.matrix(liveMatrix);

    if (_activeTool == _EditTool.crop) {
      // Use the original image for crop (coordinates are relative to original)
      return Center(
        child: _buildCropPreview(_loadedImage!, colorFilter),
      );
    }

    return Center(
      child: RotatedBox(
        quarterTurns: _rotation,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _ImagePreviewPainter(image: img, colorFilter: colorFilter),
              size: _fitSize(
                img.width.toDouble(), img.height.toDouble(),
                constraints.maxWidth, constraints.maxHeight,
              ),
            );
          },
        ),
      ),
    );
  }

  Size _fitSize(double imgW, double imgH, double maxW, double maxH) {
    final imgAspect = imgW / imgH;
    if (imgAspect > maxW / maxH) {
      return Size(maxW, maxW / imgAspect);
    } else {
      return Size(maxH * imgAspect, maxH);
    }
  }

  Widget _buildCropPreview(ui.Image img, ColorFilter colorFilter) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displaySize = _fitSize(
          img.width.toDouble(), img.height.toDouble(),
          constraints.maxWidth, constraints.maxHeight,
        );

        return SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ImagePreviewPainter(image: img, colorFilter: colorFilter),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropOverlayPainter(
                    cropLeft: _cropLeft, cropTop: _cropTop,
                    cropRight: _cropRight, cropBottom: _cropBottom,
                  ),
                ),
              ),
              _buildHandle(displaySize.width, displaySize.height, _Corner.topLeft),
              _buildHandle(displaySize.width, displaySize.height, _Corner.topRight),
              _buildHandle(displaySize.width, displaySize.height, _Corner.bottomLeft),
              _buildHandle(displaySize.width, displaySize.height, _Corner.bottomRight),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(double displayW, double displayH, _Corner corner) {
    double left, top;

    switch (corner) {
      case _Corner.topLeft:
        left = _cropLeft * displayW; top = _cropTop * displayH; break;
      case _Corner.topRight:
        left = _cropRight * displayW; top = _cropTop * displayH; break;
      case _Corner.bottomLeft:
        left = _cropLeft * displayW; top = _cropBottom * displayH; break;
      case _Corner.bottomRight:
        left = _cropRight * displayW; top = _cropBottom * displayH; break;
    }

    const handleSize = 32.0;

    return Positioned(
      left: left - handleSize / 2,
      top: top - handleSize / 2,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final dx = details.delta.dx / displayW;
            final dy = details.delta.dy / displayH;
            switch (corner) {
              case _Corner.topLeft:
                _cropLeft = (_cropLeft + dx).clamp(0.0, _cropRight - 0.05);
                _cropTop = (_cropTop + dy).clamp(0.0, _cropBottom - 0.05);
                break;
              case _Corner.topRight:
                _cropRight = (_cropRight + dx).clamp(_cropLeft + 0.05, 1.0);
                _cropTop = (_cropTop + dy).clamp(0.0, _cropBottom - 0.05);
                break;
              case _Corner.bottomLeft:
                _cropLeft = (_cropLeft + dx).clamp(0.0, _cropRight - 0.05);
                _cropBottom = (_cropBottom + dy).clamp(_cropTop + 0.05, 1.0);
                break;
              case _Corner.bottomRight:
                _cropRight = (_cropRight + dx).clamp(_cropLeft + 0.05, 1.0);
                _cropBottom = (_cropBottom + dy).clamp(_cropTop + 0.05, 1.0);
                break;
            }
          });
        },
        child: Container(
          width: handleSize, height: handleSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.cyanAccent, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  // --- Tool controls ---

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => setState(() => _rotation = (_rotation - 1) % 4),
          icon: const Icon(Icons.rotate_left, color: Colors.white, size: 32),
          tooltip: 'Rotar izquierda',
        ),
        const SizedBox(width: 32),
        Text('${_rotation * 90}°', style: const TextStyle(color: Colors.white70, fontSize: 18)),
        const SizedBox(width: 32),
        IconButton(
          onPressed: () => setState(() => _rotation = (_rotation + 1) % 4),
          icon: const Icon(Icons.rotate_right, color: Colors.white, size: 32),
          tooltip: 'Rotar derecha',
        ),
      ],
    );
  }

  Widget _buildBWControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.monochrome_photos, color: Colors.white54),
            const SizedBox(width: 12),
            const Text('Blanco y Negro', style: TextStyle(color: Colors.white)),
            const Spacer(),
            Switch(
              value: _grayscale,
              activeTrackColor: Colors.cyanAccent,
              onChanged: (v) {
                setState(() {
                  _grayscale = v;
                  _bwPreviewDirty = true;
                });
                _rebuildBWPreviewIfNeeded();
              },
            ),
          ],
        ),
        if (_grayscale) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Umbral', style: TextStyle(color: Colors.white54, fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _threshold,
                  min: 50, max: 220,
                  activeColor: Colors.cyanAccent,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    setState(() {
                      _threshold = v;
                      _bwPreviewDirty = true;
                    });
                  },
                  onChangeEnd: (_) => _rebuildBWPreviewIfNeeded(),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${_threshold.round()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBrightnessControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSliderRow('Brillo', _brightness, -100, 100, (v) => setState(() => _brightness = v)),
        const SizedBox(height: 8),
        _buildSliderRow('Contraste', _contrast, -100, 100, (v) => setState(() => _contrast = v)),
      ],
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
        Expanded(
          child: Slider(
            value: value, min: min, max: max,
            activeColor: Colors.cyanAccent,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCropControls() {
    final hasCustomCrop = _cropLeft > 0.01 || _cropTop > 0.01 || _cropRight < 0.99 || _cropBottom < 0.99;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.crop, color: Colors.white54),
        const SizedBox(width: 12),
        const Text('Arrastrá las esquinas', style: TextStyle(color: Colors.white70, fontSize: 14)),
        if (hasCustomCrop) ...[
          const SizedBox(width: 16),
          TextButton(
            onPressed: () => setState(() {
              _cropLeft = 0; _cropTop = 0; _cropRight = 1; _cropBottom = 1;
            }),
            child: const Text('Resetear', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ],
    );
  }

  Widget _buildToolBar() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _toolBarItem(_EditTool.rotate, Icons.rotate_right, 'Rotar'),
            _toolBarItem(_EditTool.bw, Icons.monochrome_photos, 'B/N'),
            _toolBarItem(_EditTool.brightness, Icons.brightness_6, 'Brillo'),
            _toolBarItem(_EditTool.crop, Icons.crop, 'Recortar'),
          ],
        ),
      ),
    );
  }

  Widget _toolBarItem(_EditTool tool, IconData icon, String label) {
    final selected = _activeTool == tool;
    return InkWell(
      onTap: () => setState(() => _activeTool = tool),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.cyanAccent : Colors.white54, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              color: selected ? Colors.cyanAccent : Colors.white54,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}

// --- Custom painter ---
class _ImagePreviewPainter extends CustomPainter {
  final ui.Image image;
  final ColorFilter colorFilter;

  _ImagePreviewPainter({required this.image, required this.colorFilter});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..colorFilter = colorFilter;
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(_ImagePreviewPainter old) =>
      old.image != image || old.colorFilter != colorFilter;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CropOverlayPainter extends CustomPainter {
  final double cropLeft, cropTop, cropRight, cropBottom;

  _CropOverlayPainter({
    required this.cropLeft, required this.cropTop,
    required this.cropRight, required this.cropBottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = cropLeft * size.width;
    final top = cropTop * size.height;
    final right = cropRight * size.width;
    final bottom = cropBottom * size.height;

    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), dimPaint);
    canvas.drawRect(Rect.fromLTRB(0, bottom, size.width, size.height), dimPaint);
    canvas.drawRect(Rect.fromLTRB(0, top, left, bottom), dimPaint);
    canvas.drawRect(Rect.fromLTRB(right, top, size.width, bottom), dimPaint);

    final borderPaint = Paint()
      ..color = Colors.cyanAccent ..style = PaintingStyle.stroke ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), borderPaint);

    final thirdPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke ..strokeWidth = 0.5;
    final w = right - left;
    final h = bottom - top;
    canvas.drawLine(Offset(left + w / 3, top), Offset(left + w / 3, bottom), thirdPaint);
    canvas.drawLine(Offset(left + 2 * w / 3, top), Offset(left + 2 * w / 3, bottom), thirdPaint);
    canvas.drawLine(Offset(left, top + h / 3), Offset(right, top + h / 3), thirdPaint);
    canvas.drawLine(Offset(left, top + 2 * h / 3), Offset(right, top + 2 * h / 3), thirdPaint);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.cropLeft != cropLeft || old.cropTop != cropTop ||
      old.cropRight != cropRight || old.cropBottom != cropBottom;
}
