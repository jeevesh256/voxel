import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/song_metadata_cache.dart';
import '../services/webdav_service.dart';
import '../services/jellyfin_service.dart';

class SettingsModel extends ChangeNotifier {
  /// Clear all app caches: station, genre, and song metadata
  Future<int> clearAppCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    const stationPrefixes = [
      'stations_top_',
      'stations_all_',
      'stations_genre_',
    ];
    int removed = 0;
    // Remove station and genre caches
    for (final key in keys) {
      final isStationCache =
          stationPrefixes.any((prefix) => key.startsWith(prefix));
      if (isStationCache || key == 'genres_all') {
        final didRemove = await prefs.remove(key);
        if (didRemove) removed++;
      }
    }
    // Clear song metadata cache
    await SongMetadataCache().clearCache();
    // Clear recently played cache key
    await prefs.remove('recently_played_items');
    return removed;
  }

  static const String _kGaplessPlaybackKey = 'gapless_playback';
  static const String _kNormalizeVolumeKey = 'normalize_volume';
  static const String _kAccentColorKey = 'theme_accent_color';
  static const String _kHapticsEnabledKey = 'haptics_enabled';
  static const String _kHapticsOnButtonTapsKey = 'haptics_on_button_taps';
  static const String _kHapticsOnLikesKey = 'haptics_on_likes';
  static const String _kHapticsOnLongPressKey = 'haptics_on_long_press';
  static const String _kHapticsOnSliderScrubbingKey = 'haptics_on_slider_scrubbing';
  static const String _kCookiePlayPauseEnabledKey = 'cookie_play_pause_enabled';
  static const String _kSourcePathsKey = 'source_paths';
  static const String _kWebdavServersKey = 'webdav_servers';
  static const String _kJellyfinServersKey = 'jellyfin_servers';
  static const String _kPinnedFoldersKey = 'pinned_network_folders';

  static const List<String> defaultSourcePaths = [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
  ];

  static const List<Color> accentPresets = [
    Color(0xFF7C5CBF), // Muted Violet
    Color(0xFF2E8B6A), // Muted Emerald
    Color(0xFF5558B8), // Muted Indigo
    Color(0xFFC43B59), // Muted Rose
    Color(0xFFD4880F), // Muted Amber
    Color(0xFFC06448), // Terracotta
  ];

  bool _gaplessPlayback = true;
  bool _normalizeVolume = false;
  Color _accentColor = const Color(0xFF7C5CBF);
  bool _hapticsEnabled = true;
  bool _hapticsOnButtonTaps = true;
  bool _hapticsOnLikes = true;
  bool _hapticsOnLongPress = true;
  bool _hapticsOnSliderScrubbing = true;
  bool _cookiePlayPauseEnabled = false;
  List<String> _sourcePaths = List.from(defaultSourcePaths);
  List<WebdavServerConfig> _webdavServers = [];
  List<JellyfinServerConfig> _jellyfinServers = [];
  List<PinnedNetworkFolder> _pinnedFolders = [];

  SettingsModel() {
    _loadSettings();
  }

  bool get gaplessPlayback => _gaplessPlayback;
  bool get normalizeVolume => _normalizeVolume;
  Color get accentColor => _accentColor;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get hapticsOnButtonTaps => _hapticsOnButtonTaps;
  bool get hapticsOnLikes => _hapticsOnLikes;
  bool get hapticsOnLongPress => _hapticsOnLongPress;
  bool get hapticsOnSliderScrubbing => _hapticsOnSliderScrubbing;
  bool get cookiePlayPauseEnabled => _cookiePlayPauseEnabled;
  List<String> get sourcePaths => List.unmodifiable(_sourcePaths);
  List<WebdavServerConfig> get webdavServers => List.unmodifiable(_webdavServers);
  List<JellyfinServerConfig> get jellyfinServers => List.unmodifiable(_jellyfinServers);
  List<PinnedNetworkFolder> get pinnedFolders => List.unmodifiable(_pinnedFolders);

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _gaplessPlayback = prefs.getBool(_kGaplessPlaybackKey) ?? true;
    _normalizeVolume = prefs.getBool(_kNormalizeVolumeKey) ?? false;
    _hapticsEnabled = prefs.getBool(_kHapticsEnabledKey) ?? true;
    _hapticsOnButtonTaps = prefs.getBool(_kHapticsOnButtonTapsKey) ?? true;
    _hapticsOnLikes = prefs.getBool(_kHapticsOnLikesKey) ?? true;
    _hapticsOnLongPress = prefs.getBool(_kHapticsOnLongPressKey) ?? true;
    _hapticsOnSliderScrubbing = prefs.getBool(_kHapticsOnSliderScrubbingKey) ?? true;
    _cookiePlayPauseEnabled = prefs.getBool(_kCookiePlayPauseEnabledKey) ?? false;
    final accentVal = prefs.getInt(_kAccentColorKey);
    if (accentVal != null) {
      _accentColor = Color(accentVal);
    } else {
      _accentColor = const Color(0xFF7C5CBF);
    }
    final savedPaths = prefs.getStringList(_kSourcePathsKey);
    if (savedPaths != null && savedPaths.isNotEmpty) {
      _sourcePaths = savedPaths;
    }
    final savedWebdav = prefs.getStringList(_kWebdavServersKey);
    if (savedWebdav != null) {
      try {
        _webdavServers = savedWebdav
            .map((s) => WebdavServerConfig.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding webdav servers: $e');
      }
    }
    final savedJellyfin = prefs.getStringList(_kJellyfinServersKey);
    if (savedJellyfin != null) {
      try {
        _jellyfinServers = savedJellyfin
            .map((s) => JellyfinServerConfig.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding jellyfin servers: $e');
      }
    }
    final savedPinned = prefs.getStringList(_kPinnedFoldersKey);
    if (savedPinned != null) {
      try {
        _pinnedFolders = savedPinned
            .map((s) => PinnedNetworkFolder.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding pinned folders: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }


  void setGaplessPlayback(bool value) {
    _gaplessPlayback = value;
    _saveBool(_kGaplessPlaybackKey, value);
    notifyListeners();
  }

  void setNormalizeVolume(bool value) {
    _normalizeVolume = value;
    _saveBool(_kNormalizeVolumeKey, value);
    notifyListeners();
  }

  void setHapticsEnabled(bool value) {
    _hapticsEnabled = value;
    _saveBool(_kHapticsEnabledKey, value);
    notifyListeners();
  }

  void setHapticsOnButtonTaps(bool value) {
    _hapticsOnButtonTaps = value;
    _saveBool(_kHapticsOnButtonTapsKey, value);
    notifyListeners();
  }

  void setHapticsOnLikes(bool value) {
    _hapticsOnLikes = value;
    _saveBool(_kHapticsOnLikesKey, value);
    notifyListeners();
  }

  void setHapticsOnLongPress(bool value) {
    _hapticsOnLongPress = value;
    _saveBool(_kHapticsOnLongPressKey, value);
    notifyListeners();
  }

  void setHapticsOnSliderScrubbing(bool value) {
    _hapticsOnSliderScrubbing = value;
    _saveBool(_kHapticsOnSliderScrubbingKey, value);
    notifyListeners();
  }

  void setCookiePlayPauseEnabled(bool value) {
    _cookiePlayPauseEnabled = value;
    _saveBool(_kCookiePlayPauseEnabledKey, value);
    notifyListeners();
  }

  Future<void> addSourcePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || _sourcePaths.contains(trimmed)) return;
    _sourcePaths = [..._sourcePaths, trimmed];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSourcePathsKey, _sourcePaths);
    notifyListeners();
  }

  Future<void> removeSourcePath(String path) async {
    _sourcePaths = _sourcePaths.where((p) => p != path).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSourcePathsKey, _sourcePaths);
    notifyListeners();
  }

  Future<void> resetSourcePaths() async {
    _sourcePaths = List.from(defaultSourcePaths);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSourcePathsKey, _sourcePaths);
    notifyListeners();
  }

  Future<void> addWebdavServer(WebdavServerConfig server) async {
    if (_webdavServers.any((s) => s.url == server.url)) return;
    _webdavServers = [..._webdavServers, server];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kWebdavServersKey,
      _webdavServers.map((s) => jsonEncode(s.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> removeWebdavServer(String id) async {
    _webdavServers = _webdavServers.where((s) => s.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kWebdavServersKey,
      _webdavServers.map((s) => jsonEncode(s.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> addJellyfinServer(JellyfinServerConfig server) async {
    if (_jellyfinServers.any((s) => s.url == server.url)) return;
    _jellyfinServers = [..._jellyfinServers, server];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kJellyfinServersKey,
      _jellyfinServers.map((s) => jsonEncode(s.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> removeJellyfinServer(String id) async {
    _jellyfinServers = _jellyfinServers.where((s) => s.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kJellyfinServersKey,
      _jellyfinServers.map((s) => jsonEncode(s.toJson())).toList(),
    );
    notifyListeners();
  }

  void setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAccentColorKey, color.value);
    notifyListeners();
  }

  Future<int> clearStationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    const prefixes = [
      'stations_top_',
      'stations_all_',
      'stations_genre_',
    ];

    var removed = 0;
    for (final key in keys) {
      final isStationCache = prefixes.any((prefix) => key.startsWith(prefix));
      if (isStationCache || key == 'genres_all') {
        final didRemove = await prefs.remove(key);
        if (didRemove) {
          removed++;
        }
      }
    }
    return removed;
  }

  Future<void> pinNetworkFolder(PinnedNetworkFolder folder) async {
    if (_pinnedFolders.any((f) => f.id == folder.id)) return;
    _pinnedFolders = [..._pinnedFolders, folder];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kPinnedFoldersKey,
      _pinnedFolders.map((f) => jsonEncode(f.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> unpinNetworkFolder(String id) async {
    _pinnedFolders = _pinnedFolders.where((f) => f.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kPinnedFoldersKey,
      _pinnedFolders.map((f) => jsonEncode(f.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> updatePinnedNetworkFolder(
    String id, {
    String? name,
    String? artworkPath,
    int? artworkColor,
  }) async {
    _pinnedFolders = _pinnedFolders.map((f) {
      if (f.id == id) {
        return PinnedNetworkFolder(
          id: f.id,
          name: name ?? f.name,
          type: f.type,
          serverId: f.serverId,
          serverName: f.serverName,
          path: f.path,
          controlUrl: f.controlUrl,
          artworkPath: artworkPath ?? f.artworkPath,
          artworkColor: artworkColor ?? f.artworkColor,
        );
      }
      return f;
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kPinnedFoldersKey,
      _pinnedFolders.map((f) => jsonEncode(f.toJson())).toList(),
    );
    notifyListeners();
  }
}

class PinnedNetworkFolder {
  final String id;
  final String name;
  final String type; // 'upnp', 'webdav', or 'jellyfin'
  final String serverId;
  final String serverName;
  final String path;
  final String? controlUrl; // for UPnP
  final String? artworkPath;
  final int? artworkColor;

  PinnedNetworkFolder({
    required this.id,
    required this.name,
    required this.type,
    required this.serverId,
    required this.serverName,
    required this.path,
    this.controlUrl,
    this.artworkPath,
    this.artworkColor,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'serverId': serverId,
        'serverName': serverName,
        'path': path,
        'controlUrl': controlUrl,
        'artworkPath': artworkPath,
        'artworkColor': artworkColor,
      };

  factory PinnedNetworkFolder.fromJson(Map<String, dynamic> json) => PinnedNetworkFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        serverId: json['serverId'] as String,
        serverName: json['serverName'] as String,
        path: json['path'] as String,
        controlUrl: json['controlUrl'] as String?,
        artworkPath: json['artworkPath'] as String?,
        artworkColor: json['artworkColor'] as int?,
      );
}

