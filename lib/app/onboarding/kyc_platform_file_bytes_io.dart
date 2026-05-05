import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List?> readPlatformFileBytes(PlatformFile file) async {
  if (file.bytes != null) return file.bytes!;
  final p = file.path;
  if (p == null || p.isEmpty) return null;
  try {
    return File(p).readAsBytes();
  } catch (_) {
    return null;
  }
}
