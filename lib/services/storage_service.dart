import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class StorageService {
  Future<List<FileSystemEntity>> getAudioFiles() async {
    if (!await _requestPermissions()) {
      throw Exception('Storage permission denied');
    }

    final List<FileSystemEntity> files = [];
    final List<String> musicDirs = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ];

    for (String dir in musicDirs) {
      final directory = Directory(dir);
      if (await directory.exists()) {
        try {
          await for (var entity in directory.list(recursive: true)) {
            if (entity is File && _isAudioFile(entity.path)) {
              files.add(entity);
            }
          }
        } catch (e) {
          debugPrint('Error scanning directory $dir: $e');
        }
      }
    }
    return files;
  }

  bool _isAudioFile(String path) {
    return path.toLowerCase().endsWith('.mp3') || 
           path.toLowerCase().endsWith('.m4a') ||
           path.toLowerCase().endsWith('.wav') ||
           path.toLowerCase().endsWith('.aac') ||
           path.toLowerCase().endsWith('.flac');
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.request();
      final audioStatus = await Permission.audio.request();
      return storageStatus.isGranted || audioStatus.isGranted;
    }
    return true;
  }
}
