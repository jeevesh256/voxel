import 'dart:io';

class Playlist {
  final String id;
  final String name;
  final List<File> songs;
  final bool isSystem;

  const Playlist({
    required this.id,
    required this.name,
    this.songs = const [],
    this.isSystem = false,
  });

  Playlist copyWith({
    String? name,
    List<File>? songs,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      isSystem: isSystem,
    );
  }
}
