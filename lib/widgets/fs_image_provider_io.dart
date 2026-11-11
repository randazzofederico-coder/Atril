import 'dart:io';

import 'package:flutter/painting.dart';

ImageProvider? fileImageProvider(String path) => FileImage(File(path));
