import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where a developer tool writes something meant to leave the device.
///
/// Not where practice history goes. These are takes, traces, and reports that
/// are only useful once they reach a computer, so they go somewhere a person
/// can actually reach rather than somewhere the app can.
///
/// The two platforms disagree about where that is. On iOS the app's Documents
/// directory is exactly it, because the app declares file sharing and Files
/// shows it. On Android the same directory is private app storage that no file
/// manager will open, so the tools that wrote there produced files nobody
/// could collect; app-specific external storage is the reachable equivalent,
/// by `adb pull` and by file managers that still browse `Android/data`.
Future<Directory> exportDirectory(String kind) async {
  final base = Platform.isAndroid
      ? await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory()
      : await getApplicationDocumentsDirectory();
  return Directory('${base.path}/$kind')..createSync(recursive: true);
}
