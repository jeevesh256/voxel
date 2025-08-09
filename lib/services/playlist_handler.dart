import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'audio_queue_manager.dart';

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

class PlaylistHandler extends ChangeNotifier {
  AudioQueueManager? _queueManager;
  List<Song> _queue = [];
  List<Song> _originalPlaylist = []; // Keep track of original playlist for repeat
  final Map<String, Playlist> _playlists = {};

  void setQueueManager(AudioQueueManager manager) {
    _queueManager = manager;
  }

  // Queue getters and methods
  List<Song> get queue => List.unmodifiable(_queue);
  List<Song> get originalPlaylist => List.unmodifiable(_originalPlaylist);

  void updateQueue(List<Song> songs) {
    _queue = songs;
    _originalPlaylist = List.from(songs); // Store original for repeat
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (_queueManager != null && index >= 0 && index < _queue.length) {
      await _queueManager!.removeFromQueue(index);
      _queue.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_queueManager != null && oldIndex < _queue.length && newIndex <= _queue.length) {
      if (newIndex > oldIndex) newIndex--;
      
      final song = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, song);
      
      await _queueManager!.reorderQueue(oldIndex, newIndex);
      notifyListeners();
    }
  }

  Future<void> addToQueue(Song song) async {
    if (_queueManager != null) {
      await _queueManager!.addToQueue(song);
      _queue.add(song);
      notifyListeners();
    }
  }

  Future<void> insertAtQueue(Song song, int index) async {
    if (_queueManager != null && index >= 0 && index <= _queue.length) {
      await _queueManager!.insertAtQueue(song, index);
      _queue.insert(index, song);
      notifyListeners();
    }
  }

  // Session-only queue management (doesn't affect original playlist)
  Future<void> removeFromSession(int index) async {
    if (_queueManager != null && index >= 0 && index < _queue.length) {
      await _queueManager!.removeFromQueue(index);
      // Update current session queue but keep original playlist intact
      _queue.removeAt(index);
      notifyListeners();
    }
  }

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
