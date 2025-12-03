import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';  // Add this import
import '../services/playlist_handler.dart';  // Add this import
import '../models/radio_station.dart';
import '../models/custom_playlist.dart';
import 'dart:io';
import 'audio_queue_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';


class AudioPlayerService extends ChangeNotifier implements AudioQueueManager {
  /// Returns the type of current media: 'radio', 'song', or null
  String? getCurrentMediaType() {
    final current = currentTrack;
    if (current == null) return null;
    
    // Use isRadioPlaying which checks _currentRadioStation instead of allRadios
    if (isRadioPlaying || _currentRadioStation != null) return 'radio';
    return 'song';
  }
  /// Add the current radio to favourite radios (if not already there)
  void likeCurrentRadio() {
    final current = currentTrack;
    if (current == null) return;
    final allRadios = getPlaylistRadios('all_radios');
    final emptyRadio = RadioStation(id: '', name: '', streamUrl: '', genre: '', artworkUrl: '', country: '');
    final matchedRadio = allRadios.firstWhere(
      (r) => r.id == current.id || r.streamUrl == current.id || r.streamUrl == current.title,
      orElse: () => emptyRadio,
    );
    if (matchedRadio.id.isNotEmpty && !isRadioLiked(matchedRadio)) {
      addRadioToPlaylist('favourite_radios', matchedRadio);
    }
  }
  // Global list of all radios in the app
  List<RadioStation> allRadios = [];
  final AudioPlayer _player = AudioPlayer();
  final Map<String, List<File>> _playlists = {
    'liked': [],
    'offline': [],
  };
  final Map<String, List<RadioStation>> _radioPlaylists = {
    'favourite_radios': [],
  };
  final PlaylistHandler _playlistHandler;
  final List<String> _likedTracks = [];
  final Set<String> _likedRadios = {};
  final Map<String, CustomPlaylist> _customPlaylists = {};
  static const String _likedTracksKey = 'liked_tracks';
  static const String _likedRadiosKey = 'liked_radios';
  static const String _customPlaylistsKey = 'custom_playlists';
  late SharedPreferences _prefs;

  late ConcatenatingAudioSource _playlist;
  
  // Spotify-style dual queue system
  final List<Song> _nextUpQueue = []; // Manually added songs (higher priority)
  bool _isCustomShuffling = false; // Our custom shuffle state
  List<Song> _originalPlaylistSongs = []; // Original playlist order for shuffle/unshuffle
  
  // Getters for queue system
  List<Song> get nextUpQueue => List.unmodifiable(_nextUpQueue);
  
  // Custom shuffle getter (replaces just_audio's shuffle)
  bool get isShuffling => _isCustomShuffling;
  
  // Clean up played next up songs
  void _cleanupPlayedNextUpSongs() {
    if (_nextUpQueue.isEmpty) return;
    
    final currentIndex = _player.currentIndex ?? 0;
    final sequence = _player.sequence;
    if (sequence == null || sequence.isEmpty) return;
    
    // Remove songs from next up queue that have already been played
    // (songs before current index that were marked as "Next Up")
    for (int i = 0; i < currentIndex && i < sequence.length; i++) {
      final mediaItem = sequence[i].tag as MediaItem?;
      if (mediaItem?.album == 'Next Up') {
        // Find and remove this song from the next up queue
        _nextUpQueue.removeWhere((song) => song.id == mediaItem!.id);
      }
    }
  }

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

  RadioStation? _currentRadioStation;
  RadioStation? get currentRadioStation => _currentRadioStation;

  AudioPlayer get player => _player;
  MediaItem? get currentMedia => _currentMedia;
  bool get isPlaying => _player.playing;

