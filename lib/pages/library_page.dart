import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/settings_model.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/radio_playback_guard.dart';
import '../services/storage_service.dart';
import '../services/song_metadata_cache.dart';
import '../widgets/voxel_toast.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/radio_menu_sheet.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'playlist_page.dart';
import 'favourite_radios_page.dart';
import 'artist_page.dart';
import '../services/upnp_service.dart';
import '../services/webdav_service.dart';
import '../services/jellyfin_service.dart';
import 'network_browser_page.dart';
import 'library_search_page.dart';

enum LibrarySortOption { name, songCount }

void pushMaterialPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          RepaintBoundary(child: page),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        ));
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    ),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  bool handleBack() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      return true;
    }
    return false;
  }

  void switchTab(int index) {
    if (mounted && index >= 0 && index < _tabController.length) {
      _tabController.animateTo(index);
    }
  }
  final StorageService _storageService = StorageService();
  final SongMetadataCache _metadataCache = SongMetadataCache();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  double? _dragStartX;
  String? _appDocumentsPath;

  // Per-tab filters are no longer driven by an inline search bar;
  // search lives in LibrarySearchPage. Keep this field as '' so the
  // existing per-tab filter expressions compile without modification.
  final String _searchQuery = '';
  LibrarySortOption _sortOption = LibrarySortOption.name;
  bool _isAscending = true;
  bool _isScrollingVertically = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 3,
        vsync: this,
        animationDuration: const Duration(milliseconds: 300));
    _metadataCache.initialize();
    _loadAppDocumentsPath();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioService = context.read<AudioPlayerService>();
      final offlineSongs = audioService.getPlaylistSongs('offline');
      if (offlineSongs.isEmpty) {
        _loadAudioFiles();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAppDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!mounted) {
      _appDocumentsPath = directory.path;
      return;
    }
    setState(() {
      _appDocumentsPath = directory.path;
    });
  }

  String? _cachedArtistImagePath(String artistName) {
    final appPath = _appDocumentsPath;
    if (appPath == null || appPath.isEmpty) return null;
    final safeName = artistName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final filePath = '$appPath/artist_img_$safeName.jpg';
    if (File(filePath).existsSync()) return filePath;
    return null;
  }

  Future<void> _loadAudioFiles() async {
    try {
      final settings = context.read<SettingsModel>();
      final entities = await _storageService.getAudioFiles(
        paths: settings.sourcePaths.toList(),
      );
      final files = entities.whereType<File>().toList();
      if (mounted) {
        context.read<AudioPlayerService>().loadOfflineFiles(files);
      }
    } catch (e) {
      debugPrint('Error loading audio files: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight +
        70.0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 68,
        title: const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Library',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Playlists'),
                      Tab(text: 'Artists'),
                      Tab(text: 'Radios'),
                    ],
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    unselectedLabelColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7),
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                    onPressed: () => pushMaterialPage(
                        context, const LibrarySearchPage()),
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.sort, color: Colors.grey[400], size: 20),
                    onPressed: _showLibrarySortSheet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          _dragStartX = details.globalPosition.dx;
        },
        onHorizontalDragEnd: (details) {
          // If the swipe started from the edge, it's an OS back navigation gesture.
          // Ignore it entirely so we don't accidentally switch tabs.
          if (_dragStartX != null) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (_dragStartX! < 40.0 || _dragStartX! > screenWidth - 40.0) {
              return;
            }
          }

          final vx = details.primaryVelocity ?? 0;
          final current = _tabController.index;
          final int next;
          // Higher threshold to avoid accidental tab switches
          const thresholdVelocity = 900.0;
          if (vx < -thresholdVelocity && current < 2) {
            next = current + 1;
          } else if (vx > thresholdVelocity && current > 0) {
            next = current - 1;
          } else {
            return;
          }
          _tabController.animateTo(next);
        },
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _KeepAliveTabView(child: _buildPlaylistsView(bottomPad)),
            _KeepAliveTabView(child: _buildArtistsView(bottomPad)),
            _KeepAliveTabView(child: _buildFavouriteRadiosView(bottomPad)),
          ],
        ),
      ),
    );
  }


  // ─── RADIOS ──────────────────────────────────────────────────────────────────


  Widget _buildFavouriteRadiosView(double bottomPad) {
    return Consumer<AudioPlayerService>(
      builder: (context, audioService, _) {
        final List allRadios =
            audioService.getPlaylistRadios('favourite_radios');

        // Filter by search query
        List displayRadios = _searchQuery.isEmpty
            ? List.from(allRadios)
            : allRadios
                .where((r) => (r.name as String)
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
                .toList();

        // Sort by name, respecting _isAscending
        displayRadios.sort((a, b) {
          final cmp = (a.name as String)
              .toLowerCase()
              .compareTo((b.name as String).toLowerCase());
          return _isAscending ? cmp : -cmp;
        });

        if (displayRadios.isEmpty) {
          return Center(
            child: _buildEmptyState(
              icon: allRadios.isEmpty
                  ? Icons.radio_rounded
                  : Icons.search_off_rounded,
              title: allRadios.isEmpty ? 'No saved radios' : 'No matches',
              subtitle: allRadios.isEmpty
                  ? 'Tap the heart on any station to save it here'
                  : 'Try a different search term',
            ),
          );
        }

        // When searching, show all matches; otherwise cap at 5
        final showAll = _searchQuery.isNotEmpty || displayRadios.length <= 5;
        final displayCount = showAll ? displayRadios.length : 5;

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: 8, bottom: bottomPad),
          itemCount: displayCount + (showAll ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == displayCount) {
              // View all row
              return InkWell(
                onTap: () =>
                    pushMaterialPage(context, const FavouriteRadiosPage()),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.more_horiz,
                            color: Colors.grey[400], size: 24),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'View all ${allRadios.length} stations',
                        style: TextStyle(
                          color: Colors.deepPurple.shade300,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final radio = displayRadios[index];
            return _buildRadioRow(radio, audioService);
          },
        );
      },
    );
  }

  bool _isValidArtwork(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final thumbParam = uri.queryParameters['t']?.toLowerCase() ?? '';

    if (host.startsWith('encrypted-tbn') && host.endsWith('gstatic.com')) {
      return false;
    }

    if (host == 'de8as167a043l.cloudfront.net' ||
        path.contains('/styles/images/logosplus/')) {
      return false;
    }

    if (host == 'assets.laut.fm' && thumbParam.startsWith('_')) {
      return false;
    }

    if (path.endsWith('/icon.png') || 
        path.endsWith('/icon.ico') ||
        path.endsWith('/favicon.ico')) {
      return false;
    }

    if (path.contains('favicon')) {
      return false;
    }

    return host.isNotEmpty &&
        !path.endsWith('.ico') &&
        !path.endsWith('.svg') &&
        !path.endsWith('.bmp');
  }

  Widget _buildRadioRow(dynamic radio, AudioPlayerService audioService) {
    final hasArt = _isValidArtwork(radio.artworkUrl as String);
    final accentColor = Theme.of(context).colorScheme.primary;
    final isRadioActive = audioService.isRadioPlaying &&
        audioService.currentRadioStation?.id == radio.id;

    return GestureDetector(
      onTap: () async {
        final blockReason = await RadioPlaybackGuard.blockingMessage();
        if (blockReason != null) {
          final miniPlayerActive = audioService.isMiniPlayerVisible;
          final bottomPad = MediaQuery.of(context).padding.bottom +
              kBottomNavigationBarHeight +
              (miniPlayerActive ? 70.0 : 0.0);
          VoxelToast.show(
            context,
            blockReason,
          );
          return;
        }
        audioService.playRadioStation(radio);
      },
      onLongPress: () {
        final settings = Provider.of<SettingsModel>(context, listen: false);
        if (settings.hapticsEnabled && settings.hapticsOnLongPress) {
          HapticFeedback.mediumImpact();
        }
        _showRadioMenu(context, radio, audioService);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 0, top: 6, bottom: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 48,
                height: 48,
                child: hasArt
                    ? CachedNetworkImage(
                        imageUrl: radio.artworkUrl as String,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorListener: (_) {},
                        placeholder: (_, __) => Container(
                          color: Theme.of(context).colorScheme.primaryContainer,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.radio_rounded,
                              color: Theme.of(context).colorScheme.onPrimaryContainer, size: 24),
                        ),
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.radio_rounded,
                            color: Theme.of(context).colorScheme.onPrimaryContainer, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    radio.name as String,
                    style: TextStyle(
                      fontWeight: isRadioActive ? FontWeight.w500 : FontWeight.w400,
                      fontSize: 16,
                      color: isRadioActive ? accentColor : Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    radio.genre as String,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showRadioMenu(context, radio, audioService),
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 22),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
      ),
    );
  }

  void _showRadioMenu(
      BuildContext context, dynamic radio, AudioPlayerService audioService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => RadioMenuSheet(
        radio: radio,
        accentColor: Theme.of(context).colorScheme.primary,
        audioService: audioService,
        onRemove: () {
          audioService.removeRadioFromPlaylist('favourite_radios', radio);
        },
      ),
    );
  }



  // ─── PLAYLISTS ───────────────────────────────────────────────────────────────

  Widget _buildPlaylistsView(double bottomPad) {
    return Consumer2<AudioPlayerService, SettingsModel>(
      builder: (context, audioService, settings, _) {
        final playlists = audioService.allPlaylists;
        final customPlaylists = audioService.customPlaylists;

        final likedCount = playlists
            .firstWhere(
              (e) => e.key == 'liked',
              orElse: () => const MapEntry('liked', []),
            )
            .value
            .length;

        final offlineCount = playlists
            .firstWhere(
              (e) => e.key == 'offline',
              orElse: () => const MapEntry('offline', []),
            )
            .value
            .length;

        // Filter and sort custom playlists
        var filteredCustom = _searchQuery.isEmpty
            ? customPlaylists.toList()
            : customPlaylists
                .where((p) =>
                    p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        if (_sortOption == LibrarySortOption.name) {
          filteredCustom.sort((a, b) {
            final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return _isAscending ? cmp : -cmp;
          });
        } else {
          filteredCustom.sort((a, b) {
            final cmp = audioService
                .getPlaylistSongs(a.id)
                .length
                .compareTo(audioService.getPlaylistSongs(b.id).length);
            return _isAscending ? cmp : -cmp;
          });
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: 8, bottom: bottomPad),
          children: [
            // ── System playlists ──
            if (_searchQuery.isEmpty ||
                'liked songs'.contains(_searchQuery.toLowerCase()))
              _buildPlaylistRow(
                thumbnail: _solidThumbnail(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  icon: Icons.favorite_rounded,
                ),
                title: 'Liked Songs',
                subtitle: '$likedCount songs',
                onTap: () => pushMaterialPage(
                  context,
                  const PlaylistPage(
                    playlistId: 'liked',
                    title: 'Liked Songs',
                    icon: Icons.favorite,
                  ),
                ),
              ),
            if (_searchQuery.isEmpty ||
                'offline'.contains(_searchQuery.toLowerCase()))
              _buildPlaylistRow(
                thumbnail: _solidThumbnail(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  icon: Icons.offline_pin_rounded,
                ),
                title: 'Offline',
                subtitle: '$offlineCount songs',
                onTap: () => pushMaterialPage(
                  context,
                  const PlaylistPage(
                    playlistId: 'offline',
                    title: 'Offline',
                    icon: Icons.offline_pin,
                  ),
                ),
              ),

            // ── My Playlists header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
              child: Row(
                children: [
                  const Text(
                    'My Playlists',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _showCreatePlaylistDialog,
                    icon: Icon(Icons.add_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 24),
                    tooltip: 'New playlist',
                  ),
                ],
              ),
            ),

            // ── Playlists & Pinned Folders ──
            () {
              final filteredPinned = _searchQuery.isEmpty
                  ? settings.pinnedFolders
                  : settings.pinnedFolders
                      .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                      .toList();

              if (customPlaylists.isEmpty && settings.pinnedFolders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                  child: _buildEmptyState(
                    icon: Icons.library_music_rounded,
                    title: 'No playlists yet',
                    subtitle: 'Tap + to create your first playlist',
                  ),
                );
              }

              if (filteredCustom.isEmpty && filteredPinned.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                  child: _buildEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    subtitle: 'Try a different search term',
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...filteredCustom.map(
                    (playlist) => _buildPlaylistRow(
                      thumbnail: _playlistThumbnail(playlist, audioService),
                      title: playlist.name,
                      subtitle: () {
                        final n = audioService.getPlaylistSongs(playlist.id).length;
                        return '$n ${n == 1 ? 'song' : 'songs'}';
                      }(),
                      onTap: () => pushMaterialPage(
                        context,
                        PlaylistPage(
                          playlistId: playlist.id,
                          title: playlist.name,
                          icon: Icons.queue_music,
                          allowReorder: true,
                        ),
                      ),
                      trailing: IconButton(
                        onPressed: () => _showPlaylistOptionsSheet(playlist),
                        icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ),
                  ),
                  ...filteredPinned.map((folder) {
                    final webdavConfig = folder.type == 'webdav'
                        ? settings.webdavServers.firstWhere(
                            (s) => s.id == folder.serverId || s.url == folder.serverId,
                            orElse: () => WebdavServerConfig(
                              id: folder.serverId,
                              name: folder.serverName,
                              url: folder.serverId,
                            ),
                          )
                        : null;

                    final jellyfinConfig = folder.type == 'jellyfin'
                        ? settings.jellyfinServers.firstWhere(
                            (s) => s.id == folder.serverId,
                            orElse: () => JellyfinServerConfig(
                              id: folder.serverId,
                              name: folder.serverName,
                              url: '',
                              userId: folder.serverId,
                              token: '',
                            ),
                          )
                        : null;

                    return _buildPlaylistRow(
                      thumbnail: _pinnedFolderThumbnail(folder),
                      title: folder.name,
                      subtitle: '${folder.serverName} • Network Folder',
                      trailing: IconButton(
                        icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                        tooltip: 'Folder Options',
                        onPressed: () => _showPinnedFolderOptionsSheet(folder, settings),
                      ),
                      onTap: () {
                        if (folder.type == 'upnp') {
                          pushMaterialPage(
                            context,
                            NetworkBrowserPage(
                              upnpDevice: UpnpDevice(
                                location: folder.serverId,
                                friendlyName: folder.serverName,
                                controlUrl: folder.controlUrl ?? '',
                              ),
                              initialObjectId: folder.path,
                              initialFolderName: folder.name,
                              pinnedFolder: folder,
                            ),
                          );
                        } else if (folder.type == 'webdav') {
                          pushMaterialPage(
                            context,
                            NetworkBrowserPage(
                              webdavConfig: webdavConfig,
                              initialUrl: folder.path,
                              initialFolderName: folder.name,
                              pinnedFolder: folder,
                            ),
                          );
                        } else if (folder.type == 'jellyfin') {
                          pushMaterialPage(
                            context,
                            NetworkBrowserPage(
                              jellyfinConfig: jellyfinConfig,
                              initialObjectId: folder.path,
                              initialFolderName: folder.name,
                              pinnedFolder: folder,
                            ),
                          );
                        }
                      },
                    );
                  }),
                ],
              );
            }(),
          ],
        );
      },
    );
  }

  /// A generic list row used for both system and custom playlists.
  Widget _buildPlaylistRow({
    required Widget thumbnail,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        highlightColor: Theme.of(context).colorScheme.primary.withOpacity(0.04),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
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

  /// Square thumbnail with a solid muted background and a tinted icon.
  Widget _solidThumbnail({
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        size: 26,
      ),
    );
  }

  /// Blends an artwork color with the current app theme surface for a cohesive look.
  Color _themedAccentColor(Color rawColor) {
    final surface = Theme.of(context).colorScheme.surface;
    // Pull rawColor 70% toward theme surface — retains 30% of raw color identity
    return Color.lerp(rawColor, surface, 0.70) ?? rawColor;
  }

  /// Thumbnail for a custom playlist — artwork if available, colored box otherwise.
  Widget _playlistThumbnail(dynamic playlist, AudioPlayerService audioService) {
    final scheme = Theme.of(context).colorScheme;
    final rawColor = playlist.artworkColor != null
        ? Color(playlist.artworkColor as int)
        : scheme.tertiaryContainer;
    final accentColor = _themedAccentColor(rawColor);
    // Second gradient stop: blend toward theme primary for more cohesion
    final gradientEnd = Color.lerp(accentColor, scheme.primary, 0.15) != null
        ? Color.lerp(Color.lerp(accentColor, scheme.primary, 0.15)!, Colors.black, 0.20)!
        : accentColor;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 8,
            spreadRadius: 0,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 56,
          height: 56,
          child: playlist.artworkPath != null &&
                  (playlist.artworkPath as String).isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(playlist.artworkPath as String),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _coloredPlaylistThumb(accentColor, gradientEnd),
                    ),
                    // Subtle overlay tinted toward the theme surface
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.surface.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _coloredPlaylistThumb(accentColor, gradientEnd),
        ),
      ),
    );
  }

  Widget _coloredPlaylistThumb(Color color, Color colorEnd) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, colorEnd],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _pinnedFolderThumbnail(PinnedNetworkFolder folder) {
    final scheme = Theme.of(context).colorScheme;
    final rawColor = folder.artworkColor != null
        ? Color(folder.artworkColor!)
        : scheme.primaryContainer;
    final accentColor = _themedAccentColor(rawColor);
    final gradientEnd = Color.lerp(
          Color.lerp(accentColor, scheme.primary, 0.15),
          Colors.black,
          0.20,
        ) ?? accentColor;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 8,
            spreadRadius: 0,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 56,
          height: 56,
          child: folder.artworkPath != null && folder.artworkPath!.isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(folder.artworkPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _coloredPinnedFolderThumb(accentColor, gradientEnd, folder.type),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.surface.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _coloredPinnedFolderThumb(accentColor, gradientEnd, folder.type),
        ),
      ),
    );
  }

  Widget _coloredPinnedFolderThumb(Color color, Color colorEnd, String type) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, colorEnd],
        ),
      ),
      child: Center(
        child: Icon(
          type == 'upnp' ? Icons.dns_rounded : Icons.cloud_rounded,
          color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  // ─── ARTISTS ─────────────────────────────────────────────────────────────────

  String _normalizeArtistToken(String raw) {
    var cleaned = raw.trim();
    
    // Remove common video/audio suffixes from the artist name
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[]\s*(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\s*[\)\]]', caseSensitive: false),
      '',
    ).trim();
    // Also remove loose "official lyric video", "official video", etc.
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(?:official\s+)?(?:lyric\s+|music\s+)?(?:video|audio|visualizer)\b', caseSensitive: false),
      '',
    ).trim();

    // Remove leading/trailing whitespace and punctuation
    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s\(\[\{]+|[\s\)\]\}\.,;:!]+$'),
      '',
    );
    // Remove trailing unmatched parenthesis/bracket fragments
    cleaned =
        cleaned.replaceAll(RegExp(r'[\)\]\}]?\s*\[.*|[\)\]\}]?\s*\(.*'), '');
    // Remove any trailing bracketed/parenthesized content (e.g., [radio edit], (radio edit))
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(.*?\) $'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[.*?\] $'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'unknown artist') {
      return '';
    }
    return cleaned;
  }

  List<String> _splitCompoundArtists(String rawArtist) {
    return rawArtist
        .split(RegExp(r'\s*,\s*|\s*&\s*|\s+(?:feat\.?|ft\.?|x)\s+',
            caseSensitive: false))
        .map(_normalizeArtistToken)
        .where((a) => a.isNotEmpty)
        .toList();
  }

  List<String> _extractFeaturedArtistsFromTitle(String title) {
    final featured = <String>[];

    final bracketedFeat = RegExp(
      r'\((?:feat\.?|ft\.?)\s+([^\)]+)\)|\[(?:feat\.?|ft\.?)\s+([^\]]+)\]',
      caseSensitive: false,
    );

    for (final match in bracketedFeat.allMatches(title)) {
      final names = (match.group(1) ?? match.group(2) ?? '').trim();
      if (names.isEmpty) continue;
      featured.addAll(_splitCompoundArtists(names));
    }

    // Support non-bracket forms like "Song Title feat. Artist".
    final inlineFeat =
        RegExp(r'\b(?:feat\.?|ft\.?)\s+(.+)$', caseSensitive: false)
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

  Widget _buildArtistsView(double bottomPad) {
    final audioService = context.watch<AudioPlayerService>();
    final audioFiles = audioService.getPlaylistSongs('offline');
    final artistMap = <String, List<File>>{};
    final artistAlbumArt = <String, String>{};

    // For each artist, find the first song with a local album art file (from iTunes enrichment)
    for (var file in audioFiles) {
      final song = _metadataCache.createSongFromFile(file);
      final rawArtist = song.artist;
      if (rawArtist == 'Unknown Artist' || rawArtist.isEmpty) continue;

      final artistsByKey = <String, String>{};
      for (final artist in [
        ..._splitCompoundArtists(rawArtist),
        ..._extractFeaturedArtistsFromTitle(song.title),
      ]) {
        final normalized = _normalizeArtistToken(artist);
        if (normalized.isEmpty) continue;
        artistsByKey.putIfAbsent(normalized.toLowerCase(), () => normalized);
      }

      for (final artist in artistsByKey.values) {
        artistMap.putIfAbsent(artist, () => []).add(file);
        // Prefer local file album art (downloaded from iTunes enrichment)
        if (!artistAlbumArt.containsKey(artist) && song.albumArt.isNotEmpty) {
          // Only use if it's a local file path (not a URL)
          if (!song.albumArt.startsWith('http') &&
              File(song.albumArt).existsSync()) {
            artistAlbumArt[artist] = song.albumArt;
          }
        }
      }
    }

    final allArtistNames = artistMap.keys.toList();

    // Filter by search query
    var displayedArtists = _searchQuery.isEmpty
        ? List<String>.from(allArtistNames)
        : allArtistNames
            .where((a) => a.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    // Sort artists
    if (_sortOption == LibrarySortOption.name) {
      displayedArtists.sort((a, b) {
        final cmp = a.toLowerCase().compareTo(b.toLowerCase());
        return _isAscending ? cmp : -cmp;
      });
    } else {
      displayedArtists.sort((a, b) {
        final cmp = artistMap[a]!.length.compareTo(artistMap[b]!.length);
        return _isAscending ? cmp : -cmp;
      });
    }

    if (displayedArtists.isEmpty) {
      return Center(
        child: _buildEmptyState(
          icon: allArtistNames.isEmpty
              ? Icons.person_outline_rounded
              : Icons.search_off_rounded,
          title: allArtistNames.isEmpty ? 'No artists found' : 'No matches',
          subtitle: allArtistNames.isEmpty
              ? 'Add songs with artist metadata to see them here'
              : 'Try a different search term',
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: 8, bottom: bottomPad),
      itemCount: displayedArtists.length,
      itemBuilder: (context, index) {
        final artist = displayedArtists[index];
        final songs = artistMap[artist]!;
        final cachedArtistImage = _cachedArtistImagePath(artist);
        final albumArt = cachedArtistImage ?? artistAlbumArt[artist];

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => pushMaterialPage(
              context,
              ArtistPage(
                artistName: artist,
                songs: songs,
                artistArtwork: albumArt,
              ),
            ),
            splashColor: Colors.white.withOpacity(0.04),
            highlightColor: Colors.white.withOpacity(0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildArtistAvatar(albumArt, artist),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                          style:
                              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistAvatar(String? albumArt, String artistName) {
    final initials = artistName.isNotEmpty ? artistName[0].toUpperCase() : '?';
    final hue =
        (artistName.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    final avatarColor = HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor();

    return SizedBox(
      width: 56,
      height: 56,
      child: ClipOval(
        child: albumArt != null && albumArt.isNotEmpty
            ? Image.file(
                File(albumArt),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _initialsAvatar(initials, avatarColor),
              )
            : _initialsAvatar(initials, avatarColor),
      ),
    );
  }

  Widget _initialsAvatar(String initials, Color color) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
    );
  }

  // ─── SHARED HELPERS ───────────────────────────────────────────────────────────

  void _showLibrarySortSheet() {
    final isRadiosTab = _tabController.index == 2;
    final options = [
      (
        icon: Icons.sort_by_alpha,
        label: 'Name',
        value: LibrarySortOption.name,
      ),
      if (!isRadiosTab)
        (
          icon: Icons.music_note_outlined,
          label: 'Song count',
          value: LibrarySortOption.songCount,
        ),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            top: 12,
            bottom: MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2.25),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sort Library',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final isSelected = _sortOption == opt.value;
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                    leading: Icon(opt.icon,
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withOpacity(0.7)),
                    title: Text(
                      opt.label,
                      style: TextStyle(
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                            _isAscending
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: scheme.primary,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        if (_sortOption == opt.value) {
                          _isAscending = !_isAscending;
                        } else {
                          _sortOption = opt.value;
                          _isAscending = true;
                        }
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 72, color: Colors.grey[800]),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            subtitle,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ─── DIALOGS ────────────────────────────────────────────────────────────────

  Future<void> _showCreatePlaylistDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return const CreatePlaylistDialog(
          titleText: 'Create Playlist',
          actionText: 'Create',
        );
      },
    );

    if (result != null) {
      final audioService = context.read<AudioPlayerService>();
      await audioService.createCustomPlaylist(
        result['name'],
        artworkPath: result['artworkPath'],
        artworkColor: result['color'],
      );
    }
  }

  void _showPlaylistOptionsSheet(dynamic playlist) {
    final songCount = playlist.songPaths.length;
    final accentColor = playlist.artworkColor != null
        ? Color(playlist.artworkColor!)
        : Colors.deepPurple.shade400;
    final playlistSong = Song(
      id: playlist.id.toString(),
      filePath: playlist.artworkPath ?? '',
      title: playlist.name,
      artist: 'Playlist',
      album: '$songCount ${songCount == 1 ? 'song' : 'songs'}',
      albumArt: playlist.artworkPath ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (ctx) => SongMenuSheet(
        song: playlistSong,
        accentColor: accentColor,
        options: [
          SongMenuOption(
            icon: Icons.edit_rounded,
            title: 'Edit playlist',
            color: accentColor,
            onTap: () {
              _showEditPlaylistDialog(playlist);
            },
          ),
          SongMenuOption(
            icon: Icons.delete_outline_rounded,
            title: 'Delete playlist',
            color: Colors.red.shade400,
            onTap: () {
              _showDeletePlaylistDialog(playlist);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _playPinnedFolder(PinnedNetworkFolder folder, WebdavServerConfig? webdavConfig, JellyfinServerConfig? jellyfinConfig) async {
    VoxelToast.show(context, 'Loading network tracks...');
    try {
      final List<Song> songList = [];
      if (folder.type == 'upnp') {
        final rawItems = await UpnpService.browse(folder.controlUrl ?? '', folder.path);
        final tracks = rawItems.where((i) => !i.isContainer && i.streamUrl != null).toList();
        for (var t in tracks) {
          songList.add(Song(
            id: t.streamUrl!,
            filePath: t.streamUrl!,
            title: t.title.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
            artist: t.artist ?? folder.serverName,
            album: t.album ?? folder.name,
          ));
        }
      } else if (folder.type == 'webdav' && webdavConfig != null) {
        final rawItems = await WebdavService.list(webdavConfig, folder.path);
        final tracks = rawItems.where((i) => !i.isDirectory && i.streamUrl != null).toList();
        for (var t in tracks) {
          songList.add(Song(
            id: t.streamUrl!,
            filePath: t.streamUrl!,
            title: t.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
            artist: folder.serverName,
            album: folder.name,
          ));
        }
      } else if (folder.type == 'jellyfin' && jellyfinConfig != null) {
        final rawItems = await JellyfinService.listItems(jellyfinConfig, folder.path);
        final tracks = rawItems.where((i) => !i.isDirectory && i.streamUrl.isNotEmpty).toList();
        for (var t in tracks) {
          songList.add(Song(
            id: t.streamUrl,
            filePath: t.streamUrl,
            title: t.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
            artist: t.artist ?? folder.serverName,
            album: t.album ?? folder.name,
            albumArt: t.artworkUrl ?? '',
          ));
        }
      }

      if (songList.isEmpty) {
        if (mounted) {
          VoxelToast.show(context, 'No audio files found in folder');
        }
        return;
      }

      final metadataCache = SongMetadataCache();
      await metadataCache.initialize();
      for (var song in songList) {
        await metadataCache.saveMetadata(song);
      }

      final audioService = context.read<AudioPlayerService>();
      final files = songList.map((s) => File(s.filePath)).toList();
      await audioService.playFileInContext(files.first, files);
    } catch (e) {
      if (mounted) {
        VoxelToast.show(context, 'Failed to load tracks: $e');
      }
    }
  }

  void _showPinnedFolderOptionsSheet(PinnedNetworkFolder folder, SettingsModel settings) {
    final accentColor = folder.artworkColor != null
        ? Color(folder.artworkColor!)
        : Theme.of(context).colorScheme.primary;
    final folderSong = Song(
      id: folder.id,
      filePath: folder.artworkPath ?? '',
      title: folder.name,
      artist: folder.serverName,
      album: 'Network Folder',
      albumArt: folder.artworkPath ?? '',
    );

    // Retrieve matching WebDAV config if needed
    final webdavConfig = folder.type == 'webdav'
        ? settings.webdavServers.firstWhere(
            (s) => s.id == folder.serverId || s.url == folder.serverId,
            orElse: () => WebdavServerConfig(
              id: folder.serverId,
              name: folder.serverName,
              url: folder.serverId,
            ),
          )
        : null;

    // Retrieve matching Jellyfin config if needed
    final jellyfinConfig = folder.type == 'jellyfin'
        ? settings.jellyfinServers.firstWhere(
            (s) => s.id == folder.serverId,
            orElse: () => JellyfinServerConfig(
              id: folder.serverId,
              name: folder.serverName,
              url: '',
              userId: folder.serverId,
              token: '',
            ),
          )
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (ctx) => SongMenuSheet(
        song: folderSong,
        accentColor: accentColor,
        rightButtonIcon: Icons.push_pin_rounded,
        rightButtonColor: Colors.red.shade400,
        onPlayTap: () {
          Navigator.pop(ctx);
          _playPinnedFolder(folder, webdavConfig, jellyfinConfig);
        },
        onRightButtonTap: () async {
          Navigator.pop(ctx);
          await settings.unpinNetworkFolder(folder.id);
          if (mounted) {
            VoxelToast.show(
              context,
              'Folder unpinned from Library',
            );
          }
        },
        options: [
          SongMenuOption(
            icon: Icons.play_arrow_rounded,
            title: 'Play folder',
            onTap: () {
              _playPinnedFolder(folder, webdavConfig, jellyfinConfig);
            },
          ),
          SongMenuOption(
            icon: Icons.queue_music_rounded,
            title: 'Add folder to queue',
            onTap: () async {
              VoxelToast.show(context, 'Loading network tracks...');
              try {
                final List<Song> songList = [];
                if (folder.type == 'upnp') {
                  final rawItems = await UpnpService.browse(folder.controlUrl ?? '', folder.path);
                  final tracks = rawItems.where((i) => !i.isContainer && i.streamUrl != null).toList();
                  for (var t in tracks) {
                    songList.add(Song(
                      id: t.streamUrl!,
                      filePath: t.streamUrl!,
                      title: t.title.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
                      artist: t.artist ?? folder.serverName,
                      album: t.album ?? folder.name,
                    ));
                  }
                } else if (folder.type == 'webdav' && webdavConfig != null) {
                  final rawItems = await WebdavService.list(webdavConfig, folder.path);
                  final tracks = rawItems.where((i) => !i.isDirectory && i.streamUrl != null).toList();
                  for (var t in tracks) {
                    songList.add(Song(
                      id: t.streamUrl!,
                      filePath: t.streamUrl!,
                      title: t.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
                      artist: folder.serverName,
                      album: folder.name,
                    ));
                  }
                } else if (folder.type == 'jellyfin' && jellyfinConfig != null) {
                  final rawItems = await JellyfinService.listItems(jellyfinConfig, folder.path);
                  final tracks = rawItems.where((i) => !i.isDirectory && i.streamUrl.isNotEmpty).toList();
                  for (var t in tracks) {
                    songList.add(Song(
                      id: t.streamUrl,
                      filePath: t.streamUrl,
                      title: t.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
                      artist: t.artist ?? folder.serverName,
                      album: t.album ?? folder.name,
                      albumArt: t.artworkUrl ?? '',
                    ));
                  }
                }

                if (songList.isEmpty) {
                  if (context.mounted) {
                    VoxelToast.show(context, 'No audio files found in folder');
                  }
                  return;
                }

                final metadataCache = SongMetadataCache();
                await metadataCache.initialize();
                for (var song in songList) {
                  await metadataCache.saveMetadata(song);
                }

                final audioService = context.read<AudioPlayerService>();
                for (var song in songList) {
                  await audioService.addToQueue(song);
                }
                if (context.mounted) {
                  VoxelToast.show(context, 'Added ${songList.length} tracks to queue');
                }
              } catch (e) {
                if (context.mounted) {
                  VoxelToast.show(context, 'Failed to load tracks: $e');
                }
              }


            },
          ),
          SongMenuOption(
            icon: Icons.edit_rounded,
            title: 'Edit pinned folder',
            color: accentColor,
            onTap: () {
              _showEditPinnedFolderDialog(folder, settings);
            },
          ),
          SongMenuOption(
            icon: Icons.push_pin_rounded,
            title: 'Unpin folder',
            color: Colors.red.shade400,
            onTap: () async {
              await settings.unpinNetworkFolder(folder.id);
              if (mounted) {
                VoxelToast.show(
                  context,
                  'Folder unpinned from Library',
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showEditPinnedFolderDialog(PinnedNetworkFolder folder, SettingsModel settings) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CreatePlaylistDialog(
          initialName: folder.name,
          initialArtworkPath: folder.artworkPath,
          initialColor: folder.artworkColor,
          titleText: 'Edit Pinned Folder',
          actionText: 'Save',
        );
      },
    );

    if (result != null) {
      await settings.updatePinnedNetworkFolder(
        folder.id,
        name: result['name'] as String?,
        artworkPath: result['artworkPath'] as String?,
        artworkColor: result['color'] as int?,
      );
    }
  }

  Future<void> _showEditPlaylistDialog(dynamic playlist) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CreatePlaylistDialog(
          initialName: playlist.name,
          initialArtworkPath: playlist.artworkPath,
          initialColor: playlist.artworkColor,
          titleText: 'Edit Playlist',
          actionText: 'Save',
        );
      },
    );

    if (result != null) {
      final audioService = context.read<AudioPlayerService>();
      await audioService.updateCustomPlaylist(
        playlist.id,
        name: result['name'] as String?,
        artworkPath: result['artworkPath'] as String?,
        artworkColor: result['color'] as int?,
      );
    }
  }

  Future<void> _showDeletePlaylistDialog(dynamic playlist) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.3,
        minChildSize: 0.25,
        maxChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Delete Playlist?',
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${playlist.name}"? This action cannot be undone.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == true) {
      final audioService = context.read<AudioPlayerService>();
      await audioService.deleteCustomPlaylist(playlist.id);
    }
  }
}

// Keeps a tab page alive in PageView so scroll state is preserved across switches.
class _KeepAliveTabView extends StatefulWidget {
  const _KeepAliveTabView({required this.child});
  final Widget child;

  @override
  State<_KeepAliveTabView> createState() => _KeepAliveTabViewState();
}

class _KeepAliveTabViewState extends State<_KeepAliveTabView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
