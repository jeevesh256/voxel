import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class UpnpDevice {
  final String location;
  final String friendlyName;
  final String controlUrl;

  UpnpDevice({
    required this.location,
    required this.friendlyName,
    required this.controlUrl,
  });
}

class UpnpMediaItem {
  final String id;
  final String title;
  final bool isContainer;
  final String? streamUrl;
  final String? artist;
  final String? album;
  final String? artworkUrl;
  final String? type;

  UpnpMediaItem({
    required this.id,
    required this.title,
    required this.isContainer,
    this.streamUrl,
    this.artist,
    this.album,
    this.artworkUrl,
    this.type,
  });
}

/// Thrown when a UPnP server cannot be reached or returns an error.
class UpnpConnectionException implements Exception {
  final String message;
  const UpnpConnectionException(this.message);
  @override
  String toString() => message;
}

class UpnpService {
  static const String _ssdpIp = '239.255.255.250';
  static const int _ssdpPort = 1900;

  /// Discover UPnP Media Servers on the local network using SSDP.
  static Future<List<UpnpDevice>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    final List<UpnpDevice> devices = [];
    final Set<String> locations = {};
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.multicastLoopback = false;

      final mSearch =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_ssdpIp:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:service:ContentDirectory:1\r\n'
          '\r\n';

      final data = utf8.encode(mSearch);
      final multicastAddress = InternetAddress(_ssdpIp);
      socket.send(data, multicastAddress, _ssdpPort);

      // Also send a generic search target just in case
      final mSearchAll =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_ssdpIp:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: upnp:rootdevice\r\n'
          '\r\n';
      socket.send(utf8.encode(mSearchAll), multicastAddress, _ssdpPort);

      final completer = Completer<List<UpnpDevice>>();
      
      final subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final packet = socket?.receive();
          if (packet == null) return;

