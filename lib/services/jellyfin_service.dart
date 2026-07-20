import 'dart:convert';
import 'package:http/http.dart' as http;

class JellyfinServerConfig {
  final String id;
  final String name;
  final String url;
  final String userId;
  final String token;
  final String? username;
  final String? password;

  JellyfinServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.userId,
    required this.token,
    this.username,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'userId': userId,
        'token': token,
        'username': username,
        'password': password,
      };

  factory JellyfinServerConfig.fromJson(Map<String, dynamic> json) => JellyfinServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        userId: json['userId'] as String,
        token: json['token'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
      );
}

class JellyfinItem {
  final String id;
  final String name;
  final bool isDirectory;
  final String streamUrl;
  final String? artist;
  final String? album;
  final String? artworkUrl;
  final String? type;

  JellyfinItem({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.streamUrl,
    this.artist,
    this.album,
    this.artworkUrl,
    this.type,
  });
}

class JellyfinService {
  static const String _clientName = 'Voxel Music Player';
  static const String _version = '1.0.0';

  /// Authenticate with Jellyfin server and return a completed server configuration.
  static Future<JellyfinServerConfig> authenticate({
    required String url,
    required String username,
    required String password,
  }) async {
    final cleanUrl = url.replaceAll(RegExp(r'/+$'), '');
    final authUrl = Uri.parse('$cleanUrl/Users/AuthenticateByName');

    // Jellyfin Authorization header details
    final authHeader = 'MediaBrowser Client="$_clientName", Device="Android Device", DeviceId="voxel_device_id", Version="$_version"';

    final response = await http.post(
      authUrl,
      headers: {
        'Content-Type': 'application/json',
        'X-Emby-Authorization': authHeader,
      },
      body: jsonEncode({
        'Username': username,
        'Pw': password,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Jellyfin connection failed: HTTP status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['AccessToken'] as String;
    final userMap = data['User'] as Map<String, dynamic>;
    final userId = userMap['Id'] as String;

    // Fetch server info to get server name
    String serverName = 'Jellyfin Server';
    try {
      final infoUrl = Uri.parse('$cleanUrl/System/Info');
      final infoRes = await http.get(
        infoUrl,
        headers: {
          'X-Emby-Token': token,
        },
      ).timeout(const Duration(seconds: 5));
      if (infoRes.statusCode == 200) {
        final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
        serverName = infoData['ServerName'] as String? ?? 'Jellyfin Server';
      }
    } catch (_) {}

    return JellyfinServerConfig(
      id: userId,
      name: serverName,
      url: cleanUrl,
      userId: userId,
      token: token,
      username: username,
      password: password,
    );
  }

  /// Lists views/folders at Jellyfin root context.
  static Future<List<JellyfinItem>> listLibraryViews(JellyfinServerConfig config) async {
    final cleanUrl = config.url.replaceAll(RegExp(r'/+$'), '');
    final itemsUrl = Uri.parse('$cleanUrl/Users/${config.userId}/Views');

    final response = await http.get(
      itemsUrl,
      headers: {
        'X-Emby-Token': config.token,
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Failed to load Jellyfin views: HTTP status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawList = data['Items'] as List<dynamic>? ?? [];

    final List<JellyfinItem> list = [];
    for (final item in rawList) {
      final id = item['Id'] as String;
      final name = item['Name'] as String? ?? 'Unknown Collection';
      list.add(JellyfinItem(
        id: id,
        name: name,
        isDirectory: true,
        streamUrl: '',
      ));
    }
    return list;
  }

  /// Lists items within a specific parent library or folder collection.
  static Future<List<JellyfinItem>> listItems(JellyfinServerConfig config, String parentId) async {
    final cleanUrl = config.url.replaceAll(RegExp(r'/+$'), '');
    final itemsUrl = Uri.parse(
      '$cleanUrl/Users/${config.userId}/Items?ParentId=$parentId&Fields=AudioChannels,PrimaryImageAspectRatio,SortName,Overview,ArtistItems,AlbumArtists',
    );

    final response = await http.get(
      itemsUrl,
      headers: {
        'X-Emby-Token': config.token,
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Failed to load Jellyfin items: HTTP status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawList = data['Items'] as List<dynamic>? ?? [];

    final List<JellyfinItem> list = [];
    for (final item in rawList) {
      final id = item['Id'] as String;
      final name = item['Name'] as String? ?? 'Unknown';
      final isFolder = item['IsFolder'] as bool? ?? false;
      final type = item['Type'] as String?;

      if (isFolder) {
        list.add(JellyfinItem(
          id: id,
          name: name,
          isDirectory: true,
          streamUrl: '',
        ));
      } else if (type == 'Audio') {
        // Build direct stream URL: Jellyfin Audio stream requires token parameter in URL query or auth headers
        final streamUrl = '$cleanUrl/Audio/$id/stream?static=true&api_key=${config.token}';
        
        // Artwork Primary Image
        String? artUrl;
        final hasImage = item['ImageTags'] != null && (item['ImageTags'] as Map<String, dynamic>).containsKey('Primary');
        if (hasImage) {
          artUrl = '$cleanUrl/Items/$id/Images/Primary?fillWidth=300&fillHeight=300&quality=90&api_key=${config.token}';
        }

        final artist = item['Artists'] != null && (item['Artists'] as List<dynamic>).isNotEmpty
            ? (item['Artists'] as List<dynamic>).first as String?
            : item['AlbumArtist'] as String?;

        final album = item['Album'] as String?;

        list.add(JellyfinItem(
          id: id,
          name: name,
          isDirectory: false,
          streamUrl: streamUrl,
          artist: artist,
          album: album,
          artworkUrl: artUrl,
          type: 'Audio',
        ));
      } else if (type == 'Photo') {
        // For photos, the primary image is the streamable item itself
        final photoUrl = '$cleanUrl/Items/$id/Images/Primary?api_key=${config.token}';
        list.add(JellyfinItem(
          id: id,
          name: name,
          isDirectory: false,
          streamUrl: photoUrl, // Pass image source URL directly as streamUrl
          artist: 'Jellyfin Photo',
          album: 'Photos',
          artworkUrl: photoUrl,
          type: 'Photo',
        ));
      } else if (type == 'Movie' || type == 'Video' || type == 'Episode') {
        // Build video stream URL (download or direct stream endpoint)
        final streamUrl = '$cleanUrl/Videos/$id/stream?static=true&api_key=${config.token}';
        String? artUrl;
        final hasImage = item['ImageTags'] != null && (item['ImageTags'] as Map<String, dynamic>).containsKey('Primary');
        if (hasImage) {
          artUrl = '$cleanUrl/Items/$id/Images/Primary?fillWidth=300&fillHeight=300&quality=90&api_key=${config.token}';
        }
        list.add(JellyfinItem(
          id: id,
          name: name,
          isDirectory: false,
          streamUrl: streamUrl,
          artist: 'Video file',
          album: 'Videos',
          artworkUrl: artUrl,
          type: 'Video',
        ));
      }
    }
    return list;
  }
}
