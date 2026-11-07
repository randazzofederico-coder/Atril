import 'package:flutter/material.dart';

/// Diálogo para elegir si una exportación incluye o no las anotaciones.
///
/// Devuelve `true` (con anotaciones), `false` (sin anotaciones) o `null` si el
/// usuario canceló.
Future<bool?> askIncludeAnnotations(
  BuildContext context, {
  required String title,
  String withSubtitle = 'Las anotaciones quedan dibujadas en el PDF',
  String withoutSubtitle = 'PDF original, tal como fue importado',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        _Option(
          icon: Icons.draw_outlined,
          label: 'Con anotaciones',
          subtitle: withSubtitle,
          onTap: () => Navigator.pop(ctx, true),
        ),
        _Option(
          icon: Icons.picture_as_pdf_outlined,
          label: 'Sin anotaciones',
          subtitle: withoutSubtitle,
          onTap: () => Navigator.pop(ctx, false),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
