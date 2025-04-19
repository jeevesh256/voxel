import 'dart:io';
import 'package:flutter/foundation.dart';

class Playlist {
  final String id;
  final String name;
  List<File> songs;
  final bool isSystem;

  Playlist({
    required this.id,
    required this.name,
    this.songs = const [],
    this.isSystem = false,
  });
}

class PlaylistHandler {
  final Map<String, Playlist> _playlists = {};

  void initializePlaylists() {
    _playlists['liked'] = Playlist(
      id: 'liked',
      name: 'Liked Songs',
      isSystem: true,
    );
    _playlists['offline'] = Playlist(
      id: 'offline',
      name: 'Offline',
      isSystem: true,
    );
  }

  void updatePlaylist(String id, List<File> songs) {
    if (_playlists.containsKey(id)) {
      _playlists[id]!.songs = songs;
    }
  }

  Playlist? getPlaylist(String id) => _playlists[id];
  List<Playlist> get allPlaylists => _playlists.values.toList();
}
