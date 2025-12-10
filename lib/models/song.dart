import 'dart:io';

class Song {
  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final String albumArt;
  final Duration duration;

  const Song({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    this.album = '',
    this.albumArt = '',
    this.duration = const Duration(minutes: 3),
  });

  factory Song.fromFile(File file) {
    final name = file.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac)$'), '');
    return Song(
      id: file.path,
      filePath: file.path,
      title: name,
      artist: 'Unknown Artist',
      album: '',
    );
  }

  Song copyWith({
    String? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    String? albumArt,
    Duration? duration,
  }) {
    return Song(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArt: albumArt ?? this.albumArt,
      duration: duration ?? this.duration,
    );
  }
}
