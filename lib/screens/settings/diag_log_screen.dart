import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/diag_log.dart';

/// Ajustes → Acerca de → Registro de diagnóstico.
class DiagLogScreen extends StatelessWidget {
  const DiagLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de diagnóstico'),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: DiagLog.text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Registro copiado')),
                );
              }
            },
          ),
          IconButton(tooltip: 'Borrar', icon: const Icon(Icons.delete_outline), onPressed: DiagLog.clear),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: DiagLog.revision,
        builder: (context, _, __) {
          final text = DiagLog.text;
          if (text.isEmpty) return const Center(child: Text('Todavía no hay nada registrado.'));
          return SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          );
        },
      ),
    );
  }
}
