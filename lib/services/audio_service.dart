import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:io';
import 'playlist_handler.dart';

class AudioPlayerService with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, List<File>> _playlists = {
    'liked': [],
    'offline': [],
  };

  final PlaylistHandler _playlistHandler = PlaylistHandler();
  String? _currentPlaylistId;

  MediaItem? _currentMedia;
  bool _isInitialized = false;

  // Track liked status
  final Set<String> _likedTracks = {};

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

  // Toggle like status for current track
  void toggleLike() {
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
      final playlist = ConcatenatingAudioSource(
        children: songs.map((file) => 
          AudioSource.file(
            file.path,
            tag: MediaItem(
              id: file.path, // Use file path as ID for consistent like tracking
              title: file.path.split('/').last,
              album: playlistId,
            ),
          ),
        ).toList(),
      );

      await _player.setAudioSource(playlist);
      await _player.play();
      notifyListeners();
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

  String? get currentPlaylistName {
    if (_currentPlaylistId == null) return null;
    return _playlistHandler.getPlaylist(_currentPlaylistId!)?.name;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
