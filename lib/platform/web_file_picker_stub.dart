import 'picked_file.dart';

/// Solo existe en web (ver web_file_picker_web.dart).
Future<List<PickedFile>> pickFilesWeb({
  required String accept,
  bool multiple = false,
  void Function()? onWaiting,
}) =>
    throw UnsupportedError('pickFilesWeb solo está disponible en web');

void cancelPendingPick() {}
