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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _gaplessPlayback = prefs.getBool(_kGaplessPlaybackKey) ?? true;
    _normalizeVolume = prefs.getBool(_kNormalizeVolumeKey) ?? false;
    _hapticsEnabled = prefs.getBool(_kHapticsEnabledKey) ?? true;
    _hapticsOnButtonTaps = prefs.getBool(_kHapticsOnButtonTapsKey) ?? true;
    _hapticsOnLikes = prefs.getBool(_kHapticsOnLikesKey) ?? true;
    _hapticsOnLongPress = prefs.getBool(_kHapticsOnLongPressKey) ?? true;
    _hapticsOnSliderScrubbing = prefs.getBool(_kHapticsOnSliderScrubbingKey) ?? true;
    final accentVal = prefs.getInt(_kAccentColorKey);
    if (accentVal != null) {
      _accentColor = Color(accentVal);
    } else {
      _accentColor = const Color(0xFF7C5CBF);
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
}
