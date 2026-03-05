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

class ITunesArtist {
  final String artistName;
  final String primaryGenre;
  final String artistLinkUrl;
  final int artistId;

  ITunesArtist({
    required this.artistName,
    required this.primaryGenre,
    required this.artistLinkUrl,
    required this.artistId,
  });
}

class ITunesAlbum {
  final String albumName;
  final String artworkUrl;

  ITunesAlbum({
    required this.albumName,
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

  Future<ITunesArtist?> searchArtist({required String artistName}) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'term': artistName,
      'entity': 'musicArtist',
      'limit': '1',
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>? ?? [];

      if (results.isEmpty) return null;

      final item = results.first as Map<String, dynamic>;
      return ITunesArtist(
        artistName: item['artistName'] as String? ?? '',
        primaryGenre: item['primaryGenreName'] as String? ?? '',
        artistLinkUrl: item['artistLinkUrl'] as String? ?? '',
        artistId: item['artistId'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ITunesAlbum>> getArtistAlbumArtworks({required int artistId, int limit = 10}) async {
    final uri = Uri.parse('https://itunes.apple.com/lookup').replace(queryParameters: {
      'id': '$artistId',
      'entity': 'album',
      'limit': '$limit',
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];

      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>? ?? [];

      // Skip first result (artist info) and get albums
      final albums = results.skip(1).toList();

      return albums
          .map((item) {
            final albumName = item['collectionName'] as String? ?? '';
            final artwork = (item['artworkUrl100'] as String? ?? '')
                .replaceAll('100x100bb', '600x600bb');
            return ITunesAlbum(
              albumName: albumName,
              artworkUrl: artwork,
            );
          })
          .where((album) => album.artworkUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
