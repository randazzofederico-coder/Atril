import 'package:flutter/material.dart';
import '../../models/annotation_stroke.dart';

class AnnotationToolbar extends StatelessWidget {
  final AnnotationTool selectedTool;
  final ValueChanged<AnnotationTool> onTypeChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  // Future: Color and Width pickers

  const AnnotationToolbar({
    super.key,
    required this.selectedTool,
    required this.onTypeChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: Colors.black, // Dark theme for toolbar
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _ToolButton(
            icon: Icons.gesture,
            tooltip: 'Lapicera',
            isSelected: selectedTool == AnnotationTool.pen,
            onTap: () => onTypeChanged(AnnotationTool.pen),
          ),
          _ToolButton(
            icon: Icons.highlight,
            tooltip: 'Resaltador',
            isSelected: selectedTool == AnnotationTool.highlighter,
            onTap: () => onTypeChanged(AnnotationTool.highlighter),
          ),
          _ToolButton(
            icon: Icons.edit_off, // or brush
            tooltip: 'Tapadera (Whiteout)',
            isSelected: selectedTool == AnnotationTool.whiteout,
            onTap: () => onTypeChanged(AnnotationTool.whiteout),
          ),
          const VerticalDivider(color: Colors.white24, indent: 12, endIndent: 12, width: 24),
          _ToolButton(
            icon: Icons.title, 
            tooltip: 'Texto',
            isSelected: selectedTool == AnnotationTool.text,
            onTap: () => onTypeChanged(AnnotationTool.text),
          ),
          _ToolButton(
            icon: Icons.approval, // Stamp icon placeholder
            tooltip: 'Sello',
            isSelected: selectedTool == AnnotationTool.stamp,
            onTap: () => onTypeChanged(AnnotationTool.stamp),
          ),
          const VerticalDivider(color: Colors.white24, indent: 12, endIndent: 12, width: 24),
          IconButton(
            onPressed: onUndo,
            icon: const Icon(Icons.undo, color: Colors.white),
            tooltip: 'Deshacer',
          ),
          IconButton(
            onPressed: onRedo,
            icon: const Icon(Icons.redo, color: Colors.white),
            tooltip: 'Rehacer',
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
             tooltip: 'Limpiar Página',
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.cyanAccent : Colors.white54;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }
}
