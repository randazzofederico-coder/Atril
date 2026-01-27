import 'package:flutter/material.dart';
import '../data/app_data.dart';

class FolderCreationDialog extends StatefulWidget {
  final String parentId;

  const FolderCreationDialog({super.key, required this.parentId});

  @override
  State<FolderCreationDialog> createState() => _FolderCreationDialogState();
}

class _FolderCreationDialogState extends State<FolderCreationDialog> {
  final _controller = TextEditingController();

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      await AppData.createFolder(name: name, parentId: widget.parentId);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva Carpeta'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nombre'),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _create,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}