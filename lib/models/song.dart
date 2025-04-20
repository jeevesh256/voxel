import 'dart:io';

class Song {
  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String albumArt;
  final Duration duration;

  const Song({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
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
    );
  }
}
