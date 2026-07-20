import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class WebdavServerConfig {
  final String id;
  final String name;
  final String url;
  final String? username;
  final String? password;

  WebdavServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.username,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
      };

  factory WebdavServerConfig.fromJson(Map<String, dynamic> json) => WebdavServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
      );
}

class WebdavItem {
  final String path;
  final String name;
  final bool isDirectory;
  final String streamUrl;

  WebdavItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.streamUrl,
  });
}

class WebdavService {
  /// Fetches directory listing for a given WebDAV path (relative or absolute URL).
  static Future<List<WebdavItem>> list(
    WebdavServerConfig config,
    String targetUrl,
  ) async {
    final Map<String, String> headers = {
      'Depth': '1',
      'Content-Type': 'application/xml',
    };

    if (config.username != null && config.password != null) {
      final auth = base64.encode(utf8.encode('${config.username}:${config.password}'));
      headers['Authorization'] = 'Basic $auth';
    }

    final body =
        '<?xml version="1.0" encoding="utf-8" ?>\n'
        '<d:propfind xmlns:d="DAV:">\n'
        '  <d:prop>\n'
        '    <d:resourcetype/>\n'
        '    <d:getcontenttype/>\n'
        '    <d:getcontentlength/>\n'
        '  </d:prop>\n'
        '</d:propfind>';

    try {
      final response = await http.post(
        Uri.parse(targetUrl),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 207 && response.statusCode != 200) {
        throw Exception('Failed to list directory: HTTP status ${response.statusCode}');
      }

      final document = xml.XmlDocument.parse(response.body);
      final responses = document.findAllElements('d:response');
      
      // Fallback search target if DAV namespace uses a different prefix
      final listResponses = responses.isNotEmpty
          ? responses
          : document.findAllElements('D:response').isNotEmpty
              ? document.findAllElements('D:response')
              : document.findAllElements('response');

      final List<WebdavItem> items = [];
      final baseUri = Uri.parse(config.url);

      for (final resNode in listResponses) {
        final hrefNode = resNode.findAllElements('d:href').firstOrNull ??
            resNode.findAllElements('D:href').firstOrNull ??
            resNode.findAllElements('href').firstOrNull;
            
        if (hrefNode == null) continue;

        String href = Uri.decodeFull(hrefNode.innerText);
        
        // Resolve absolute stream URL
        final resolvedUri = baseUri.resolve(href);
        final fullStreamUrl = resolvedUri.toString();

        // Parse path/filename
        final name = _getBasename(resolvedUri.path);

        // Determine if it's a directory
        final resTypeNode = resNode.findAllElements('d:resourcetype').firstOrNull ??
            resNode.findAllElements('D:resourcetype').firstOrNull ??
            resNode.findAllElements('resourcetype').firstOrNull;

        final isDirectory = resTypeNode != null &&
            (resTypeNode.findAllElements('d:collection').isNotEmpty ||
             resTypeNode.findAllElements('D:collection').isNotEmpty ||
             resTypeNode.findAllElements('collection').isNotEmpty);

        // Exclude the parent directory itself from the results
        final requestUri = Uri.parse(targetUrl);
        if (resolvedUri.path.replaceAll(RegExp(r'/+$'), '') ==
            requestUri.path.replaceAll(RegExp(r'/+$'), '')) {
          continue;
        }

        if (isDirectory) {
          items.add(WebdavItem(
            path: fullStreamUrl,
            name: name,
            isDirectory: true,
            streamUrl: fullStreamUrl,
          ));
        } else {
          // Check if it's an audio or image file
          if (_isAudioFile(name) || _isImageFile(name)) {
            items.add(WebdavItem(
              path: fullStreamUrl,
              name: name,
              isDirectory: false,
              streamUrl: fullStreamUrl,
            ));
          }
        }
      }

      // Sort: Directories first, then alphabetically by name
      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return items;
    } catch (e) {
      debugPrint('Webdav browse error: $e');
      rethrow;
    }
  }

  static String _getBasename(String path) {
    final cleanPath = path.replaceAll(RegExp(r'/+$'), '');
    final idx = cleanPath.lastIndexOf('/');
    if (idx == -1) return cleanPath;
    return cleanPath.substring(idx + 1);
  }

  static bool _isAudioFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg');
  }

  static bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.svg');
  }
}
