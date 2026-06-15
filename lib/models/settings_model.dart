import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/song_metadata_cache.dart';

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
    // Optionally: clear other caches here
    return removed;
  }

  static const String _kShowNonMusicGenresKey = 'show_non_music_genres';
  static const String _kGaplessPlaybackKey = 'gapless_playback';
  static const String _kNormalizeVolumeKey = 'normalize_volume';
  static const String _kUseCellularDataKey = 'use_cellular_data';
  static const String _kDataSaverKey = 'data_saver_mode';
  static const String _kOfflineModeKey = 'offline_mode';

  bool _showNonMusicGenres = false;
  bool _gaplessPlayback = true;
  bool _normalizeVolume = false;
  bool _useCellularData = true;
  bool _dataSaverMode = false;
  bool _offlineMode = false;

  SettingsModel() {
    _loadSettings();
  }

  bool get showNonMusicGenres => _showNonMusicGenres;
  bool get gaplessPlayback => _gaplessPlayback;
  bool get normalizeVolume => _normalizeVolume;
  bool get useCellularData => _useCellularData;
  bool get dataSaverMode => _dataSaverMode;
  bool get offlineMode => _offlineMode;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _showNonMusicGenres = prefs.getBool(_kShowNonMusicGenresKey) ?? false;
    _gaplessPlayback = prefs.getBool(_kGaplessPlaybackKey) ?? true;
    _normalizeVolume = prefs.getBool(_kNormalizeVolumeKey) ?? false;
    _useCellularData = prefs.getBool(_kUseCellularDataKey) ?? true;
    _dataSaverMode = prefs.getBool(_kDataSaverKey) ?? false;
    _offlineMode = prefs.getBool(_kOfflineModeKey) ?? false;
    notifyListeners();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void setShowNonMusicGenres(bool value) {
    _showNonMusicGenres = value;
    _saveBool(_kShowNonMusicGenresKey, value);
    notifyListeners();
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

  void setUseCellularData(bool value) {
    _useCellularData = value;
    _saveBool(_kUseCellularDataKey, value);
    notifyListeners();
  }

  void setDataSaverMode(bool value) {
    _dataSaverMode = value;
    _saveBool(_kDataSaverKey, value);
    notifyListeners();
  }

  void setOfflineMode(bool value) {
    _offlineMode = value;
    _saveBool(_kOfflineModeKey, value);
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
}
