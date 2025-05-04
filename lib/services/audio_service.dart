import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';  // Add this import
import '../services/playlist_handler.dart';  // Add this import
import 'dart:io';
import 'package:provider/provider.dart';
import 'queue_manager.dart';
import 'audio_queue_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:math' as math;
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class AudioPlayerService extends ChangeNotifier implements AudioQueueManager {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, List<File>> _playlists = {
    'liked': [],
    'offline': [],
  };
  final PlaylistHandler _playlistHandler;
  final Set<String> _likedTracks = {};
  static const String _likedTracksKey = 'liked_tracks';
  late SharedPreferences _prefs;

  late ConcatenatingAudioSource _playlist;

  AudioPlayerService(this._playlistHandler) {
    _playlist = ConcatenatingAudioSource(children: []);
    _player.setAudioSource(_playlist);

    _playlistHandler.setQueueManager(this);
    _loadLikedTracks();

    // Listen to player index changes and shuffle mode changes
    _player.currentIndexStream.listen((index) {
      if (index != null) notifyListeners();
    });

    _player.shuffleModeEnabledStream.listen((enabled) {
      notifyListeners();
    });
  }

  String? _currentPlaylistId;

  MediaItem? _currentMedia;
  bool _isInitialized = false;

  AudioPlayer get player => _player;
  MediaItem? get currentMedia => _currentMedia;
  bool get isPlaying => _player.playing;

  // Add missing getters
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration? get duration => _player.duration;
  List<MapEntry<String, List<File>>> get allPlaylists => _playlists.entries.toList();

  // Get current track metadata
  MediaItem? get currentTrack {
    final sequence = player.sequence;
    if (sequence == null || sequence.isEmpty) return null;
    return sequence[player.currentIndex ?? 0].tag as MediaItem?;
  }

  // Check if current track is liked
  bool get isLiked {
    final current = currentTrack;
    if (current == null) return false;
    return _likedTracks.contains(current.id);
  }

  Future<void> _loadLikedTracks() async {
    _prefs = await SharedPreferences.getInstance();
    final likedTracks = _prefs.getStringList(_likedTracksKey) ?? [];
    _likedTracks.addAll(likedTracks);
    
    // Sync liked tracks with playlist
    _playlists['liked'] = likedTracks.map((path) => File(path)).toList();
    notifyListeners();
  }

  Future<void> _saveLikedTracks() async {
    await _prefs.setStringList(_likedTracksKey, _likedTracks.toList());
  }

  // Toggle like status for current track
  Future<void> toggleLike() async {
    final current = currentTrack;
    if (current == null) return;

    final currentFile = File(current.id);
    
    if (isLiked) {
      _likedTracks.remove(current.id);
      _playlists['liked']?.removeWhere((file) => file.path == current.id);
    } else {
      if (!(_playlists['liked']?.any((file) => file.path == current.id) ?? false)) {
        _likedTracks.add(current.id);
        _playlists['liked']?.add(currentFile);
      }
    }
    await _saveLikedTracks();
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await _player.setVolume(1.0);
      _setupPlayerListeners();
      _playlistHandler.initializePlaylists();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing: $e');
      rethrow;
    }
  }

  void _setupPlayerListeners() {
    _player.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });

    _player.sequenceStateStream.listen((state) {
      if (state?.currentSource?.tag != null) {
        _currentMedia = state!.currentSource!.tag as MediaItem;
        notifyListeners();
      }
    });
  }

  Future<void> playFile(File file) async {
    try {
      final name = file.path.split('/').last;
      final title = name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
      
      final audioSource = AudioSource.file(
        file.path,
        tag: MediaItem(
          id: file.path, // Use file path as ID for consistent like tracking
          title: title,
          album: 'Local Music',
        ),
      );

      await _player.setAudioSource(audioSource);
      // Wait for duration to be loaded
      await _player.load();
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing file: $e');
    }
  }

  Future<void> seekToPosition(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  // Add missing methods
  Future<void> loadOfflineFiles(List<File> files) async {
    _playlists['offline'] = files;
    notifyListeners();
  }

  List<File> getPlaylistSongs(String playlistId) {
    return _playlists[playlistId] ?? [];
  }

  Future<void> playPlaylist(String playlistId) async {
    _currentPlaylistId = playlistId;
    final songs = _playlists[playlistId];
    if (songs == null || songs.isEmpty) return;

    try {
      final songsList = songs.map((file) => Song.fromFile(file)).toList();
      _playlistHandler.updateQueue(songsList);

      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) => 
          AudioSource.file(
            song.filePath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: playlistId,
            ),
          ),
        ).toList(),
      );

      await _player.setAudioSource(_playlist, initialIndex: 0);
      await _player.play();
    } catch (e) {
      debugPrint('Error playing playlist: $e');
    }
  }

  Future<void> playFiles(List<File> files) async {
    if (files.isEmpty) return;
    try {
      final playlist = ConcatenatingAudioSource(
        children: files.map((file) => 
          AudioSource.file(
            file.path,
            tag: MediaItem(
              id: file.path,
              title: file.path.split('/').last,
            ),
          ),
        ).toList(),
      );

      await _player.setAudioSource(playlist);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing files: $e');
    }
  }

  Future<void> playPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    try {
      if (_player.duration != null) {
        await _player.seek(position);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  Future<void> playQueueItem(int index) async {
    try {
      if (_playlist != null && index >= 0 && index < _playlist.length) {
        await _player.seek(Duration.zero, index: index);
        if (!_player.playing) {
          await _player.play();
        }
      }
    } catch (e) {
      debugPrint('Error playing queue item: $e');
    }
  }

  Future<void> playFileInContext(File file, List<File> playlistFiles) async {
    if (playlistFiles.isEmpty) return;
    try {
      final songsList = playlistFiles.map((f) => Song.fromFile(f)).toList();
      _playlistHandler.updateQueue(songsList);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) => 
          AudioSource.file(
            song.filePath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
            ),
          ),
        ).toList(),
      );

      final selectedIndex = playlistFiles.indexOf(file);
      await _player.setAudioSource(_playlist, initialIndex: selectedIndex);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing file in context: $e');
    }
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    try {
      if (_playlist != null) {
        final currentIndex = _player.currentIndex;
        await _playlist.move(oldIndex, newIndex);
        
        if (currentIndex == oldIndex) {
          await _player.seek(_player.position, index: newIndex);
        }
      }
    } catch (e) {
      debugPrint('Error reordering queue: $e');
    }
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (_playlist == null) return;
    try {
      await _playlist.removeAt(index);
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing from queue: $e');
    }
  }

  @override
  Future<void> addToQueue(Song song) async {
    if (_playlist == null) return;
    try {
      await _playlist.add(AudioSource.file(
        song.filePath,
        tag: MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
        ),
      ));
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding to queue: $e');
    }
  }

  @override
  Future<void> updateQueue(List<Song> songs) async {
    try {
      final sources = songs.map((song) => 
        AudioSource.file(
          song.filePath,
          tag: MediaItem(
            id: song.id,
            title: song.title,
            artist: song.artist,
          ),
        ),
      ).toList();

      await _playlist.clear();
      await _playlist.addAll(sources);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating queue: $e');
    }
  }

  String? get currentPlaylistName {
    if (_currentPlaylistId == null) return null;
    return _playlistHandler.getPlaylist(_currentPlaylistId!)?.name;
  }

  Stream<MediaItem?> get currentMediaStream => Rx.combineLatest2(
    _player.currentIndexStream,
    _player.sequenceStream,
    (index, sequence) {
      if (index == null || sequence == null || sequence.isEmpty) return null;
      return sequence[index].tag as MediaItem?;
    },
  ).distinct();

  Future<void> toggleShuffle() async {
    try {
      final enabled = !_player.shuffleModeEnabled;
      
      if (enabled) {
        // Get current track index and position
        final currentIndex = _player.currentIndex;
        final position = _player.position;
        
        // Enable shuffle mode first
        await _player.setShuffleModeEnabled(true);
        
        // If we have a current track, make sure it stays playing
        if (currentIndex != null) {
          // Get the shuffled index of the current track
          final currentItem = _playlist.sequence[currentIndex];
          final newIndex = _playlist.sequence.indexOf(currentItem);
          
          // Seek to the same position at the new shuffled index
          await _player.seek(position, index: newIndex);
        }
      } else {
        // Simply disable shuffle mode
        await _player.setShuffleModeEnabled(false);
        
        // just_audio will automatically restore the original sequence
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling shuffle: $e');
    }
  }

  Future<void> cycleRepeatMode() async {
    try {
      final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
      final currentIndex = modes.indexOf(_player.loopMode);
      final nextMode = modes[(currentIndex + 1) % modes.length];
      await _player.setLoopMode(nextMode);
      _updateQueueDisplay();
      notifyListeners();
    } catch (e) {
      debugPrint('Error cycling repeat mode: $e');
    }
  }

  void _updateQueueDisplay() {
    // No need to do anything special for now, as the UI automatically
    // updates based on player state changes. This method is kept as a
    // placeholder for future queue display logic if needed.
  }

  // Add getters for current states
  bool get isShuffling => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
