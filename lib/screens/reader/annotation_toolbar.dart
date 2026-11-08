import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/annotation_stroke.dart';
import '../../models/annotation_style.dart';

/// Palette of colors for annotation tools.
const List<Color> kAnnotationColors = [
  Colors.black,
  Colors.redAccent,
  Color(0xFF2196F3), // Blue
  Color(0xFF4CAF50), // Green
  Color(0xFFFF9800), // Orange
  Color(0xFF9C27B0), // Violet
  Color(0xFFFFEB3B), // Yellow
  Colors.white,
];

class AnnotationToolbar extends StatefulWidget {
  final AnnotationTool selectedTool;
  final Color selectedColor;
  final double selectedWidth;
  final ValueChanged<AnnotationTool> onTypeChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;

  const AnnotationToolbar({
    super.key,
    required this.selectedTool,
    required this.selectedColor,
    required this.selectedWidth,
    required this.onTypeChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  @override
  State<AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends State<AnnotationToolbar> {
  bool _expanded = false;

  /// Herramientas con tamaño ajustable.
  bool get _hasSize =>
      widget.selectedTool == AnnotationTool.pen ||
      widget.selectedTool == AnnotationTool.highlighter ||
      widget.selectedTool == AnnotationTool.whiteout ||
      widget.selectedTool == AnnotationTool.eraser;

  /// La goma no tiene color.
  bool get _hasColor => widget.selectedTool != AnnotationTool.eraser;

  // --- Slider logarítmico de tamaño ------------------------------------------
  // t ∈ [0..1] → ancho = min · (max/min)^t. Da mucha precisión en tamaños
  // chicos (0.3, 0.5, 0.8...) sin perder los grandes.

  static double _widthToT(double w) {
    final clamped = w.clamp(AnnotationStyle.minWidth, AnnotationStyle.maxWidth);
    return math.log(clamped / AnnotationStyle.minWidth) /
        math.log(AnnotationStyle.maxWidth / AnnotationStyle.minWidth);
  }

  static double _tToWidth(double t) {
    final raw = AnnotationStyle.minWidth *
        math.pow(AnnotationStyle.maxWidth / AnnotationStyle.minWidth, t);
    // Redondeo "amable" según la escala
    if (raw < 1) return (raw * 10).round() / 10;   // 0.3, 0.4, ...
    if (raw < 5) return (raw * 4).round() / 4;     // 1, 1.25, 1.5, ...
    if (raw < 10) return (raw * 2).round() / 2;    // 5, 5.5, 6, ...
    return raw.roundToDouble();                    // 10, 11, 12, ...
  }

  static String _formatWidth(double w) {
    if (w == w.roundToDouble()) return w.toStringAsFixed(0);
    return w < 1 ? w.toStringAsFixed(1) : w.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary row: Tool icons + Undo/Redo/Clear
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                _ToolButton(
                  icon: Icons.gesture,
                  tooltip: 'Lapicera',
                  isSelected: widget.selectedTool == AnnotationTool.pen,
                  color: widget.selectedTool == AnnotationTool.pen ? widget.selectedColor : null,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.pen);
                    setState(() => _expanded = true);
                  },
                ),
                _ToolButton(
                  icon: Icons.highlight,
                  tooltip: 'Resaltador',
                  isSelected: widget.selectedTool == AnnotationTool.highlighter,
                  color: widget.selectedTool == AnnotationTool.highlighter ? widget.selectedColor : null,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.highlighter);
                    setState(() => _expanded = true);
                  },
                ),
                _ToolButton(
                  icon: Icons.edit_off,
                  tooltip: 'Tapadera (Whiteout)',
                  isSelected: widget.selectedTool == AnnotationTool.whiteout,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.whiteout);
                    setState(() => _expanded = true); // mostrar tamaño
                  },
                ),
                _ToolButton(
                  icon: Icons.cleaning_services_outlined,
                  tooltip: 'Borrador (borra lo que toca)',
                  isSelected: widget.selectedTool == AnnotationTool.eraser,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.eraser);
                    setState(() => _expanded = true); // mostrar tamaño
                  },
                ),
                const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10, width: 20),
                _ToolButton(
                  icon: Icons.title,
                  tooltip: 'Texto',
                  isSelected: widget.selectedTool == AnnotationTool.text,
                  color: widget.selectedTool == AnnotationTool.text ? widget.selectedColor : null,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.text);
                    setState(() => _expanded = true);
                  },
                ),
                _ToolButton(
                  icon: Icons.approval,
                  tooltip: 'Sello',
                  isSelected: widget.selectedTool == AnnotationTool.stamp,
                  onTap: () {
                    widget.onTypeChanged(AnnotationTool.stamp);
                    setState(() => _expanded = false);
                  },
                ),
                const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10, width: 20),
                // Toggle expand button
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.palette,
                    color: _expanded ? Colors.cyanAccent : Colors.white54,
                  ),
                  tooltip: _expanded ? 'Ocultar opciones' : 'Color y grosor',
                ),
                const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10, width: 20),
                IconButton(
                  onPressed: widget.onUndo,
                  icon: const Icon(Icons.undo, color: Colors.white),
                  tooltip: 'Deshacer',
                ),
                IconButton(
                  onPressed: widget.onRedo,
                  icon: const Icon(Icons.redo, color: Colors.white),
                  tooltip: 'Rehacer',
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                  tooltip: 'Limpiar Página',
                ),
              ],
            ),
          ),

          // Secondary row: Color palette + Width slider (expandable)
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildOptionsRow(),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          // Color palette (la goma no tiene color)
          if (!_hasColor)
            const Expanded(
              child: Text('Tamaño de la goma', style: TextStyle(color: Colors.white70, fontSize: 13)),
            )
          else
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in kAnnotationColors)
                    _ColorDot(
                      color: c,
                      isSelected: _colorsEqual(widget.selectedColor, c),
                      onTap: () => widget.onColorChanged(c),
                    ),
                ],
              ),
            ),
          ),
          // Tamaño (lapicera, resaltador, tapadera y goma)
          if (_hasSize) ...[
            const SizedBox(width: 8),
            // Width preview line
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              child: Container(
                width: widget.selectedWidth.clamp(1.0, 22.0),
                height: widget.selectedWidth.clamp(1.0, 22.0),
                decoration: BoxDecoration(
                  color: _hasColor ? widget.selectedColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: _hasColor ? null : Border.all(color: Colors.white70, width: 1.5),
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  activeTrackColor: Colors.cyanAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.cyanAccent,
                  overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _widthToT(widget.selectedWidth),
                  min: 0.0,
                  max: 1.0,
                  label: _formatWidth(widget.selectedWidth),
                  divisions: 60,
                  onChanged: (t) => widget.onWidthChanged(_tToWidth(t)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _colorsEqual(Color a, Color b) {
    return a.toARGB32() == b.toARGB32();
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isSelected ? Colors.cyanAccent : Colors.white54;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: iconColor),
          onPressed: onTap,
        ),
        // Small color indicator dot below icon when selected and has custom color
        if (isSelected && color != null)
          Positioned(
            bottom: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 0.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: isSelected ? 30 : 26,
        height: isSelected ? 30 : 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white24,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.4), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }
}
