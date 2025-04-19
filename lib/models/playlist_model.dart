import 'dart:io';

class PlaylistModel {
  final String id;
  final String name;
  final List<File> songs;
  final bool isSystem;

  const PlaylistModel({
    required this.id,
    required this.name,
    this.songs = const [],
    this.isSystem = false,
  });
}
