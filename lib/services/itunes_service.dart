import 'dart:convert';
import 'package:http/http.dart' as http;

class ITunesTrack {
  final String trackName;
  final String artistName;
  final String collectionName;
  final String artworkUrl;

  ITunesTrack({
    required this.trackName,
    required this.artistName,
    required this.collectionName,
    required this.artworkUrl,
  });
}

class ITunesService {
  static const String _baseUrl = 'https://itunes.apple.com/search';

  Future<List<ITunesTrack>> searchTracks({required String term, int limit = 10}) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'term': term,
      'entity': 'song',
      'limit': '$limit',
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];

      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>? ?? [];

      return results.map((item) {
        final trackName = item['trackName'] as String? ?? '';
        final artistName = item['artistName'] as String? ?? '';
        final collectionName = item['collectionName'] as String? ?? '';
        final artwork = (item['artworkUrl100'] as String? ?? '').replaceAll('100x100bb', '1000x1000bb');

        return ITunesTrack(
          trackName: trackName,
          artistName: artistName,
          collectionName: collectionName,
          artworkUrl: artwork,
        );
      }).where((t) => t.trackName.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }
}
