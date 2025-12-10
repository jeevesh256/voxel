import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'dart:io';

class SongMetadataCache {
  // Singleton so all callers share the same in-memory cache
  static final SongMetadataCache _instance = SongMetadataCache._internal();
  factory SongMetadataCache() => _instance;
  SongMetadataCache._internal();

  static const String _cacheKey = 'song_metadata_cache';
  late SharedPreferences _prefs;
  final Map<String, Map<String, dynamic>> _cache = {};

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCache();
  }

  Future<void> _loadCache() async {
    final cacheJson = _prefs.getString(_cacheKey);
    if (cacheJson != null) {
      try {
        final decoded = jsonDecode(cacheJson) as Map<String, dynamic>;
        _cache.clear();
        _cache.addAll(decoded.cast<String, Map<String, dynamic>>());
      } catch (e) {
        print('Error loading metadata cache: $e');
      }
    }
  }

  Future<void> _saveCache() async {
    try {
      final encoded = jsonEncode(_cache);
      await _prefs.setString(_cacheKey, encoded);
    } catch (e) {
      print('Error saving metadata cache: $e');
    }
  }

  /// Save metadata for a song
  Future<void> saveMetadata(Song song) async {
    _cache[song.filePath] = {
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'albumArt': song.albumArt,
      'duration': song.duration.inMilliseconds,
    };
    await _saveCache();
  }

  /// Get cached metadata for a file path
  Map<String, dynamic>? getMetadata(String filePath) {
    return _cache[filePath];
  }

  /// Create a Song from file with cached metadata if available
  Song createSongFromFile(File file) {
    final cached = getMetadata(file.path);
    
    if (cached != null) {
      return Song(
        id: file.path,
        filePath: file.path,
        title: cached['title'] ?? file.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), ''),
        artist: cached['artist'] ?? 'Unknown Artist',
        album: cached['album'] ?? '',
        albumArt: cached['albumArt'] ?? '',
        duration: Duration(milliseconds: cached['duration'] ?? 180000),
      );
    }
    
    // No cached metadata, use default Song.fromFile
    return Song.fromFile(file);
  }

  /// Clear all cached metadata
  Future<void> clearCache() async {
    _cache.clear();
    await _saveCache();
  }
}