          final response = utf8.decode(packet.data, allowMalformed: true);
          final location = _getHeader(response, 'LOCATION');
          if (location != null && !locations.contains(location)) {
            locations.add(location);
            _fetchDeviceDescription(location).then((device) {
              if (device != null) {
                devices.add(device);
              }
            }).catchError((e) {
              debugPrint('Error fetching device description: $e');
            });
          }
        }
      });

      await Future.delayed(timeout);
      await subscription.cancel();
      return devices;
    } catch (e) {
      debugPrint('UPnP discovery error: $e');
      return [];
    } finally {
      socket?.close();
    }
  }

  static String? _getHeader(String response, String headerName) {
    final lines = response.split('\r\n');
    for (final line in lines) {
      if (line.toLowerCase().startsWith('${headerName.toLowerCase()}:')) {
        return line.substring(headerName.length + 1).trim();
      }
    }
    return null;
  }

  static Future<UpnpDevice?> _fetchDeviceDescription(String locationUrl) async {
    try {
      final response = await http.get(Uri.parse(locationUrl)).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;

      final document = xml.XmlDocument.parse(response.body);
      
      // Look for FriendlyName
      final friendlyNameNode = document.findAllElements('friendlyName').firstOrNull;
      final friendlyName = friendlyNameNode?.innerText ?? 'DLNA Server';

      // Look for urn:schemas-upnp-org:service:ContentDirectory:1
      final services = document.findAllElements('service');
      String? controlPath;
      
      for (final service in services) {
        final serviceType = service.findElements('serviceType').firstOrNull?.innerText;
        if (serviceType != null && serviceType.contains('ContentDirectory')) {
          controlPath = service.findElements('controlURL').firstOrNull?.innerText;
          break;
        }
      }

      if (controlPath == null) return null;

      // Resolve relative control URL
      final baseUri = Uri.parse(locationUrl);
      final controlUrl = baseUri.resolve(controlPath).toString();

      return UpnpDevice(
        location: locationUrl,
        friendlyName: friendlyName,
        controlUrl: controlUrl,
      );
    } catch (e) {
      debugPrint('UPnP xml fetch error: $e');
      return null;
    }
  }

  /// Browse a UPnP ContentDirectory.
  /// [objectId] is the folder ID. Root is usually '0'.
  static Future<List<UpnpMediaItem>> browse(String controlUrl, String objectId) async {
    final body =
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\n'
        '  <s:Body>\n'
        '    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">\n'
        '      <ObjectID>$objectId</ObjectID>\n'
        '      <BrowseFlag>BrowseDirectChildren</BrowseFlag>\n'
        '      <Filter>*</Filter>\n'
        '      <StartingIndex>0</StartingIndex>\n'
        '      <RequestedCount>999</RequestedCount>\n'
        '      <SortCriteria></SortCriteria>\n'
        '    </u:Browse>\n'
        '  </s:Body>\n'
        '</s:Envelope>';

    try {
      final response = await http.post(
        Uri.parse(controlUrl),
        headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPACTION': '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"',
        },
        body: body,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('SOAP browse request failed: ${response.statusCode}');
      }

      final doc = xml.XmlDocument.parse(response.body);
      final resultNode = doc.findAllElements('Result').firstOrNull;
      if (resultNode == null) return [];

      // The SOAP Result contains escaped XML/HTML. We decode it.
      final resultXmlString = resultNode.innerText;
      final didlDoc = xml.XmlDocument.parse(resultXmlString);
      
      final List<UpnpMediaItem> items = [];

      // Parse containers (folders)
      for (final node in didlDoc.findAllElements('container')) {
        final id = node.getAttribute('id') ?? '';
        final title = node.findElements('dc:title').firstOrNull?.innerText ?? 'Unnamed Folder';
        items.add(UpnpMediaItem(
          id: id,
          title: title,
          isContainer: true,
        ));
      }

      // Parse items (songs)
      for (final node in didlDoc.findAllElements('item')) {
        final id = node.getAttribute('id') ?? '';
        final title = node.findElements('dc:title').firstOrNull?.innerText ?? 'Unnamed Song';
        final artist = node.findElements('upnp:artist').firstOrNull?.innerText;
        final album = node.findElements('upnp:album').firstOrNull?.innerText;
        final artworkUrl = node.findElements('upnp:albumArtURI').firstOrNull?.innerText;
        
        final upnpClass = node.findElements('upnp:class').firstOrNull?.innerText ?? '';
        final isPhoto = upnpClass.contains('imageItem') || upnpClass.contains('photo');
        final isVideo = upnpClass.contains('videoItem') || upnpClass.contains('movie');

        // Find stream URL from <res> element
        String? streamUrl;
        final resNode = node.findElements('res').firstOrNull;
        if (resNode != null) {
          streamUrl = resNode.innerText.trim();
          final protocolInfo = resNode.getAttribute('protocolInfo') ?? '';
          
          if (isPhoto || protocolInfo.contains('image/')) {
            // Yes, it is a photo
          } else if (isVideo || protocolInfo.contains('video/')) {
            // Yes, it is a video
          } else if (!protocolInfo.contains('audio/')) {
            // Check extension fallback for audio files
            final ext = streamUrl.toLowerCase();
            if (!ext.endsWith('.mp3') && !ext.endsWith('.m4a') && !ext.endsWith('.wav') && !ext.endsWith('.flac') && !ext.endsWith('.aac') && !ext.endsWith('.ogg')) {
              // Check extension fallback for video files
              if (ext.endsWith('.mp4') || ext.endsWith('.mkv') || ext.endsWith('.avi') || ext.endsWith('.mov') || ext.endsWith('.webm')) {
                // Yes, it is a video
              } else {
                // Ignore non-audio, non-image, non-video files
                streamUrl = null;
              }
            }
          }
        }

        if (streamUrl != null) {
          final computedIsVideo = isVideo || (resNode != null && (resNode.getAttribute('protocolInfo') ?? '').contains('video/')) || 
              (streamUrl.toLowerCase().endsWith('.mp4') || streamUrl.toLowerCase().endsWith('.mkv') || streamUrl.toLowerCase().endsWith('.avi') || streamUrl.toLowerCase().endsWith('.mov') || streamUrl.toLowerCase().endsWith('.webm'));
          items.add(UpnpMediaItem(
            id: id,
            title: title,
            isContainer: false,
            streamUrl: streamUrl,
            artist: computedIsVideo ? 'Video file' : (isPhoto ? 'Plex Photo' : artist),
            album: computedIsVideo ? 'Videos' : (isPhoto ? 'Photos' : album),
            artworkUrl: artworkUrl ?? (isPhoto ? streamUrl : null),
            type: computedIsVideo ? 'Video' : (isPhoto ? 'Photo' : 'Audio'),
          ));
        }
      }

      return items;
    } catch (e) {
      debugPrint('UPnP browse error: $e');
      if (e is SocketException) {
        throw const UpnpConnectionException(
            'Cannot reach the server. Make sure it is on and connected to the same network.');
      } else if (e is TimeoutException) {
        throw const UpnpConnectionException(
            'Connection timed out. The server may be busy or unreachable.');
      } else if (e is UpnpConnectionException) {
        rethrow;
      } else {
        throw UpnpConnectionException('Failed to load folder: ${e.runtimeType}');
      }
    }
  }
}
