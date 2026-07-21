import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';  // Add this import
import '../services/playlist_handler.dart';  // Add this import
import '../models/radio_station.dart';
import '../models/custom_playlist.dart';
import '../models/recently_played_item.dart';
import 'dart:io';
import 'audio_queue_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'song_metadata_cache.dart';
import 'storage_service.dart';


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
  final List<String> _hiddenTracks = [];
  final Set<String> _likedRadios = {};
  final List<String> _hiddenRadios = [];
  final Map<String, CustomPlaylist> _customPlaylists = {};
  static const String _likedTracksKey = 'liked_tracks';
  static const String _hiddenTracksKey = 'hidden_tracks';
  static const String _likedRadiosKey = 'liked_radios';
  static const String _hiddenRadiosKey = 'hidden_radios';
  static const String _customPlaylistsKey = 'custom_playlists';
  static const String _recentlyPlayedKey = 'recently_played_playlists';
  late SharedPreferences _prefs;
  final SongMetadataCache _metadataCache = SongMetadataCache();

  int _playSessionId = 0;
  late ConcatenatingAudioSource _playlist;
  
  // BehaviorSubject that caches the last known valid duration.
  // Unlike a stream getter, BehaviorSubject replays the last value to new
  // subscribers immediately — so widget rebuilds after queue changes always
  // receive the correct duration without waiting for durationStream to re-emit.
  final BehaviorSubject<Duration> _durationSubject = BehaviorSubject.seeded(Duration.zero);

  // BehaviorSubject that caches the last known current media track/station.
  // Replays the current media instantly to new subscribers.
  final BehaviorSubject<MediaItem?> _currentMediaSubject = BehaviorSubject.seeded(null);

  // PublishSubject for radio playback errors — fires once per failure, no replay.
  final PublishSubject<String> _radioErrorSubject = PublishSubject<String>();

  /// Stream of user-facing radio error messages.
  /// Listen to this at the top-level scaffold to show toasts.
  Stream<String> get radioErrorStream => _radioErrorSubject.stream;

  /// Tracks whether ExoPlayer has emitted a real (file-parsed) duration for
  /// the current song. Resets when the song changes. Used to reject
  /// 180000ms tag re-emissions that occur after queue structural changes.
  bool _durationConfirmedReal = false;

  /// Tracks whether radio was actively playing, used to detect stream drops.
  bool _radioWasPlaying = false;

  /// A stable duration stream. Always emits the last known good duration;
  /// never regresses to Duration.zero or null during queue modifications.
  Stream<Duration> get stableDurationStream => _durationSubject.stream;
  
  // Spotify-style dual queue system
  final List<Song> _nextUpQueue = []; // Manually added songs (higher priority)
  bool _isCustomShuffling = false; // Our custom shuffle state
  
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
    _metadataCache.initialize();
    _initOfflineFiles();
    _loadLikedTracks();
    _loadRecentlyPlayed();

    // Reset confirmation flag when song changes so new songs start fresh
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        _durationConfirmedReal = false; // New song — treat next 180000ms as tag estimate, not rejection target
        notifyListeners();
      }
    });

    _player.shuffleModeEnabledStream.listen((enabled) {
      notifyListeners();
    });

    _player.playerStateStream.listen((state) {
      notifyListeners();
    });

    // Feed valid durations into the BehaviorSubject.
    // ExoPlayer emits the MediaItem tag duration (180000ms default) as a pre-estimate
    // before parsing the actual file. On queue changes (move/insert), it re-emits
    // 180000ms, overwriting the real duration. We reject those re-emissions once
    // a real (non-180000ms) duration has been confirmed for the current song.
    _player.durationStream.listen((d) {
      if (d != null && d != Duration.zero) {
        final isTagDefault = d.inMilliseconds == 180000;
        if (!isTagDefault) {
          // Real file-parsed duration — accept and mark confirmed
          _durationConfirmedReal = true;
          _durationSubject.add(d);
        } else if (!_durationConfirmedReal) {
          // Still waiting for real duration — accept tag estimate temporarily
          _durationSubject.add(d);
        }
        // else: 180000ms after a real duration → queue change artifact, silently ignored
      } else {
        // null/zero (e.g. brief during structural queue change) → hold last good value
        final current = _durationSubject.valueOrNull;
        if (current != null && current != Duration.zero) {
          _durationSubject.add(current);
        }
      }
    });

    // Listen to changes that affect the currently playing track metadata and update subject
    _player.currentIndexStream.listen((_) => _updateCurrentMediaSubject());
    _player.sequenceStream.listen((_) => _updateCurrentMediaSubject());
    _player.durationStream.listen((_) => _updateCurrentMediaSubject());
    _player.positionStream.listen((_) => _updateCurrentMediaSubject());
  }

  void _updateCurrentMediaSubject() {
    final track = currentTrack;
    if (_currentMediaSubject.value != track) {
      _currentMediaSubject.add(track);
    }
  }
  Future<void> _loadRecentlyPlayed() async {
    _prefs = await SharedPreferences.getInstance();
    final cached = _prefs.getStringList(_recentlyPlayedKey) ?? [];
    _recentlyPlayedItems.clear();
    for (final itemJson in cached) {
      try {
        _recentlyPlayedItems.add(RecentlyPlayedItem.fromJson(jsonDecode(itemJson)));
      } catch (e) {
        debugPrint('Error loading recently played item: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _saveRecentlyPlayed() async {
    final encoded = _recentlyPlayedItems.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_recentlyPlayedKey, encoded);
  }

  String? _currentPlaylistId;
  String? _currentArtistName;
  String? get currentArtistName => _currentArtistName;

  MediaItem? _currentMedia;

  RadioStation? _currentRadioStation;
  RadioStation? get currentRadioStation => _currentRadioStation;

  AudioPlayer get player => _player;
  MediaItem? get currentMedia => _currentMedia;
  bool get isPlaying => _player.playing;
  bool _hasPlayedOnce = false;
  bool get isMiniPlayerVisible {
    return (currentMedia ?? currentTrack) != null || _currentRadioStation != null;
  }

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
    if (sequence == null || sequence.isEmpty) {
      if (_currentMedia != null) {
        final activeDur = player.duration ?? _currentMedia!.duration;
        if (activeDur != null && activeDur != Duration.zero) {
          return _currentMedia!.copyWith(duration: activeDur);
        }
      }
      return _currentMedia;
    }

    final currentIndex = player.currentIndex;
    if (currentIndex == null || currentIndex < 0 || currentIndex >= sequence.length) {
      if (_currentMedia != null) {
        final activeDur = player.duration ?? _currentMedia!.duration;
        if (activeDur != null && activeDur != Duration.zero) {
          return _currentMedia!.copyWith(duration: activeDur);
        }
      }
      return _currentMedia;
    }

    final item = sequence[currentIndex].tag as MediaItem?;
    if (item != null) {
      // Cross-reference with metadata cache for any edited tags
      final cached = _metadataCache.getMetadata(item.id);
      var displayItem = item;
      if (cached != null) {
        final cachedTitle = cached['title'] as String?;
        final cachedArtist = cached['artist'] as String?;
        final cachedAlbum = cached['album'] as String?;
        final cachedAlbumArt = cached['albumArt'] as String?;

        Uri? artUri;
        if (cachedAlbumArt != null && cachedAlbumArt.isNotEmpty) {
          if (cachedAlbumArt.startsWith('http://') || cachedAlbumArt.startsWith('https://')) {
            artUri = Uri.parse(cachedAlbumArt);
          } else {
            final artFile = File(cachedAlbumArt);
            if (artFile.existsSync()) {
              artUri = Uri.file(cachedAlbumArt);
            }
          }
        }
        displayItem = item.copyWith(
          title: cachedTitle ?? item.title,
          artist: cachedArtist ?? item.artist,
          album: (cachedAlbum != null && cachedAlbum.isNotEmpty) ? cachedAlbum : item.album,
          artUri: artUri ?? item.artUri,
        );
      }

      // If the duration is missing, zero, or exactly equal to the 3-minute fallback (180,000ms),
      // override it with the actual loaded player duration.
      final itemDurationMs = displayItem.duration?.inMilliseconds ?? 0;
      final needsOverride = itemDurationMs == 0 || itemDurationMs == 180000;
      final activeDuration = needsOverride ? (player.duration ?? displayItem.duration) : (displayItem.duration ?? player.duration);
      
      if (activeDuration != null && activeDuration != Duration.zero) {
        return displayItem.copyWith(duration: activeDuration);
      }
      return displayItem;
    }
    return item ?? _currentMedia;
  }

  // Check if current track is liked
  bool get isLiked {
    final current = currentTrack;
    if (current == null) return false;
    final type = getCurrentMediaType();
    if (type != 'song') return false;
    return _likedTracks.contains(current.id);
  }

  /// Check if any file path is in the liked playlist.
  bool isFileLiked(String path) => _likedTracks.contains(path);


  Future<void> _initOfflineFiles() async {
    try {
      final storageService = StorageService();
      final entities = await storageService.getAudioFiles();
      
      _prefs = await SharedPreferences.getInstance();
      final hiddenList = _prefs.getStringList(_hiddenTracksKey) ?? [];
      _hiddenTracks.clear();
      _hiddenTracks.addAll(hiddenList);

      final files = entities
          .whereType<File>()
          .where((file) => !_hiddenTracks.contains(file.path))
          .toList();
      
      // Sort files by modification time (recently added first)
      files.sort((a, b) {
        try {
          return b.statSync().modified.compareTo(a.statSync().modified);
        } catch (e) {
          return 0;
        }
      });
      
      _playlists['offline'] = files;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading offline files: $e');
    }
  }

  Future<void> _loadLikedTracks() async {
    _prefs = await SharedPreferences.getInstance();
    final likedTracks = _prefs.getStringList(_likedTracksKey) ?? [];
    _likedTracks.clear();
    _likedTracks.addAll(likedTracks);
    _playlists['liked'] = likedTracks.map((path) => File(path)).toList();

    final hiddenTracks = _prefs.getStringList(_hiddenTracksKey) ?? [];
    _hiddenTracks.clear();
    _hiddenTracks.addAll(hiddenTracks);

    final hiddenRadios = _prefs.getStringList(_hiddenRadiosKey) ?? [];
    _hiddenRadios.clear();
    _hiddenRadios.addAll(hiddenRadios);

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
      // Return the global list of all radios excluding hidden ones
      return allRadios.where((r) => !_hiddenRadios.contains(r.id)).toList();
    }
    final list = _radioPlaylists[playlistId] ?? [];
    return list.where((r) => !_hiddenRadios.contains(r.id)).toList();
  }

  void hideRadioStation(RadioStation station) async {
    if (!_hiddenRadios.contains(station.id)) {
      _hiddenRadios.add(station.id);
      await _prefs.setStringList(_hiddenRadiosKey, _hiddenRadios);
      // Remove from favorites if hidden
      removeRadioFromPlaylist('favourite_radios', station);
      notifyListeners();
    }
  }

  void unhideRadioStation(RadioStation station) async {
    if (_hiddenRadios.remove(station.id)) {
      await _prefs.setStringList(_hiddenRadiosKey, _hiddenRadios);
      notifyListeners();
    }
  }

  bool isRadioHidden(String stationId) {
    return _hiddenRadios.contains(stationId);
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
  /// Toggle liked state for any file by path (not just currently playing).
  Future<void> toggleLikeFile(String path) async {
    if (_likedTracks.contains(path)) {
      _likedTracks.remove(path);
      _playlists['liked']?.removeWhere((f) => f.path == path);
    } else {
      _likedTracks.insert(0, path);
      _playlists['liked']?.insert(0, File(path));
    }
    await _saveLikedTracks();
    notifyListeners();
  }

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
        // Only pause+seek when the entire queue is done (last item).
        // For network streams, just_audio may briefly fire 'completed' while
        // buffering the next track — guard against that by checking the index.
        final index = _player.currentIndex ?? 0;
        final length = _player.sequence?.length ?? 1;
        final isLastTrack = (index >= length - 1);
        if (isLastTrack) {
          _player.pause();
          _player.seek(Duration.zero, index: 0);
        }
      }
    });

    _player.sequenceStateStream.listen((state) {
      if (state?.currentSource?.tag != null) {
        final tag = state!.currentSource!.tag as MediaItem;
        _currentMedia = tag;
        _currentMediaSubject.add(tag);

        // Only clear _currentRadioStation if the album is not 'Radio'
        if (_currentMedia?.album != 'Radio') {
          _currentRadioStation = null;
        }
        _cleanupPlayedNextUpSongs();
        notifyListeners();
      }
    });
  }

  AudioSource _buildAudioSource(String path, MediaItem tag) {
    final trimmedPath = path.trim();
    if (trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://')) {
      return AudioSource.uri(Uri.parse(trimmedPath), tag: tag);
    }
    return AudioSource.file(trimmedPath, tag: tag);
  }

  Future<void> playFile(File file) async {
    try {
      // Clear radio station when playing a song
      _currentRadioStation = null;
      
      final name = file.path.split('/').last;
      final title = name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
      final isRemote = file.path.startsWith('http://') || file.path.startsWith('https://');
      
      final audioSource = _buildAudioSource(
        file.path,
        MediaItem(
          id: file.path, // Use file path as ID for consistent like tracking
          title: title,
          album: isRemote ? 'Network Stream' : 'Local Music',
        ),
      );

      await _player.setAudioSource(audioSource, initialPosition: Duration.zero);
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
    final filtered = files.where((f) => !_hiddenTracks.contains(f.path)).toList();
    // Sort files by modification time (recently added first)
    final sortedFiles = List<File>.from(filtered);
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
      final songsList = sortedFiles.map((file) => _metadataCache.createSongFromFile(file)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: 'offline');
    }
    
    notifyListeners();
  }

  List<File> getPlaylistSongs(String playlistId) {
    return _playlists[playlistId] ?? [];
  }

  String _normalizeArtistToken(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[]\s*(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\s*[\)\]]', caseSensitive: false),
      '',
    ).trim();
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\b', caseSensitive: false),
      '',
    ).trim();
    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s\(\[\{]+|[\s\)\]\}\.,;:!]+$'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[\)\]\}]?\s*\[.*|[\)\]\}]?\s*\(.*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(.*?\) $'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[.*?\] $'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'unknown artist') {
      return '';
    }
    return cleaned;
  }

  List<String> _splitCompoundArtists(String rawArtist) {
    return rawArtist
        .split(RegExp(r'\s*,\s*|\s*&\s*|\s+(?:feat\.?|ft\.?|x)\s+', caseSensitive: false))
        .map(_normalizeArtistToken)
        .where((a) => a.isNotEmpty)
        .toList();
  }

  List<String> _extractFeaturedArtistsFromTitle(String title) {
    final featured = <String>[];
    final bracketedFeat = RegExp(
      r'\((?:feat\.?|ft\.?)\s+([^\)]+)\)|\[(?:feat\.?|ft\.?)\s+([^\]]+)\]',
      caseSensitive: false,
    );
    for (final match in bracketedFeat.allMatches(title)) {
      final names = (match.group(1) ?? match.group(2) ?? '').trim();
      if (names.isEmpty) continue;
      featured.addAll(_splitCompoundArtists(names));
    }
    final inlineFeat = RegExp(r'\b(?:feat\.?|ft\.?)\s+(.+)$', caseSensitive: false)
        .firstMatch(title)
        ?.group(1)
        ?.trim();
    if (inlineFeat != null && inlineFeat.isNotEmpty) {
      featured.addAll(_splitCompoundArtists(inlineFeat));
    }
    final unique = <String, String>{};
    for (final name in featured) {
      final normalized = _normalizeArtistToken(name);
      if (normalized.isEmpty) continue;
      unique.putIfAbsent(normalized.toLowerCase(), () => normalized);
    }
    return unique.values.toList();
  }

  List<File> getSongsByArtist(String artistName) {
    final audioFiles = getPlaylistSongs('offline');
    final result = <File>[];
    final targetTokens = _splitCompoundArtists(artistName).map((s) => s.toLowerCase()).toSet();
    if (targetTokens.isEmpty) return [];

    for (var file in audioFiles) {
      final song = _metadataCache.createSongFromFile(file);
      final rawArtist = song.artist;
      if (rawArtist == 'Unknown Artist' || rawArtist.isEmpty) continue;

      final songArtists = [
        ..._splitCompoundArtists(rawArtist),
        ..._extractFeaturedArtistsFromTitle(song.title),
      ].map((s) => s.toLowerCase()).toSet();

      if (songArtists.intersection(targetTokens).isNotEmpty) {
        result.add(file);
      }
    }
    return result;
  }

  String? getArtistArtwork(String artistName) {
    final songs = getSongsByArtist(artistName);
    for (var file in songs) {
      final song = _metadataCache.createSongFromFile(file);
      if (song.albumArt.isNotEmpty && !song.albumArt.startsWith('http') && File(song.albumArt).existsSync()) {
        return song.albumArt;
      }
    }
    return null;
  }

  Future<void> playPlaylist(String playlistId) async {
    // Clear radio station when playing a playlist
    _currentRadioStation = null;
    _currentArtistName = null;
    _currentPlaylistId = playlistId;
    final songs = _playlists[playlistId];
    if (songs == null || songs.isEmpty) return;

    try {
      final songsList = songs.map((file) => _metadataCache.createSongFromFile(file)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: playlistId);

      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) {
          final isRemote = song.filePath.startsWith('http://') || song.filePath.startsWith('https://');
          return _buildAudioSource(
            song.filePath,
            MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: playlistId,
              artUri: song.albumArt.isNotEmpty
                  ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                  : null,
              duration: song.duration,
            ),
          );
        }).toList(),
      );

      // Ensure shuffle is disabled when playing playlist in order
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: 0, initialPosition: Duration.zero);
      await _player.play();
      addRecentlyPlayedPlaylist(playlistId);
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

      final songsList = filteredSongs.map((f) => _metadataCache.createSongFromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: playlistId);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) {
          final isRemote = song.filePath.startsWith('http://') || song.filePath.startsWith('https://');
          return _buildAudioSource(
            song.filePath,
            MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: playlistId,
              artUri: song.albumArt.isNotEmpty
                  ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                  : null,
              duration: song.duration,
            ),
          );
        }).toList(),
      );

      // Ensure shuffle is disabled when playing playlist in order
      await _player.setShuffleModeEnabled(false);
      await _player.setAudioSource(_playlist, initialIndex: initialIndex, initialPosition: Duration.zero);
      await _player.play();
      addRecentlyPlayedPlaylist(playlistId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing filtered playlist: $e');
    }
  }

  Future<void> playFiles(List<File> files, {String? artistName}) async {
    if (files.isEmpty) return;
    try {
      // Clear radio station when playing files
      _currentRadioStation = null;
      _currentArtistName = artistName;
      _currentPlaylistId = artistName != null ? null : 'offline';

      final songsList = files.map((f) => _metadataCache.createSongFromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: _currentPlaylistId);

      final playlist = ConcatenatingAudioSource(
        children: songsList.map((song) {
          final isRemote = song.filePath.startsWith('http://') || song.filePath.startsWith('https://');
          return _buildAudioSource(
            song.filePath,
            MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: song.album,
              artUri: song.albumArt.isNotEmpty
                  ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                  : null,
              duration: song.duration,
            ),
          );
        }).toList(),
      );

      await _player.setAudioSource(playlist, initialPosition: Duration.zero);
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

  Future<void> playFileInContext(File file, List<File> playlistFiles, {String? artistName}) async {
    if (playlistFiles.isEmpty) return;
    
    // If the clicked song is already the active track, just seek to beginning and play
    if (currentTrack?.id == file.path) {
      await _player.seek(Duration.zero);
      if (!_player.playing) {
        await _player.play();
      }
      return;
    }

    final currentSessionId = ++_playSessionId;
    try {
      // Cleanly stop and reset player to terminate any pending operations
      await _player.stop();
      if (_playSessionId != currentSessionId) return;

      // Clear radio station when playing songs
      _currentRadioStation = null;
      _currentArtistName = artistName;
      
      if (artistName != null) {
        _currentPlaylistId = null;
      } else {
        _currentPlaylistId = null;
        // Set current playlist by comparing contents exactly
        for (var entry in _playlists.entries) {
          if (listEquals(entry.value, playlistFiles)) {
            _currentPlaylistId = entry.key;
            addRecentlyPlayedPlaylist(_currentPlaylistId!);
            break;
          }
        }
        // If playlist not found, assume it's the offline playlist
        _currentPlaylistId ??= 'offline';
      }

      final songsList = playlistFiles.map((f) => _metadataCache.createSongFromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: _currentPlaylistId);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) {
          final isRemote = song.filePath.startsWith('http://') || song.filePath.startsWith('https://');
          return _buildAudioSource(
            song.filePath,
            MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: isRemote ? 'Network Stream' : _currentPlaylistId,
              artUri: song.albumArt.isNotEmpty
                  ? (song.albumArt.startsWith('http://') || song.albumArt.startsWith('https://') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                  : null,
              duration: song.duration,
            ),
          );
        }).toList(),
      );

      final selectedIndex = playlistFiles.indexWhere((f) => f.path == file.path);
      // Ensure shuffle is disabled when playing from playlist
      await _player.setShuffleModeEnabled(false);
      if (_playSessionId != currentSessionId) return;

      await _player.setAudioSource(_playlist, initialIndex: selectedIndex, initialPosition: Duration.zero);
      if (_playSessionId != currentSessionId) return;

      await _player.play();
      if (_playSessionId != currentSessionId) return;

      notifyListeners();
    } catch (e) {
      if (_playSessionId == currentSessionId) {
        debugPrint('Error playing file in context: $e');
      }
    }
  }

  Future<void> playFileInContextWithPlaylistId(File file, List<File> playlistFiles, String playlistId) async {
    if (playlistFiles.isEmpty) return;
 
    // If the clicked song is already the active track, just seek to beginning and play
    if (currentTrack?.id == file.path) {
      await _player.seek(Duration.zero);
      if (!_player.playing) {
        await _player.play();
      }
      return;
    }
 
    final currentSessionId = ++_playSessionId;
    try {
      // Cleanly stop and reset player to terminate any pending operations
      await _player.stop();
      if (_playSessionId != currentSessionId) return;

      // Clear radio station when playing songs
      _currentRadioStation = null;
      _currentPlaylistId = playlistId;
      addRecentlyPlayedPlaylist(_currentPlaylistId!);

      final songsList = playlistFiles.map((f) => _metadataCache.createSongFromFile(f)).toList();
      _playlistHandler.updateQueue(songsList, playlistContext: _currentPlaylistId);
      
      _playlist = ConcatenatingAudioSource(
        children: songsList.map((song) {
          final isRemote = song.filePath.startsWith('http://') || song.filePath.startsWith('https://');
          return _buildAudioSource(
            song.filePath,
            MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: _currentPlaylistId,
              artUri: song.albumArt.isNotEmpty
                  ? (song.albumArt.startsWith('http://') || song.albumArt.startsWith('https://') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                  : null,
              duration: song.duration,
            ),
          );
        }).toList(),
      );

      final selectedIndex = playlistFiles.indexWhere((f) => f.path == file.path);
      // Ensure shuffle is disabled when playing from playlist
      await _player.setShuffleModeEnabled(false);
      if (_playSessionId != currentSessionId) return;

      await _player.setAudioSource(_playlist, initialIndex: selectedIndex, initialPosition: Duration.zero);
      if (_playSessionId != currentSessionId) return;

      await _player.play();
      if (_playSessionId != currentSessionId) return;

      notifyListeners();
    } catch (e) {
      if (_playSessionId == currentSessionId) {
        debugPrint('Error playing file in context: $e');
      }
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
      final audioSource = _buildAudioSource(
        song.filePath,
        MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: 'Next Up', // Special marker for manually added songs
          artUri: song.albumArt.isNotEmpty
              ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
              : null,
          duration: song.duration,
        ),
      );

      if (_currentRadioStation != null) {
        // If a radio station was active, stop it, clear the queue, and start playing the queued song immediately
        await _player.stop();
        _currentRadioStation = null;
        _nextUpQueue.clear();
        _nextUpQueue.add(song);

        await _playlist.clear();
        await _playlist.add(audioSource);
        await _player.setAudioSource(_playlist);
        await _player.play();
        notifyListeners();
        return;
      }

      // Standard queue insertion
      _nextUpQueue.add(song);
      
      // Get current index to insert after current song
      final currentIndex = _player.currentIndex ?? 0;
      final insertIndex = currentIndex + 1;
      final clampedInsertIndex = insertIndex.clamp(0, _playlist.length);

      // Insert the song right after the current song in the audio player
      await _playlist.insert(clampedInsertIndex, audioSource);
      
      if (_player.audioSource == null) {
        await _player.setAudioSource(_playlist);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding to queue: $e');
    }
  }

  @override
  Future<void> insertAtQueue(Song song, int index) async {
    try {
      final audioSource = _buildAudioSource(
        song.filePath,
        MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: 'Next Up', // Special marker for manually added songs
          artUri: song.albumArt.isNotEmpty
              ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
              : null,
          duration: song.duration,
        ),
      );

      if (_currentRadioStation != null) {
        // If a radio station was active, stop it, clear the queue, and start playing the queued song immediately
        await _player.stop();
        _currentRadioStation = null;
        _nextUpQueue.clear();
        _nextUpQueue.add(song);

        await _playlist.clear();
        await _playlist.add(audioSource);
        await _player.setAudioSource(_playlist);
        await _player.play();
        notifyListeners();
        return;
      }

      final currentIdx = _player.currentIndex ?? -1;
      final relativeNextUpIndex = (index - currentIdx - 1).clamp(0, _nextUpQueue.length);
      final clampedInsertIndex = index.clamp(0, _playlist.length);

      // Add to next up queue
      _nextUpQueue.insert(relativeNextUpIndex, song);

      await _playlist.insert(clampedInsertIndex, _buildAudioSource(
        song.filePath,
        MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: 'Next Up', // Special marker for manually added songs
          artUri: song.albumArt.isNotEmpty
              ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
              : null,
          duration: song.duration,
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
        _buildAudioSource(
          song.filePath,
          MediaItem(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: _currentPlaylistId, // Preserve playlist context
            artUri: song.albumArt.isNotEmpty
                ? (song.albumArt.startsWith('http') ? Uri.parse(song.albumArt) : Uri.file(song.albumArt))
                : null,
            duration: song.duration,
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
  Future<void> clearQueue() async {
    try {
      _nextUpQueue.clear();

      final currentIndex = _player.currentIndex;
      // Iterate backwards to safely remove from concatenating playlist
      for (int i = _playlist.length - 1; i >= 0; i--) {
        if (i == currentIndex) continue;
        final source = _playlist.sequence[i];
        final mediaItem = source.tag as MediaItem?;
        if (mediaItem?.album == 'Next Up') {
          await _playlist.removeAt(i);
        }
      }

      // Sync updated queue back to _playlistHandler
      final currentQueueSongs = _playlist.sequence.map((source) {
        final mediaItem = source.tag as MediaItem?;
        return Song(
          id: mediaItem?.id ?? '',
          filePath: mediaItem?.id ?? '',
          title: mediaItem?.title ?? 'Unknown',
          artist: mediaItem?.artist ?? 'Unknown Artist',
          album: mediaItem?.album ?? '',
          duration: mediaItem?.duration ?? Duration.zero,
        );
      }).toList();

      _playlistHandler.updateQueue(currentQueueSongs, playlistContext: _currentPlaylistId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing queue: $e');
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
      
      // Move item inside concatenating source
      await _playlist.move(oldIndex, newIndex);
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error reordering queue: $e');
    }
  }

  String? get currentPlaylistName {
    if (_currentArtistName != null) return _currentArtistName;
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

  Stream<MediaItem?> get currentMediaStream => _currentMediaSubject.stream;

  Future<void> toggleShuffle() async {
    try {
      _isCustomShuffling = !_isCustomShuffling;
      
      // Use just_audio's native shuffle which doesn't interrupt playback
      await _player.setShuffleModeEnabled(_isCustomShuffling);
      
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
  LoopMode get loopMode => _player.loopMode;

  Future<bool> _hasNetworkConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // If check fails, don't hard-block here.
      return true;
    }
  }

  MediaItem _buildRadioMediaItem(RadioStation station) {
    final artUri = Uri.tryParse(station.artworkUrl);
    return MediaItem(
      id: station.id,
      title: station.name,
      artist: station.genre,
      artUri: artUri,
      album: 'Radio',
    );
  }

  Future<void> playRadioStation(RadioStation station) async {
    try {
      if (!await _hasNetworkConnection()) {
        debugPrint('Radio playback blocked: no network connection');
        _radioErrorSubject.add('No internet connection — cannot play \'${station.name}\'.');
        return;
      }

      // Clear previous radio state BEFORE stopping to avoid race with playerStateStream
      _radioWasPlaying = false;
      _currentRadioStation = null;
      await _player.stop();

      _currentRadioStation = station;
      _currentPlaylistId = null;
      _currentMedia = _buildRadioMediaItem(station);
      
      // Track recently played radio station
      _addRecentlyPlayedItem(RecentlyPlayedItem(
        type: 'radio',
        id: station.id,
        title: station.name,
        subtitle: station.genre,
        artwork: station.artworkUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        radioStation: station,
      ));
      
      notifyListeners();

      try {
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(station.streamUrl),
            tag: _buildRadioMediaItem(station),
          ),
        );
      } catch (e) {
        debugPrint('Error setting radio audio source: $e');
        _radioErrorSubject.add(
          'Cannot connect to \'${station.name}\' — stream may be offline.',
        );
        _currentRadioStation = null;
        notifyListeners();
        return;
      }
      _updateCurrentMediaSubject();
      try {
        await _player.play();
      } catch (e) {
        debugPrint('Error starting radio playback: $e');
        _radioErrorSubject.add('\'${station.name}\' failed to start.');
      }
      _updateCurrentMediaSubject();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing radio: $e');
      _radioErrorSubject.add('Radio playback failed. Please try again.');
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

  Future<void> updateCustomPlaylist(String playlistId, {String? name, String? artworkPath, int? artworkColor}) async {
    final playlist = _customPlaylists[playlistId];
    if (playlist != null) {
      final updatedPlaylist = playlist.copyWith(
        name: name,
        artworkPath: artworkPath,
        artworkColor: artworkColor,
        modifiedAt: DateTime.now(),
      );
      _customPlaylists[playlistId] = updatedPlaylist;

      // Update matching RecentlyPlayedItem if it exists in history
      final recentIndex = _recentlyPlayedItems.indexWhere((i) => i.type == 'playlist' && i.id == playlistId);
      if (recentIndex != -1) {
        final currentItem = _recentlyPlayedItems[recentIndex];
        _recentlyPlayedItems[recentIndex] = RecentlyPlayedItem(
          type: 'playlist',
          id: playlistId,
          title: name ?? currentItem.title,
          subtitle: '${getPlaylistSongs(playlistId).length} songs',
          artwork: artworkPath ?? currentItem.artwork,
          timestamp: currentItem.timestamp,
          radioStation: currentItem.radioStation,
        );
        await _saveRecentlyPlayed();
      }

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

  /// Generic removal that handles custom, liked, and system playlists.
  Future<void> removeSongFromPlaylist(String playlistId, File song) async {
    if (playlistId == 'liked') {
      _likedTracks.remove(song.path);
      _playlists['liked']?.removeWhere((f) => f.path == song.path);
      await _saveLikedTracks();

      if (_currentPlaylistId == 'liked') {
        final songsList = (_playlists['liked'] ?? []).map((f) => _metadataCache.createSongFromFile(f)).toList();
        _playlistHandler.updateQueue(songsList, playlistContext: 'liked');
      }

      notifyListeners();
      return;
    }

    if (_customPlaylists.containsKey(playlistId)) {
      await removeSongFromCustomPlaylist(playlistId, song);

      if (_currentPlaylistId == playlistId) {
        final songsList = (_playlists[playlistId] ?? []).map((f) => _metadataCache.createSongFromFile(f)).toList();
        _playlistHandler.updateQueue(songsList, playlistContext: playlistId);
      }
      return;
    }

    // Handling for the offline system playlist (hide/blocklist from library view)
    if (playlistId == 'offline') {
      if (!_hiddenTracks.contains(song.path)) {
        _hiddenTracks.add(song.path);
        await _prefs.setStringList(_hiddenTracksKey, _hiddenTracks);
      }

      // Also clean up from liked tracks
      if (_likedTracks.contains(song.path)) {
        _likedTracks.remove(song.path);
        _playlists['liked']?.removeWhere((f) => f.path == song.path);
        await _saveLikedTracks();
      }

      // Clean up from all custom playlists
      for (final pid in _customPlaylists.keys.toList()) {
        final playlist = _customPlaylists[pid]!;
        if (playlist.songPaths.contains(song.path)) {
          final updatedPaths = List<String>.from(playlist.songPaths)..remove(song.path);
          _customPlaylists[pid] = playlist.copyWith(
            songPaths: updatedPaths,
            modifiedAt: DateTime.now(),
          );
          _playlists[pid]?.removeWhere((f) => f.path == song.path);
        }
      }
      await _saveCustomPlaylists();
    }

    // Fallback for other system playlists
    final list = _playlists[playlistId];
    if (list != null) {
      list.removeWhere((f) => f.path == song.path);
      _playlists[playlistId] = list;

      if (_currentPlaylistId == playlistId) {
        final songsList = list.map((f) => _metadataCache.createSongFromFile(f)).toList();
        _playlistHandler.updateQueue(songsList, playlistContext: playlistId);
      }

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

  /// Refresh metadata for currently playing song and entire queue from cache
  /// Always notifies listeners, even if player/queue is empty, so UI using cached
  /// metadata can rebuild immediately after edits.
  Future<void> refreshCurrentMetadata() async {
    try {
      final sequence = _player.sequence;
      if (sequence != null && sequence.isNotEmpty) {
        final updatedQueueSongs = <Song>[];
        for (final source in sequence) {
          final mediaItem = source.tag as MediaItem?;
          if (mediaItem == null) continue;

          final file = File(mediaItem.id);
          if (await file.exists()) {
            final song = _metadataCache.createSongFromFile(file);
            updatedQueueSongs.add(song);
          }
        }

        // Keep the queue model in sync with refreshed metadata
        if (updatedQueueSongs.isNotEmpty) {
          _playlistHandler.updateQueue(updatedQueueSongs, playlistContext: _currentPlaylistId);
        }
      }

      // Explicitly update the cached media reference from currentTrack
      _currentMedia = currentTrack;
      _updateCurrentMediaSubject();
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing metadata: $e');
    }
  }

  // --- Recently Played State ---
  final List<RecentlyPlayedItem> _recentlyPlayedItems = [];

  void _addRecentlyPlayedItem(RecentlyPlayedItem item) {
    _recentlyPlayedItems.removeWhere((i) => i.type == item.type && i.id == item.id);
    _recentlyPlayedItems.insert(0, item);
    if (_recentlyPlayedItems.length > 25) {
      _recentlyPlayedItems.removeLast();
    }
    _saveRecentlyPlayed();
    notifyListeners();
  }

  void addRecentlyPlayedPlaylist(String playlistId) {
    String playlistTitle = playlistId == 'liked' ? 'Liked Songs' : (playlistId == 'offline' ? 'Offline' : playlistId);
    final customPlaylist = _customPlaylists[playlistId];
    if (customPlaylist != null) {
      playlistTitle = customPlaylist.name;
    }
    _addRecentlyPlayedItem(RecentlyPlayedItem(
      type: 'playlist',
      id: playlistId,
      title: playlistTitle,
      subtitle: '${getPlaylistSongs(playlistId).length} songs',
      artwork: customPlaylist?.artworkPath ?? '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  List<RecentlyPlayedItem> get recentlyPlayedItems {
    return List.unmodifiable(_recentlyPlayedItems.where((item) {
      if (item.type == 'radio') {
        return !_hiddenRadios.contains(item.id);
      }
      if (item.type == 'song') {
        return !_hiddenTracks.contains(item.id);
      }
      return true;
    }));
  }

  Future<void> clearRecentlyPlayed() async {
    _recentlyPlayedItems.clear();
    await _prefs.remove(_recentlyPlayedKey);
    notifyListeners();
  }

  Future<void> clearHiddenRadiosAndTracks() async {
    _hiddenRadios.clear();
    _hiddenTracks.clear();
    await _prefs.remove(_hiddenRadiosKey);
    await _prefs.remove(_hiddenTracksKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _currentRadioStation = null;
    _durationSubject.close();
    _currentMediaSubject.close();
    _player.dispose();
    super.dispose();
  }
}