  // Add missing getters
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration? get duration => _player.duration;
  List<MapEntry<String, List<File>>> get allPlaylists {
    final allPlaylistEntries = <MapEntry<String, List<File>>>[];
    allPlaylistEntries.addAll(_playlists.entries);
    return allPlaylistEntries;
  }

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
    final type = getCurrentMediaType();
    if (type != 'song') return false;
    return _likedTracks.contains(current.id);
  }


  Future<void> _loadLikedTracks() async {
    _prefs = await SharedPreferences.getInstance();
    final likedTracks = _prefs.getStringList(_likedTracksKey) ?? [];
    _likedTracks.clear();
    _likedTracks.addAll(likedTracks);
    _playlists['liked'] = likedTracks.map((path) => File(path)).toList();

    // Load liked radios (persisted as JSON)
    final likedRadiosJson = _prefs.getStringList(_likedRadiosKey) ?? [];
    _radioPlaylists['favourite_radios'] = likedRadiosJson
        .map((jsonStr) {
          try {
            return RadioStation.fromJson(Map<String, dynamic>.from(
              jsonDecode(jsonStr),
            ));
          } catch (_) {
            return null;
          }
        })
        .whereType<RadioStation>()
        .toList();
    
    // Update liked radios set
    _likedRadios.clear();
    _likedRadios.addAll(_radioPlaylists['favourite_radios']?.map((r) => r.id) ?? []);
    
    // Load custom playlists
    await _loadCustomPlaylists();
    
    notifyListeners();
  }


  Future<void> _saveLikedTracks() async {
    await _prefs.setStringList(_likedTracksKey, _likedTracks);
  }

  Future<void> _saveLikedRadios() async {
    // Save as JSON
    final radios = _radioPlaylists['favourite_radios'] ?? [];
    final jsonList = radios.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_likedRadiosKey, jsonList);
  }
  // RadioStation playlist logic
  List<RadioStation> getPlaylistRadios(String playlistId) {
    if (playlistId == 'all_radios') {
      // Return the global list of all radios
      return allRadios;
    }
    return _radioPlaylists[playlistId] ?? [];
  }

  void addRadioToPlaylist(String playlistId, RadioStation station) {
    debugPrint('Adding radio ${station.name} (${station.id}) to playlist $playlistId');
    final radios = _radioPlaylists.putIfAbsent(playlistId, () => []);
    if (!radios.any((r) => r.id == station.id)) {
      radios.add(station);
      _likedRadios.add(station.id);
      debugPrint('Radio added successfully. Total favourite radios: ${radios.length}');
      _saveLikedRadios();
      notifyListeners();
    } else {
      debugPrint('Radio already exists in playlist');
    }
  }

  void removeRadioFromPlaylist(String playlistId, RadioStation station) {
    debugPrint('Removing radio ${station.name} (${station.id}) from playlist $playlistId');
    final radios = _radioPlaylists[playlistId];
    if (radios != null) {
      radios.removeWhere((r) => r.id == station.id);
      _likedRadios.remove(station.id);
      debugPrint('Radio removed successfully. Total favourite radios: ${radios.length}');
      _saveLikedRadios();
      notifyListeners();
    }
  }

  bool isRadioLiked(RadioStation station) {
    return _likedRadios.contains(station.id);
  }

  // Toggle like status for current track
  Future<void> toggleLike() async {
    final current = currentTrack;
    if (current == null) return;
    final type = getCurrentMediaType();
    if (type != 'song') {
      // Only handle songs here
      return;
    }
    // Song logic only
    final currentFile = File(current.id);
    if (isLiked) {
      _likedTracks.remove(current.id);
      _playlists['liked']?.removeWhere((file) => file.path == current.id);
    } else {
      if (!(_playlists['liked']?.any((file) => file.path == current.id) ?? false)) {
        _likedTracks.insert(0, current.id); // Insert at start for stack order
        _playlists['liked']?.insert(0, currentFile); // Insert at start for stack order
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
        // Only clear _currentRadioStation if the album is not 'Radio'
        // _currentRadioStation is set properly in playRadioStation()
        if (_currentMedia?.album != 'Radio') {
          _currentRadioStation = null;
        }
        
        // Clean up played next up songs
        _cleanupPlayedNextUpSongs();
        
        notifyListeners();
      }
    });
  }

  Future<void> playFile(File file) async {
    try {
      // Clear radio station when playing a song
      _currentRadioStation = null;
      
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
    // Sort files by modification time (recently added first)
    final sortedFiles = List<File>.from(files);
    sortedFiles.sort((a, b) {
      try {
        return b.statSync().modified.compareTo(a.statSync().modified);
      } catch (e) {
        // If we can't get modification time, maintain original order
        return 0;
      }
    });
    
    _playlists['offline'] = sortedFiles;
    
    // If currently playing offline, update the queue
    if (_currentPlaylistId == 'offline') {
      final songsList = sortedFiles.map((file) => Song.fromFile(file)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: 'offline');
    }
    
    notifyListeners();
  }

  List<File> getPlaylistSongs(String playlistId) {
    return _playlists[playlistId] ?? [];
  }

  Future<void> playPlaylist(String playlistId) async {
    // Clear radio station when playing a playlist
    _currentRadioStation = null;
    _currentPlaylistId = playlistId;
    final songs = _playlists[playlistId];
    if (songs == null || songs.isEmpty) return;

    try {
      final songsList = songs.map((file) => Song.fromFile(file)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: playlistId);

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

      // Ensure shuffle is disabled when playing playlist in order
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: 0);
      await _player.play();
    } catch (e) {
      debugPrint('Error playing playlist: $e');
    }
  }

  Future<void> playFilteredPlaylist(String playlistId, List<File> filteredSongs, {int initialIndex = 0}) async {
    if (filteredSongs.isEmpty) return;
    
    try {
      // Clear radio station when playing a playlist
      _currentRadioStation = null;
      _currentPlaylistId = playlistId;

      final songsList = filteredSongs.map((f) => Song.fromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: playlistId);
      
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

      // Ensure shuffle is disabled when playing playlist in order
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: initialIndex);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing filtered playlist: $e');
    }
  }

  Future<void> playFiles(List<File> files) async {
    if (files.isEmpty) return;
    try {
      // Clear radio station when playing files
      _currentRadioStation = null;
      
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
      if (index >= 0 && index < _playlist.length) {
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
      // Clear radio station when playing songs
      _currentRadioStation = null;
      
      // Set current playlist by comparing contents exactly
      for (var entry in _playlists.entries) {
        if (listEquals(entry.value, playlistFiles)) {
          _currentPlaylistId = entry.key;
          break;
        }
      }

      // If playlist not found, assume it's the offline playlist
      _currentPlaylistId ??= 'offline';

      final songsList = playlistFiles.map((f) => Song.fromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: _currentPlaylistId);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) => 
          AudioSource.file(
            song.filePath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: _currentPlaylistId, // Use the identified playlist ID
            ),
          ),
        ).toList(),
      );

      final selectedIndex = playlistFiles.indexOf(file);
      // Ensure shuffle is disabled when playing from playlist
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: selectedIndex);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing file in context: $e');
    }
  }

  Future<void> playFileInContextWithPlaylistId(File file, List<File> playlistFiles, String playlistId) async {
    if (playlistFiles.isEmpty) return;
    try {
      // Clear radio station when playing songs
      _currentRadioStation = null;
      _currentPlaylistId = playlistId;

      final songsList = playlistFiles.map((f) => Song.fromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: _currentPlaylistId);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) => 
          AudioSource.file(
            song.filePath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: _currentPlaylistId,
            ),
          ),
        ).toList(),
      );

      final selectedIndex = playlistFiles.indexOf(file);
      // Ensure shuffle is disabled when playing from playlist
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: selectedIndex);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing file in context: $e');
    }
  }

  @override
  Future<void> removeFromQueue(int index) async {
    try {
      // Remove from the concatenated source
      await _playlist.removeAt(index);
      
      // Also remove from next up queue if it's a manually added song
      final currentIndex = _player.currentIndex ?? 0;
      if (index > currentIndex && index <= currentIndex + _nextUpQueue.length) {
        final nextUpIndex = index - currentIndex - 1;
        if (nextUpIndex >= 0 && nextUpIndex < _nextUpQueue.length) {
          _nextUpQueue.removeAt(nextUpIndex);
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing from queue: $e');
    }
  }

  @override
  Future<void> addToQueue(Song song) async {
    try {
      // Add to next up queue and audio source
      _nextUpQueue.add(song);
      
      // Get current index to insert after current song
      final currentIndex = _player.currentIndex ?? 0;
      final insertIndex = currentIndex + 1;

      // Create audio source for the song with special marker for manually added
      final audioSource = AudioSource.file(
        song.filePath,
        tag: MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: 'Next Up', // Special marker for manually added songs
        ),
      );

      // Insert the song right after the current song in the audio player
      await _playlist.insert(insertIndex, audioSource);
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding to queue: $e');
    }
  }

  @override
  Future<void> insertAtQueue(Song song, int index) async {
    try {
      // Add to next up queue
      _nextUpQueue.insert(index - (_player.currentIndex ?? 0) - 1, song);

      await _playlist.insert(index, AudioSource.file(
        song.filePath,
        tag: MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: 'Next Up', // Special marker for manually added songs
        ),
      ));
      notifyListeners();
    } catch (e) {
      debugPrint('Error inserting to queue: $e');
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
            album: _currentPlaylistId, // Preserve playlist context
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

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    try {
      final currentIndex = _player.currentIndex;
      
      // Check if we're reordering within the Next Up section
      final nextUpStartIndex = (currentIndex ?? 0) + 1;
      final nextUpEndIndex = nextUpStartIndex + _nextUpQueue.length;
      
      if (oldIndex >= nextUpStartIndex && oldIndex < nextUpEndIndex &&
          newIndex >= nextUpStartIndex && newIndex < nextUpEndIndex) {
        // Reordering within Next Up - update our Next Up queue
        final nextUpOldIndex = oldIndex - nextUpStartIndex;
        final nextUpNewIndex = newIndex - nextUpStartIndex;
        
        if (nextUpOldIndex >= 0 && nextUpOldIndex < _nextUpQueue.length &&
            nextUpNewIndex >= 0 && nextUpNewIndex < _nextUpQueue.length) {
          // Update the Next Up queue data structure
          final song = _nextUpQueue.removeAt(nextUpOldIndex);
          _nextUpQueue.insert(nextUpNewIndex, song);
        }
      }
      
      // Update the audio playlist
      await _playlist.move(oldIndex, newIndex);
      
      if (currentIndex == oldIndex) {
        await _player.seek(_player.position, index: newIndex);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error reordering queue: $e');
    }
  }

  String? get currentPlaylistName {
    if (_currentPlaylistId == null) return null;
    
    // Map playlist IDs to display names
    final playlistNames = {
      'liked': 'Liked Songs',
      'offline': 'Offline',
      // Add other playlist mappings here
    };
    
    return playlistNames[_currentPlaylistId] ?? 'Library';
  }

  String? get currentPlaylistId => _currentPlaylistId;

  Stream<MediaItem?> get currentMediaStream => Rx.combineLatest2(
    _player.currentIndexStream,
    _player.sequenceStream,
    (index, sequence) {
      if (index == null || sequence == null || sequence.isEmpty) return null;
      return sequence[index].tag as MediaItem?;
    },
  ).distinct().asBroadcastStream();

  Future<void> toggleShuffle() async {
    try {
      _isCustomShuffling = !_isCustomShuffling;
      
      // Always disable just_audio's built-in shuffle to prevent conflicts
      await _player.setShuffleModeEnabled(false);
      
      // Rebuild the queue with our custom shuffle logic
      await _rebuildQueueWithCustomShuffle();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling custom shuffle: $e');
    }
  }
  
  Future<void> _rebuildQueueWithCustomShuffle() async {
    try {
      final currentIndex = _player.currentIndex ?? 0;
      final currentPosition = _player.position;
      final sequence = _player.sequence;
      
      if (sequence == null || sequence.isEmpty) return;
      
      // Create lists to hold indices instead of AudioSources
      List<int> nextUpIndices = [];
      List<int> laterIndices = [];
      
      // Separate Next Up and Later songs by index
      for (int i = currentIndex + 1; i < sequence.length; i++) {
        final mediaItem = sequence[i].tag as MediaItem?;
        
        if (mediaItem?.album == 'Next Up') {
          nextUpIndices.add(i);
        } else {
          laterIndices.add(i);
        }
      }
      
      // Store original order for later songs if we don't have it
      if (_originalPlaylistSongs.isEmpty && laterIndices.isNotEmpty) {
        _originalPlaylistSongs = laterIndices.map((index) {
          final mediaItem = sequence[index].tag as MediaItem?;
          return Song(
            id: mediaItem!.id,
            title: mediaItem.title,
            artist: mediaItem.artist ?? 'Unknown Artist',
            filePath: mediaItem.id,
          );
        }).toList();
      }
      
      // Apply shuffle only to Later song indices
      if (_isCustomShuffling && laterIndices.isNotEmpty) {
        laterIndices.shuffle();
      }
      
      // Create new sources list
      List<UriAudioSource> newSources = [];
      
      // Add current song
      final currentMediaItem = sequence[currentIndex].tag as MediaItem?;
      if (currentMediaItem != null) {
        newSources.add(AudioSource.file(
          currentMediaItem.id,
          tag: currentMediaItem,
        ));
      }
      
      // Add Next Up songs (in original order)
      for (int index in nextUpIndices) {
        final mediaItem = sequence[index].tag as MediaItem?;
        if (mediaItem != null) {
          newSources.add(AudioSource.file(
            mediaItem.id,
            tag: mediaItem,
          ));
        }
      }
      
      // Add Later songs (shuffled or original order)
      if (_isCustomShuffling) {
        // Use shuffled indices
        for (int index in laterIndices) {
          final mediaItem = sequence[index].tag as MediaItem?;
          if (mediaItem != null) {
            newSources.add(AudioSource.file(
              mediaItem.id,
              tag: mediaItem,
            ));
          }
        }
      } else {
        // Restore original order from stored songs
        for (Song song in _originalPlaylistSongs) {
          newSources.add(AudioSource.file(
            song.filePath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: _currentPlaylistId ?? 'Local Music',
            ),
          ));
        }
      }
      
      // Update the playlist
      await _playlist.clear();
      await _playlist.addAll(newSources);
      
      // Seek back to current position at index 0
      await _player.seek(currentPosition, index: 0);
      
    } catch (e) {
      debugPrint('Error rebuilding queue with custom shuffle: $e');
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
  LoopMode get loopMode => _player.loopMode;

  Future<void> playRadioStation(RadioStation station) async {
    try {
      _currentRadioStation = station;
      _currentPlaylistId = null;
      _currentMedia = null;
      await _player.setAudioSource(AudioSource.uri(Uri.parse(station.streamUrl),
        tag: MediaItem(
          id: station.id,
          title: station.name,
          artist: station.genre,
          artUri: Uri.parse(station.artworkUrl),
          album: 'Radio',
        ),
      ));
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing radio: $e');
    }
  }

  // isRadioPlaying now checks if currentRadioStation is set
  bool get isRadioPlaying {
    return _currentRadioStation != null;
  }

  // Custom Playlist Management
  List<CustomPlaylist> get customPlaylists => _customPlaylists.values.toList();

  Future<CustomPlaylist> createCustomPlaylist(String name, {String? artworkPath, int? artworkColor}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final playlist = CustomPlaylist(
      id: id,
      name: name,
      artworkPath: artworkPath,
      artworkColor: artworkColor,
      songPaths: [],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    
    _customPlaylists[id] = playlist;
    await _saveCustomPlaylists();
    notifyListeners();
    return playlist;
  }

  Future<void> deleteCustomPlaylist(String playlistId) async {
    _customPlaylists.remove(playlistId);
    _playlists.remove(playlistId);
    await _saveCustomPlaylists();
    notifyListeners();
  }

  Future<void> updateCustomPlaylist(String playlistId, {String? name, String? artworkPath}) async {
    final playlist = _customPlaylists[playlistId];
    if (playlist != null) {
      _customPlaylists[playlistId] = playlist.copyWith(
        name: name,
        artworkPath: artworkPath,
        modifiedAt: DateTime.now(),
      );
      await _saveCustomPlaylists();
      notifyListeners();
    }
  }

  Future<void> addSongToCustomPlaylist(String playlistId, File song) async {
    final playlist = _customPlaylists[playlistId];
    if (playlist != null) {
      final updatedSongPaths = List<String>.from(playlist.songPaths);
      if (!updatedSongPaths.contains(song.path)) {
        updatedSongPaths.insert(0, song.path); // Insert at start for recently added order
        _customPlaylists[playlistId] = playlist.copyWith(
          songPaths: updatedSongPaths,
          modifiedAt: DateTime.now(),
        );
        
        // Update the runtime playlist
        _playlists[playlistId] = updatedSongPaths.map((path) => File(path)).toList();
        
        await _saveCustomPlaylists();
        notifyListeners();
      }
    }
  }

  Future<void> removeSongFromCustomPlaylist(String playlistId, File song) async {
    final playlist = _customPlaylists[playlistId];
    if (playlist != null) {
      final updatedSongPaths = List<String>.from(playlist.songPaths);
      updatedSongPaths.remove(song.path);
      _customPlaylists[playlistId] = playlist.copyWith(
        songPaths: updatedSongPaths,
        modifiedAt: DateTime.now(),
      );
      
      // Update the runtime playlist
      _playlists[playlistId] = updatedSongPaths.map((path) => File(path)).toList();
      
      await _saveCustomPlaylists();
      notifyListeners();
    }
  }

  CustomPlaylist? getCustomPlaylist(String playlistId) {
    return _customPlaylists[playlistId];
  }

  Future<void> _loadCustomPlaylists() async {
    final playlistsJson = _prefs.getStringList(_customPlaylistsKey) ?? [];
    _customPlaylists.clear();
    
    for (final json in playlistsJson) {
      try {
        final playlist = CustomPlaylist.fromJson(jsonDecode(json));
        _customPlaylists[playlist.id] = playlist;
        // Load songs into runtime playlists
        _playlists[playlist.id] = playlist.songPaths.map((path) => File(path)).toList();
      } catch (e) {
        debugPrint('Error loading custom playlist: $e');
      }
    }
  }

  Future<void> _saveCustomPlaylists() async {
    final playlistsJson = _customPlaylists.values
        .map((playlist) => jsonEncode(playlist.toJson()))
        .toList();
    await _prefs.setStringList(_customPlaylistsKey, playlistsJson);
  }

  @override
  void dispose() {
    _currentRadioStation = null;
    _player.dispose();
    super.dispose();
  }
}
