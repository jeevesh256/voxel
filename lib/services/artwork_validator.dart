bool isValidArtwork(String url) {
  if (url.isEmpty) return false;
  
  // Local file paths or file URIs are always valid
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return true;
  }

  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final thumbParam = uri.queryParameters['t']?.toLowerCase() ?? '';

  // Google thumbnail URLs are often short-lived and return 404s.
  if (host.startsWith('encrypted-tbn') && host.endsWith('gstatic.com')) {
    return false;
  }

  // Known station-logo CDN entries that frequently fail DNS resolution.
  if (host == 'de8as167a043l.cloudfront.net' ||
      path.contains('/styles/images/logosplus/')) {
    return false;
  }

  // Some laut.fm thumbnail variants are unstable and frequently return 404.
  if (host == 'assets.laut.fm' && thumbParam.startsWith('_')) {
    return false;
  }

  // Wikimedia Commons URLs fail in Flutter because Wikimedia CDN requires a User-Agent header,
  // returning HTTP 400 or 403. Reject them so we fall back to our clean themed radio vector icon.
  if (host.contains('wikimedia.org')) {
    return false;
  }

  // Reject generic /icon.png and favicon-like paths that often return HTTP errors
  if (path.endsWith('/icon.png') ||
      path.endsWith('/icon.ico') ||
      path.endsWith('/favicon.ico')) {
    return false;
  }

  if (path.contains('favicon')) {
    return false;
  }

  // Reject images containing indicators of small dimensions (e.g. 16x16, 32x32, 48x48, 64x64, 96x96, 120x120, etc.)
  final lowResPatterns = [
    RegExp(r'[-_](16|32|48|64|96|120|150)\b'), // e.g. logo-32.png, logo_48.jpg
    RegExp(r'\b(16|32|48|64|96|120|150)x(16|32|48|64|96|120|150)\b'), // e.g. 32x32.png
    RegExp(r'[-_]thumb(nail)?\b'), // e.g. logo_thumb.png
    RegExp(r'[-_]small\b'), // e.g. logo_small.png
  ];
  for (final pattern in lowResPatterns) {
    if (pattern.hasMatch(url.toLowerCase())) {
      return false;
    }
  }

  // Parse iHeartRadio ops parameter (e.g. ops=fit(80,80) or contain(167,167))
  final opsParam = uri.queryParameters['ops'] ?? '';
  if (opsParam.isNotEmpty) {
    final match = RegExp(r'(fit|contain|resize)\((\d+),(\d+)\)').firstMatch(opsParam.toLowerCase());
    if (match != null) {
      final width = int.tryParse(match.group(2) ?? '') ?? 0;
      final height = int.tryParse(match.group(3) ?? '') ?? 0;
      if (width < 250 || height < 250) {
        return false; // Reject blurry rescaled iHeart images
      }
    }
  }

  // General scanner for query parameters that indicate image size/dimension (w, h, width, height, size, resize, etc.)
  for (final entry in uri.queryParameters.entries) {
    final key = entry.key.toLowerCase();
    if (key == 'w' || key == 'h' || key == 'width' || key == 'height' || key == 'size' || key == 'resize') {
      final val = int.tryParse(entry.value) ?? 0;
      if (val > 0 && val < 250) {
        return false; // Reject any image dimension less than 250px
      }
    }
  }

  return host.isNotEmpty &&
      !path.endsWith('.ico') &&
      !path.endsWith('.svg') &&
      !path.endsWith('.bmp');
}
