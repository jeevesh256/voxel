import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/radio_station.dart';

class RadioBrowserService {
  static const String _mirrorsUrl =
      'https://all.api.radio-browser.info/json/servers';
  static const String _apiSuffix = '/json';
  String? _activeBaseUrl;
  static const String _prefsKey = 'radio_browser_active_base_url';

  /// Background refresh for top stations (does not trigger UI update)
  Future<void> refreshTopStationsInBackground({int limit = 200}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'stations_top_$limit';
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse('$baseUrl/stations/topclick/$limit');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  /// Background refresh for genres (does not trigger UI update)
  Future<void> refreshGenresInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'genres_all';
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse('$baseUrl/tags');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  /// Background refresh for stations by genre (does not trigger UI update)
  Future<void> refreshStationsByGenreInBackground({String? genre, int limit = 20}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = genre == null || genre.isEmpty
        ? 'stations_all_$limit'
        : 'stations_genre_${genre}_$limit';
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse(genre == null || genre.isEmpty
        ? '$baseUrl/stations?limit=$limit&hidebroken=true'
        : '$baseUrl/stations/bytag/$genre?limit=$limit&hidebroken=true');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
      }
    } catch (_) {}
  }

  Future<String> _getActiveBaseUrl() async {
    if (_activeBaseUrl != null) return _activeBaseUrl!;
    // Try to load from shared preferences first
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_prefsKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _activeBaseUrl = savedUrl;
      return _activeBaseUrl!;
    }
    try {
      final response = await http.get(Uri.parse(_mirrorsUrl));
      if (response.statusCode == 200) {
        final List mirrors = json.decode(response.body);
        if (mirrors.isNotEmpty) {
          // Pick a random mirror
          final random = Random();
          final mirror = mirrors[random.nextInt(mirrors.length)];
          final name = mirror['name'] as String;
          _activeBaseUrl = 'https://$name$_apiSuffix';
          // Save for next time
          await prefs.setString(_prefsKey, _activeBaseUrl!);
          return _activeBaseUrl!;
        }
      }
    } catch (_) {}
    // Fallback to a default mirror if all else fails
    _activeBaseUrl = 'https://de1.api.radio-browser.info/json';
    await prefs.setString(_prefsKey, _activeBaseUrl!);
    return _activeBaseUrl!;
  }

  Future<List<RadioStation>> fetchStations({String? genre, int limit = 20}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = genre == null || genre.isEmpty
        ? 'stations_all_$limit'
        : 'stations_genre_${genre}_$limit';
    // Try cache first
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final List data = json.decode(cached);
        return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
      } catch (_) {}
    }
    // Fetch from network
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse(genre == null || genre.isEmpty
        ? '$baseUrl/stations?limit=$limit&hidebroken=true'
        : '$baseUrl/stations/bytag/$genre?limit=$limit&hidebroken=true');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      // Save to cache
      await prefs.setString(cacheKey, response.body);
      return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
    }
    return [];
  }

  Future<List<RadioStation>> fetchTopStations({int limit = 200}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'stations_top_$limit';
    // Try cache first
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final List data = json.decode(cached);
        return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
      } catch (_) {}
    }
    // Fetch from network
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse('$baseUrl/stations/topclick/$limit');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      // Save to cache
      await prefs.setString(cacheKey, response.body);
      return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
    }
    return [];
  }

  Future<List<String>> fetchGenres() async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'genres_all';
    // Try cache first
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final List data = json.decode(cached);
        return data.map((e) => e['name'] as String).toList();
      } catch (_) {}
    }
    // Fetch from network
    final baseUrl = await _getActiveBaseUrl();
    final uri = Uri.parse('$baseUrl/tags');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      // Save to cache
      await prefs.setString(cacheKey, response.body);
      return data.map((e) => e['name'] as String).toList();
    }
    return [];
  }
}
