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
  final Map<String, Playlist> _playlists = {};

  void setQueueManager(AudioQueueManager manager) {
    _queueManager = manager;
  }

  // Queue getters and methods
  List<Song> get queue => List.unmodifiable(_queue);

  // Get the current queue - for Spotify-like behavior, this should match the playlist order
  List<Song> getEffectiveQueue(String? playlistId) {
    return queue; // The queue should always reflect the current playlist order
  }

  void updateQueue(List<Song> songs, {String? playlistContext}) {
    _queue = songs;
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (_queueManager != null && index >= 0 && index < _queue.length) {
      await _queueManager!.removeFromQueue(index);
      _queue.removeAt(index);
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

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    // Validate indices
    if (oldIndex < 0 || oldIndex >= _queue.length || 
        newIndex < 0 || newIndex > _queue.length ||
        oldIndex == newIndex) {
      return;
    }
    
    // Adjust newIndex for list operations
    if (newIndex > oldIndex) newIndex--;

    try {
      final song = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, song);

      // Update the audio player queue to reflect the new order
      if (_queueManager != null) {
        await _queueManager!.reorderQueue(oldIndex, newIndex);
      }

      notifyListeners();
    } catch (e) {
      // If reordering fails, try to restore the original state
      debugPrint('Error reordering queue: $e');
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

  Future<void> removeFromSession(int index) async {
    if (index >= 0 && index < _queue.length) {
      try {
        _queue.removeAt(index);

        // Update the audio player queue
        if (_queueManager != null) {
          await _queueManager!.removeFromQueue(index);
        }

        notifyListeners();
      } catch (e) {
        debugPrint('Error removing from session at index $index: $e');
        // Refresh the queue from the audio player in case of inconsistency
        notifyListeners();
      }
    }
  }

  Future<void> removeSongFromSession(String songId) async {
    try {
      final songIndex = _queue.indexWhere((song) => song.id == songId);
      if (songIndex >= 0) {
        await removeFromSession(songIndex);
      }
    } catch (e) {
      debugPrint('Error removing song $songId from session: $e');
      notifyListeners();
    }
  }
}
