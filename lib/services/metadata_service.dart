import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'musicbrainz_service.dart';
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
  final MusicBrainzService _musicBrainzService = MusicBrainzService();
  final ITunesService _iTunesService = ITunesService();

  /// Extract basic metadata from filename
  MetadataResult extractFilenameMetadata(String filePath) {
    // Extract filename without extension
    String filename = filePath.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
    
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

    return MetadataResult(
      title: title,
      artist: artist,
      album: '',
      isFromFile: true,
      source: 'File',
    );
  }

  /// Enrich metadata using MusicBrainz API
  Future<MetadataResult?> enrichMetadata({
    required String title,
    String? artist,
    int limit = 5,
  }) async {
    try {
      print('Searching MusicBrainz for: title="$title", artist="$artist"');
      
      final recordings = await _musicBrainzService.searchRecording(
        title: title,
        artist: artist,
        limit: limit,
      );

      print('Found ${recordings.length} recordings');

      if (recordings.isEmpty) {
        print('No recordings found');
        return null;
      }

      // Get the best match (highest score)
      final bestMatch = recordings.first;
      print('Best match: ${bestMatch.title} by ${bestMatch.artist} (score: ${bestMatch.score})');

      String? albumArtPath;
      
      // Download cover art if available
      if (bestMatch.releaseId != null) {
        print('Downloading cover art for release: ${bestMatch.releaseId}');
        final artBytes = await _musicBrainzService.downloadCoverArt(
          bestMatch.releaseId!,
        );

        if (artBytes != null) {
          print('Cover art downloaded, saving...');
          albumArtPath = await _saveAlbumArtBytes(
            artBytes,
            '${bestMatch.artist}_${bestMatch.album ?? bestMatch.title}',
          );
          print('Album art saved to: $albumArtPath');
        } else {
          print('No cover art available');
        }
      }

      return MetadataResult(
        title: bestMatch.title,
        artist: bestMatch.artist,
        album: bestMatch.album ?? '',
        albumArtPath: albumArtPath,
        releaseId: bestMatch.releaseId,
        coverArtUrl: _musicBrainzService.getCoverArtUrl(bestMatch.releaseId ?? ''),
        isFromAPI: true,
        source: 'MusicBrainz',
      );
    } catch (e) {
      print('Error enriching metadata: $e');
      return null;
    }
  }

  /// Update metadata for a song: parse filename, then use API enrichment
  Future<Song> updateSongMetadata(Song song) async {
    print('Starting metadata update for: ${song.filePath}');
    
    // Step 1: Extract basic info from filename
    final fileMetadata = extractFilenameMetadata(song.filePath);
    print('Extracted from filename: title="${fileMetadata.title}", artist="${fileMetadata.artist}"');

    // Step 2: Query MusicBrainz API for accurate metadata
    final apiMetadata = await enrichMetadata(
      title: fileMetadata.title,
      artist: fileMetadata.artist != 'Unknown Artist' ? fileMetadata.artist : null,
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
      final recordings = await _musicBrainzService.searchRecording(
        title: title,
        artist: artist,
        limit: limit,
      );

      final musicBrainzResults = recordings.map((rec) {
        return MetadataResult(
          title: rec.title,
          artist: rec.artist,
          album: rec.album ?? '',
          releaseId: rec.releaseId,
          coverArtUrl: _musicBrainzService.getCoverArtUrl(rec.releaseId ?? ''),
          isFromAPI: true,
          source: 'MusicBrainz',
        );
      }).toList();

      // iTunes fallback/augment
      final query = [artist, title].where((e) => e != null && e!.isNotEmpty).join(' ');
      final iTunesTracks = await _iTunesService.searchTracks(term: query.isNotEmpty ? query : title, limit: limit);
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

      // Merge unique by title+artist, prioritizing iTunes results first
      final merged = <String, MetadataResult>{};
      for (final r in [...iTunesResults, ...musicBrainzResults]) {
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
    try {
      final artBytes = await _musicBrainzService.downloadCoverArt(releaseId);
      if (artBytes == null) {
        print('No cover art bytes for $releaseId');
        return null;
      }
      return await _saveAlbumArtBytes(artBytes, identifier);
    } catch (e) {
      print('Error downloading cover art for release $releaseId: $e');
      return null;
    }
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
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        return null;
      }
      return await _saveAlbumArtBytes(response.bodyBytes, identifier);
    } catch (e) {
      print('Error downloading cover art from $url: $e');
      return null;
    }
  }

  /// Persist provided album art bytes; returns saved file path or null.
  Future<String?> saveAlbumArtBytes({required List<int> bytes, required String identifier}) async {
    try {
      return await _saveAlbumArtBytes(bytes, identifier);
    } catch (e) {
      print('Error saving provided album art bytes: $e');
      return null;
    }
  }

  /// Save album art from downloaded bytes
  Future<String?> _saveAlbumArtBytes(List<int> artData, String identifier) async {
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
