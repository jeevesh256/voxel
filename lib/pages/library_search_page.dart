import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../services/song_metadata_cache.dart';
import '../services/upnp_service.dart';
import '../services/webdav_service.dart';
import '../services/jellyfin_service.dart';
import '../widgets/radio_menu_sheet.dart';
import 'artist_page.dart';
import 'network_browser_page.dart';
import 'playlist_page.dart';

void pushMaterialPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => page),
  );
}

class LibrarySearchPage extends StatefulWidget {
  const LibrarySearchPage({super.key});

  @override
  State<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends State<LibrarySearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final SongMetadataCache _metadataCache = SongMetadataCache();
  String _query = '';
  String? _appDocumentsPath;

  @override
  void initState() {
    super.initState();
    _metadataCache.initialize();
    _loadDocumentsPath();
  }

  Future<void> _loadDocumentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) setState(() => _appDocumentsPath = dir.path);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _cachedArtistImagePath(String artistName) {
    final appPath = _appDocumentsPath;
    if (appPath == null || appPath.isEmpty) return null;
    final safeName = artistName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final filePath = '$appPath/artist_img_$safeName.jpg';
    if (File(filePath).existsSync()) return filePath;
    return null;
  }

  // ─── Artist name helpers (mirrors library_page) ──────────────────────────────

  String _normalizeArtistToken(String raw) {
    var s = raw.trim();
    s = s.replaceAll(
      RegExp(r'\s*[\(\[]\s*(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\s*[\)\]]',
          caseSensitive: false),
      '',
    ).trim();
    s = s.replaceAll(
      RegExp(r'\b(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\b',
          caseSensitive: false),
      '',
    ).trim();
    s = s.replaceAll(RegExp(r'^[\s\(\[\{]+|[\s\)\]\}\.,;:!]+$'), '').trim();
    return s.length < 2 ? '' : s;
  }

  List<String> _splitCompoundArtists(String raw) {
    return raw
        .split(RegExp(r'(?:,|;|&|\band\b|\bfeat\.?\b|\bft\.?\b|\bvs\.?\b|\bx\b)',
            caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> _extractFeaturedArtistsFromTitle(String title) {
    final featured = <String>[];
    final bracketMatch =
        RegExp(r'[\(\[]\s*(?:feat\.?|ft\.?)\s+(.+?)[\)\]]', caseSensitive: false)
            .firstMatch(title);
    if (bracketMatch != null) {
      featured.addAll(_splitCompoundArtists(bracketMatch.group(1)!.trim()));
    }
    final inlineFeat = RegExp(r'\b(?:feat\.?|ft\.?)\s+(.+)$', caseSensitive: false)
        .firstMatch(title)
        ?.group(1)
        ?.trim();
    if (inlineFeat != null && inlineFeat.isNotEmpty) {
      featured.addAll(_splitCompoundArtists(inlineFeat));
    }
    final unique = <String, String>{};
    for (final name in featured) {
      final normalized = _normalizeArtistToken(name);
      if (normalized.isEmpty) continue;
      unique.putIfAbsent(normalized.toLowerCase(), () => normalized);
    }
    return unique.values.toList();
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  Widget _solidThumbnail({required Color color, required IconData icon}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon,
          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 26),
    );
  }

  Widget _coloredPlaylistThumb(Color color) => Container(
        color: color,
        child: Center(
          child: Icon(Icons.queue_music_rounded,
              color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 32),
        ),
      );

  Widget _playlistThumbnail(dynamic playlist, AudioPlayerService audioService) {
    final accentColor = playlist.artworkColor != null
        ? Color(playlist.artworkColor as int)
        : Theme.of(context).colorScheme.tertiaryContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: playlist.artworkPath != null && (playlist.artworkPath as String).isNotEmpty
            ? Image.file(File(playlist.artworkPath as String),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _coloredPlaylistThumb(accentColor))
            : _coloredPlaylistThumb(accentColor),
      ),
    );
  }

  Widget _coloredPinnedFolderThumb(Color color, String type) => Container(
        color: color,
        child: Center(
          child: Icon(
            type == 'upnp' ? Icons.dns_rounded : Icons.cloud_rounded,
            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            size: 28,
          ),
        ),
      );

  Widget _pinnedFolderThumbnail(dynamic folder) {
    final accentColor = folder.artworkColor != null
        ? Color(folder.artworkColor as int)
        : Theme.of(context).colorScheme.primaryContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: folder.artworkPath != null && (folder.artworkPath as String).isNotEmpty
            ? Image.file(File(folder.artworkPath as String),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _coloredPinnedFolderThumb(accentColor, folder.type as String))
            : _coloredPinnedFolderThumb(accentColor, folder.type as String),
      ),
    );
  }

  Widget _artistAvatar(String? albumArt, String artistName) {
    final initials = artistName.isNotEmpty ? artistName[0].toUpperCase() : '?';
    final hue = (artistName.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    final avatarColor = HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor();
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipOval(
        child: albumArt != null && albumArt.isNotEmpty
            ? Image.file(File(albumArt),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _initialsAvatar(initials, avatarColor))
            : _initialsAvatar(initials, avatarColor),
      ),
    );
  }

  Widget _initialsAvatar(String initials, Color color) => Container(
        color: color,
        alignment: Alignment.center,
        child: Text(initials,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)),
      );

  Widget _row({
    required Widget thumbnail,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: scheme.primary.withOpacity(0.08),
        highlightColor: scheme.primary.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 0, top: 8, bottom: 8),
          child: Row(
            children: [
              thumbnail,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 72, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text('No matches',
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Try a different search term',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      );

  Widget _hint() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_rounded, size: 64, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text('Search your library',
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Playlists, artists, network folders, radios',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      );

  // ─── Main results builder ─────────────────────────────────────────────────────

  Widget _buildResults(double bottomPad) {
    return Consumer2<AudioPlayerService, SettingsModel>(
      builder: (context, audioService, settings, _) {
        final q = _query.toLowerCase().trim();

        bool matches(String name, String subtitle) =>
            name.toLowerCase().contains(q) || subtitle.toLowerCase().contains(q);

        // ── Playlists & folders ──────────────────────────────────────────────
        final likedCount = audioService.getPlaylistSongs('liked').length;
        final offlineCount = audioService.getPlaylistSongs('offline').length;
        final List<Widget> playlistItems = [];

        if (matches('Liked Songs', '$likedCount songs'))
          playlistItems.add(_row(
            thumbnail: _solidThumbnail(
                color: Theme.of(context).colorScheme.primaryContainer,
                icon: Icons.favorite_rounded),
            title: 'Liked Songs',
            subtitle: '$likedCount songs',
            onTap: () => pushMaterialPage(context,
                const PlaylistPage(playlistId: 'liked', title: 'Liked Songs', icon: Icons.favorite)),
          ));

        if (matches('Offline', '$offlineCount songs'))
          playlistItems.add(_row(
            thumbnail: _solidThumbnail(
                color: Theme.of(context).colorScheme.secondaryContainer,
                icon: Icons.offline_pin_rounded),
            title: 'Offline',
            subtitle: '$offlineCount songs',
            onTap: () => pushMaterialPage(context,
                const PlaylistPage(playlistId: 'offline', title: 'Offline', icon: Icons.offline_pin)),
          ));

        for (final p in audioService.customPlaylists) {
          final n = audioService.getPlaylistSongs(p.id).length;
          final sub = '$n ${n == 1 ? 'song' : 'songs'}';
          if (!matches(p.name, sub)) continue;
          playlistItems.add(_row(
            thumbnail: _playlistThumbnail(p, audioService),
            title: p.name,
            subtitle: sub,
            onTap: () => pushMaterialPage(context,
                PlaylistPage(playlistId: p.id, title: p.name, icon: Icons.queue_music, allowReorder: true)),
            trailing: IconButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[400]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => _showPlaylistOptions(p, audioService),
            ),
          ));
        }

        for (final folder in settings.pinnedFolders) {
          final typeLabel = folder.type == 'webdav'
              ? 'WebDAV'
              : folder.type == 'jellyfin'
                  ? 'Jellyfin'
                  : folder.type == 'upnp'
                      ? 'UPnP'
                      : folder.type;
          final sub = '${folder.serverName} • $typeLabel Network Folder';
          if (!matches(folder.name, sub) &&
              !folder.serverName.toLowerCase().contains(q) &&
              !typeLabel.toLowerCase().contains(q) &&
              !'network'.contains(q)) continue;

          final webdavConfig = folder.type == 'webdav'
              ? settings.webdavServers.firstWhere(
                  (s) => s.id == folder.serverId || s.url == folder.serverId,
                  orElse: () => WebdavServerConfig(
                      id: folder.serverId, name: folder.serverName, url: folder.serverId))
              : null;
          final jellyfinConfig = folder.type == 'jellyfin'
              ? settings.jellyfinServers.firstWhere(
                  (s) => s.id == folder.serverId,
                  orElse: () => JellyfinServerConfig(
                      id: folder.serverId,
                      name: folder.serverName,
                      url: '',
                      userId: folder.serverId,
                      token: ''))
              : null;

          playlistItems.add(_row(
            thumbnail: _pinnedFolderThumbnail(folder),
            title: folder.name,
            subtitle: sub,
            trailing: const SizedBox(width: 8),
            onTap: () {
              if (folder.type == 'upnp') {
                pushMaterialPage(
                    context,
                    NetworkBrowserPage(
                        upnpDevice: UpnpDevice(
                            location: folder.serverId,
                            friendlyName: folder.serverName,
                            controlUrl: folder.controlUrl ?? ''),
                        initialObjectId: folder.path,
                        initialFolderName: folder.name,
                        pinnedFolder: folder));
              } else if (folder.type == 'webdav') {
                pushMaterialPage(
                    context,
                    NetworkBrowserPage(
                        webdavConfig: webdavConfig,
                        initialUrl: folder.path,
                        initialFolderName: folder.name,
                        pinnedFolder: folder));
              } else if (folder.type == 'jellyfin') {
                pushMaterialPage(
                    context,
                    NetworkBrowserPage(
                        jellyfinConfig: jellyfinConfig,
                        initialObjectId: folder.path,
                        initialFolderName: folder.name,
                        pinnedFolder: folder));
              }
            },
          ));
        }

        // ── Artists ──────────────────────────────────────────────────────────
        final audioFiles = audioService.getPlaylistSongs('offline');
        final artistMap = <String, List<File>>{};
        final artistAlbumArt = <String, String>{};
        for (var file in audioFiles) {
          final song = _metadataCache.createSongFromFile(file);
          final rawArtist = song.artist;
          if (rawArtist == 'Unknown Artist' || rawArtist.isEmpty) continue;
          final artistsByKey = <String, String>{};
          for (final artist in [
            ..._splitCompoundArtists(rawArtist),
            ..._extractFeaturedArtistsFromTitle(song.title),
          ]) {
            final n = _normalizeArtistToken(artist);
            if (n.isEmpty) continue;
            artistsByKey.putIfAbsent(n.toLowerCase(), () => n);
          }
          for (final artist in artistsByKey.values) {
            artistMap.putIfAbsent(artist, () => []).add(file);
            if (!artistAlbumArt.containsKey(artist) &&
                song.albumArt.isNotEmpty &&
                !song.albumArt.startsWith('http') &&
                File(song.albumArt).existsSync()) {
              artistAlbumArt[artist] = song.albumArt;
            }
          }
        }
        final matchedArtists = artistMap.keys
            .where((a) => a.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final List<Widget> artistItems = matchedArtists.map((artist) {
          final songs = artistMap[artist]!;
          final cached = _cachedArtistImagePath(artist);
          final albumArt = cached ?? artistAlbumArt[artist];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => pushMaterialPage(
                  context,
                  ArtistPage(
                      artistName: artist, songs: songs, artistArtwork: albumArt)),
              splashColor: Colors.white.withOpacity(0.04),
              highlightColor: Colors.white.withOpacity(0.03),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _artistAvatar(albumArt, artist),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(artist,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(
                              '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList();

        // ── Radios ───────────────────────────────────────────────────────────
        final allRadios = audioService.getPlaylistRadios('favourite_radios');
        final matchedRadios = allRadios
            .where((r) => (r.name as String).toLowerCase().contains(q))
            .toList();

        final List<Widget> radioItems = matchedRadios.map((radio) {
          final artworkUrl = radio.artworkUrl as String? ?? '';
          final hasArt = artworkUrl.isNotEmpty;
          final genre = radio.genre as String? ?? '';
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => audioService.playRadioStation(radio),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  builder: (ctx) => RadioMenuSheet(
                    radio: radio,
                    accentColor: Theme.of(context).colorScheme.primary,
                    audioService: audioService,
                    onRemove: () =>
                        audioService.removeRadioFromPlaylist('favourite_radios', radio),
                  ),
                );
              },
              splashColor: Colors.white.withOpacity(0.04),
              highlightColor: Colors.white.withOpacity(0.03),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 0, top: 6, bottom: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: hasArt
                            ? CachedNetworkImage(
                                imageUrl: artworkUrl,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                errorListener: (_) {},
                                placeholder: (_, __) => Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer),
                                errorWidget: (_, __, ___) => Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Icon(Icons.radio_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      size: 24),
                                ),
                              )
                            : Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Icon(Icons.radio_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    size: 24),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(radio.name as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (genre.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(genre,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useRootNavigator: true,
                        builder: (ctx) => RadioMenuSheet(
                          radio: radio,
                          accentColor: Theme.of(context).colorScheme.primary,
                          audioService: audioService,
                          onRemove: () => audioService
                              .removeRadioFromPlaylist('favourite_radios', radio),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList();

        // ── Assemble ─────────────────────────────────────────────────────────
        final hasResults =
            playlistItems.isNotEmpty || artistItems.isNotEmpty || radioItems.isNotEmpty;

        if (!hasResults) {
          return Center(child: _emptyState());
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: 4, bottom: bottomPad),
          children: [
            if (playlistItems.isNotEmpty) ...[
              _sectionHeader('PLAYLISTS', playlistItems.length),
              ...playlistItems,
            ],
            if (artistItems.isNotEmpty) ...[
              _sectionHeader('ARTISTS', artistItems.length),
              ...artistItems,
            ],
            if (radioItems.isNotEmpty) ...[
              _sectionHeader('RADIOS', radioItems.length),
              ...radioItems,
            ],
          ],
        );
      },
    );
  }

  void _showPlaylistOptions(dynamic playlist, AudioPlayerService audioService) {
    // Delegate to library page by just pushing the playlist page context options
    // (no-op for now, can be expanded)
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 70.0;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        backgroundColor: scheme.surface,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        titleSpacing: 0,
        toolbarHeight: 64,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: scheme.onSurface),
                ),
              ),
              // Search field
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Playlists, artists, radios…',
                      hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: _query.isNotEmpty
                              ? scheme.primary
                              : Colors.grey[500],
                          size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? GestureDetector(
                              onTap: () =>
                                  setState(() {
                                    _controller.clear();
                                    _query = '';
                                  }),
                              child: Icon(Icons.cancel_rounded,
                                  size: 18, color: Colors.grey[500]),
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _query.trim().isEmpty
            ? Center(key: const ValueKey('hint'), child: _hint())
            : _buildResults(bottomPad),
      ),
    );
  }
}
