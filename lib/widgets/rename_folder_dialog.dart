import 'package:flutter/material.dart';
import '../data/app_data.dart';

class RenameFolderDialog extends StatefulWidget {
  final String folderId;
  final String initialName;

  const RenameFolderDialog({
    super.key, 
    required this.folderId,
    required this.initialName,
  });

  @override
  State<RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<RenameFolderDialog> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final newName = _controller.text.trim();
    if (newName.isEmpty) return;
    
    // Si no cambió el nombre, cerramos sin hacer nada
    if (newName == widget.initialName) {
      Navigator.of(context).pop();
      return;
    }

    final folder = AppData.getFolderById(widget.folderId);
    if (folder == null) return; // Should not happen

    // Validar duplicados inline
    if (AppData.folderNameExists(newName, folder.parentId ?? 'root')) {
       setState(() {
         _errorText = 'Esta carpeta ya existe';
       });
       return;
    }

    // Success
    Navigator.of(context).pop(newName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renombrar carpeta'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Nuevo nombre',
          errorText: _errorText,
        ),
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        onSubmitted: (_) => _rename(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), 
          child: const Text('Cancelar')
        ),
        FilledButton(
          onPressed: _rename, 
          child: const Text('Renombrar')
        ),
      ],
    );
  }
}
