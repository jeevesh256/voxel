import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MusicBrainzRecording {
  final String id;
  final String title;
  final String artist;
  final String? releaseId;
  final String? album;
  final int score;

  MusicBrainzRecording({
    required this.id,
    required this.title,
    required this.artist,
    this.releaseId,
    this.album,
    required this.score,
  });

  factory MusicBrainzRecording.fromJson(Map<String, dynamic> json) {
    String artist = 'Unknown Artist';
    if (json['artist-credit'] != null && (json['artist-credit'] as List).isNotEmpty) {
      artist = json['artist-credit'][0]['name'] ?? 'Unknown Artist';
    }

    String? releaseId;
    String? album;
    if (json['releases'] != null && (json['releases'] as List).isNotEmpty) {
      final firstRelease = json['releases'][0];
      releaseId = firstRelease['id'];
      album = firstRelease['title'];
    }

    return MusicBrainzRecording(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: artist,
      releaseId: releaseId,
      album: album,
      score: json['score'] ?? 0,
    );
  }
}

class MusicBrainzService {
  static const String _baseUrl = 'https://musicbrainz.org/ws/2';
  static const String _userAgent = 'Voxel/1.0.0 (https://github.com/jeevesh256/voxel)';
  
  // Rate limiting: MusicBrainz allows 1 request per second
  static DateTime _lastRequestTime = DateTime(2000);
  static const Duration _minRequestInterval = Duration(seconds: 1);

  /// Search for recordings by artist and title
  Future<List<MusicBrainzRecording>> searchRecording({
    required String title,
    String? artist,
    int limit = 10,
  }) async {
    await _enforceRateLimit();

    // Build query string
    String query = 'recording:"$title"';
    if (artist != null && artist.isNotEmpty && artist != 'Unknown Artist') {
      query += ' AND artist:"$artist"';
    }

    final uri = Uri.parse('$_baseUrl/recording/').replace(
      queryParameters: {
        'query': query,
        'fmt': 'json',
        'limit': '$limit',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final recordings = <MusicBrainzRecording>[];

        if (data['recordings'] != null) {
          for (var recording in data['recordings']) {
            recordings.add(MusicBrainzRecording.fromJson(recording));
          }
        }

        return recordings;
      } else {
        print('MusicBrainz API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error searching MusicBrainz: $e');
      return [];
    }
  }

  /// Get album art URL from Cover Art Archive
  String? getCoverArtUrl(String releaseId, {int size = 500}) {
    if (releaseId.isEmpty) return null;
    return 'https://coverartarchive.org/release/$releaseId/front-$size';
  }

  /// Check if cover art exists for a release
  Future<bool> hasCoverArt(String releaseId) async {
    if (releaseId.isEmpty) return false;
    
    await _enforceRateLimit();

    final uri = Uri.parse('https://coverartarchive.org/release/$releaseId');

    try {
      final response = await http.head(uri);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Download cover art and return bytes
  Future<List<int>?> downloadCoverArt(String releaseId, {int size = 500}) async {
    final url = getCoverArtUrl(releaseId, size: size);
    if (url == null) return null;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Error downloading cover art: $e');
      return null;
    }
  }

  /// Enforce rate limit of 1 request per second
  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);

    if (timeSinceLastRequest < _minRequestInterval) {
      final waitTime = _minRequestInterval - timeSinceLastRequest;
      await Future.delayed(waitTime);
    }

    _lastRequestTime = DateTime.now();
  }
}
