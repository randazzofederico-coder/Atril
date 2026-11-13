import 'package:flutter/material.dart';

/// Messenger de la app, para mostrar avisos desde código sin `BuildContext`
/// (p. ej. "Listo: Compartir" al terminar un ZIP en segundo plano).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();
