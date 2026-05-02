import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// True when `flutter test` compiles the program (VM has no plugin `sqflite`).
const bool _kFlutterTest = bool.fromEnvironment('FLUTTER_TEST', defaultValue: false);

/// Uses FFI-backed SQLite on Windows and Linux, and in `flutter test` on any
/// host, where the platform `sqflite` implementation is not available.
/// On Flutter Web, [dart:io] [Platform] is unsupported — skip entirely.
void configureSqfliteForPlatform() {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || _kFlutterTest) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
