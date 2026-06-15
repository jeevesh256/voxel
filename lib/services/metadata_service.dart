import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'itunes_service.dart';

class MetadataResult {
  final String title;
  final String artist;
  final String album;
  final String? albumArtPath;
  final String? releaseId;
  final String? coverArtUrl;
  final Duration? duration;
  final bool isFromFile;
  final bool isFromAPI;
  final String? source;

  MetadataResult({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtPath,
    this.releaseId,
    this.coverArtUrl,
    this.duration,
    this.isFromFile = false,
    this.isFromAPI = false,
    this.source,
  });
}

class MetadataService {
  final ITunesService _iTunesService = ITunesService();

  /// Extract basic metadata from filename
  MetadataResult extractFilenameMetadata(String filePath) {
    // Extract filename without extension
    String filename = filePath
        .split('/')
        .last
        .replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');

    // Try to parse common patterns like "Artist - Title" or "Title"
    String title = filename;
    String artist = 'Unknown Artist';

    // Check for "Artist - Title" pattern
    if (filename.contains(' - ')) {
      final parts = filename.split(' - ');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    // Remove trailing (feat. ...) and [ ... ] from title
    title = title.replaceAll(RegExp(r'\s*\(feat\..*?\)', caseSensitive: false), '').trim();
    title = title.replaceAll(RegExp(r'\s*\[.*?\]'), '').trim();

    // Remove trailing (feat. ...) and [ ... ] from artist
    artist = artist.replaceAll(RegExp(r'\s*\(feat\..*?\)', caseSensitive: false), '').trim();
    artist = artist.replaceAll(RegExp(r'\s*\[.*?\]'), '').trim();

    // Remove trailing unmatched parenthesis or brackets from artist
    artist = artist.replaceAll(RegExp(r'[\[\(][^\]\)]*$'), '').trim();

    return MetadataResult(
      title: title,
      artist: artist,
      album: '',
      isFromFile: true,
      source: 'File',
    );
  }

  /// Enrich metadata using iTunes API
  Future<MetadataResult?> enrichMetadata({
    required String title,
    String? artist,
    int limit = 5,
  }) async {
    try {
      final query = [artist, title]
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .join(' ')
          .trim();
      final tracks = await _iTunesService.searchTracks(
        term: query.isNotEmpty ? query : title,
        limit: limit,
      );

      if (tracks.isEmpty) {
        return null;
      }

      final bestMatch = tracks.first;
      String? albumArtPath;

      if (bestMatch.artworkUrl.isNotEmpty) {
        albumArtPath = await downloadCoverArtFromUrl(
          url: bestMatch.artworkUrl,
          identifier: '${bestMatch.artistName}_${bestMatch.collectionName}',
        );
      }

      return MetadataResult(
        title: bestMatch.trackName,
        artist: bestMatch.artistName,
        album: bestMatch.collectionName,
        albumArtPath: albumArtPath,
        coverArtUrl: bestMatch.artworkUrl,
        isFromAPI: true,
        source: 'iTunes',
      );
    } catch (e) {
      print('Error enriching metadata: $e');
      return null;
    }
  }

  /// Update metadata for a song: parse filename, then use iTunes enrichment
  Future<Song> updateSongMetadata(Song song) async {
    print('Starting metadata update for: ${song.filePath}');

    // Step 1: Extract basic info from filename
    final fileMetadata = extractFilenameMetadata(song.filePath);
    print(
        'Extracted from filename: title="${fileMetadata.title}", artist="${fileMetadata.artist}"');

    // Step 2: Query iTunes API for accurate metadata
    final apiMetadata = await enrichMetadata(
      title: fileMetadata.title,
      artist:
          fileMetadata.artist != 'Unknown Artist' ? fileMetadata.artist : null,
    );

    if (apiMetadata != null) {
      print('Using API metadata');
      // Use API metadata
      return song.copyWith(
        title: apiMetadata.title,
        artist: apiMetadata.artist,
        album: apiMetadata.album,
        albumArt: apiMetadata.albumArtPath ?? song.albumArt,
      );
    }

    print('No API match, using filename parsing');
    // No API match, use filename parsing
    return song.copyWith(
      title: fileMetadata.title,
      artist: fileMetadata.artist,
      album: fileMetadata.album,
    );
  }

  /// Fetch multiple candidate metadata results from the API (no downloads yet)
  Future<List<MetadataResult>> searchMetadataOptions({
    required String title,
    String? artist,
    int limit = 10,
  }) async {
    try {
      final query = [artist, title]
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .join(' ')
          .trim();
      final iTunesTracks = await _iTunesService.searchTracks(
        term: query.isNotEmpty ? query : title,
        limit: limit,
      );
      final iTunesResults = iTunesTracks.map((t) {
        return MetadataResult(
          title: t.trackName,
          artist: t.artistName,
          album: t.collectionName,
          coverArtUrl: t.artworkUrl,
          isFromAPI: true,
          source: 'iTunes',
        );
      }).toList();

      // De-duplicate by title+artist.
      final merged = <String, MetadataResult>{};
      for (final r in iTunesResults) {
        final key = '${r.title.toLowerCase()}__${r.artist.toLowerCase()}';
        merged.putIfAbsent(key, () => r);
      }

      return merged.values.take(limit).toList();
    } catch (e) {
      print('Error searching metadata options: $e');
      return [];
    }
  }

  /// Download cover art for a release and persist it; returns saved file path.
  Future<String?> downloadCoverArtForRelease({
    required String releaseId,
    required String identifier,
  }) async {
    // Release-id based artwork lookup is disabled; iTunes flow uses direct URLs.
    return null;
  }

  /// Download cover art from a direct URL and persist it; returns saved file path.
  Future<String?> downloadCoverArtFromUrl({
    required String url,
    required String identifier,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        return null;
      }
      return await _saveAlbumArtBytes(response.bodyBytes, identifier);
    } catch (e) {
      print('Error downloading cover art from $url: $e');
      return null;
    }
  }

  /// Persist provided album art bytes; returns saved file path or null.
  Future<String?> saveAlbumArtBytes(
      {required List<int> bytes, required String identifier}) async {
    try {
      return await _saveAlbumArtBytes(bytes, identifier);
    } catch (e) {
      print('Error saving provided album art bytes: $e');
      return null;
    }
  }

  /// Save album art from downloaded bytes
  Future<String?> _saveAlbumArtBytes(
      List<int> artData, String identifier) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final albumArtDir = Directory('${appDir.path}/album_art');

      if (!await albumArtDir.exists()) {
        await albumArtDir.create(recursive: true);
      }

      // Sanitize identifier for filename
      final sanitized = identifier
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');

      final artFile = File('${albumArtDir.path}/$sanitized.jpg');

      await artFile.writeAsBytes(artData);
      return artFile.path;
    } catch (e) {
      print('Error saving album art: $e');
      return null;
    }
  }
}
