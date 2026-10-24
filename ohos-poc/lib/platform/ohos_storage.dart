import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

/// Initialize both account and TV-session storage before opening any Hive box.
Future<void> initializeOhosStorage() async {
  const platformChannel = MethodChannel('dev.biliremote/platform');
  final filesDirectory = await platformChannel.invokeMethod<String>(
    'filesDirectory',
  );
  if (filesDirectory == null || filesDirectory.isEmpty) {
    throw StateError('无法读取应用存储目录');
  }
  Hive.init(filesDirectory);
}
