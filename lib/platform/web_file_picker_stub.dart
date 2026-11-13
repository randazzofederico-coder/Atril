import 'dart:typed_data';

/// Solo existe en web (ver web_file_picker_web.dart).
Future<List<(String, Uint8List)>> pickFilesWeb({
  required String accept,
  bool multiple = false,
  void Function()? onWaiting,
  void Function(int count)? onChosen,
  void Function(int done, int total)? onRead,
}) =>
    throw UnsupportedError('pickFilesWeb solo está disponible en web');

void cancelPendingPick() {}
