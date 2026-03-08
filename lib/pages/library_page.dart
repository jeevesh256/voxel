import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../services/song_metadata_cache.dart';
import '../widgets/create_playlist_dialog.dart';
import 'dart:io';
import 'playlist_page.dart';
import 'favourite_radios_page.dart';
import 'artist_page.dart';

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
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final SongMetadataCache _metadataCache = SongMetadataCache();
  late TabController _tabController;

  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  LibrarySortOption _sortOption = LibrarySortOption.name;
  bool _isAscending = true;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, animationDuration: const Duration(milliseconds: 300));
    _pageController = PageController();
    _metadataCache.initialize();
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
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAudioFiles() async {
    try {
      final entities = await _storageService.getAudioFiles();
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSearching ? 112 : 52),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        onTap: (index) {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                          );
                        },
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
                          color: Colors.deepPurple.shade500,
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey[500],
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!_isSearching) ...[
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                          onPressed: () => setState(() => _isSearching = true),
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
                    ] else
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                          onPressed: () => setState(() {
                            _isSearching = false;
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Only claim the gesture when it is clearly horizontal
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          final current = _tabController.index;
          final int next;
          if (vx < -300 && current < 2) {
            next = current + 1;
          } else if (vx > 300 && current > 0) {
            next = current - 1;
          } else {
            return;
          }
          _pageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
          );
          _tabController.animateTo(next);
        },
        child: PageView(
          controller: _pageController,
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
        final List allRadios = audioService.getPlaylistRadios('favourite_radios');

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
          padding: EdgeInsets.only(top: 8, bottom: bottomPad),
          itemCount: displayCount + (showAll ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == displayCount) {
              // View all row
              return InkWell(
                onTap: () =>
                    pushMaterialPage(context, const FavouriteRadiosPage()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
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

  Widget _buildRadioRow(dynamic radio, AudioPlayerService audioService) {
    final hasArt = (radio.artworkUrl as String).isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => audioService.playRadioStation(radio),
        splashColor: Colors.white.withOpacity(0.04),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasArt
                    ? Image.network(
                        radio.artworkUrl as String,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _radioArtFallback(),
                      )
                    : _radioArtFallback(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      radio.name as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((radio.genre as String).isNotEmpty ||
                        (radio.country as String).isNotEmpty) ...
                      [
                        const SizedBox(height: 3),
                        Text(
                          [
                            if ((radio.genre as String).isNotEmpty)
                              radio.genre as String,
                            if ((radio.country as String).isNotEmpty)
                              radio.country as String,
                          ].join(' · '),
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: () =>
                    _confirmRemoveRadio(context, radio, audioService),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.favorite_rounded,
                      color: Colors.deepPurple.shade400, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radioArtFallback() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFA855A8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.radio_rounded,
          color: Colors.white, size: 26),
    );
  }

  void _confirmRemoveRadio(
      BuildContext context, dynamic radio, AudioPlayerService audioService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove station?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${radio.name}" from your saved radios?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () {
              audioService.removeRadioFromPlaylist('favourite_radios', radio);
              Navigator.of(ctx).pop();
            },
            child: Text('Remove',
                style: TextStyle(color: Colors.deepPurple.shade300)),
          ),
        ],
      ),
    );
  }

  // ─── PLAYLISTS ───────────────────────────────────────────────────────────────

  Widget _buildPlaylistsView(double bottomPad) {
    return Consumer<AudioPlayerService>(
      builder: (context, audioService, _) {
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
                .where((p) => p.name
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
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
          padding: EdgeInsets.only(top: 8, bottom: bottomPad),
          children: [
            // ── System playlists ──
            if (_searchQuery.isEmpty ||
                'liked songs'.contains(_searchQuery.toLowerCase()))
              _buildPlaylistRow(
                thumbnail: _solidThumbnail(
                  color: Colors.deepPurple.shade200,
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
                  color: const Color(0xFF5573B8),
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
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _showCreatePlaylistDialog,
                    icon: Icon(Icons.add_rounded,
                        color: Colors.deepPurple.shade300, size: 24),
                    tooltip: 'New playlist',
                  ),
                ],
              ),
            ),

            // ── Custom playlists ──
            if (customPlaylists.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                child: _buildEmptyState(
                  icon: Icons.library_music_rounded,
                  title: 'No playlists yet',
                  subtitle: 'Tap + to create your first playlist',
                ),
              )
            else if (filteredCustom.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                child: _buildEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  subtitle: 'Try a different search term',
                ),
              )
            else
              ...filteredCustom.map(
                (playlist) => _buildPlaylistRow(
                  thumbnail: _playlistThumbnail(playlist, audioService),
                  title: playlist.name,
                  subtitle: () {
                    final n =
                        audioService.getPlaylistSongs(playlist.id).length;
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
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
              ),
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
        splashColor: Colors.white.withOpacity(0.04),
        highlightColor: Colors.white.withOpacity(0.03),
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
                        color: Colors.white,
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
                        color: Colors.grey[500],
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
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }

  /// Thumbnail for a custom playlist — artwork if available, colored box otherwise.
  Widget _playlistThumbnail(dynamic playlist, AudioPlayerService audioService) {
    final accentColor = playlist.artworkColor != null
        ? Color(playlist.artworkColor as int)
        : const Color(0xFF80CBC4);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: playlist.artworkPath != null &&
                (playlist.artworkPath as String).isNotEmpty
            ? Image.file(
                File(playlist.artworkPath as String),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _coloredPlaylistThumb(accentColor),
              )
            : _coloredPlaylistThumb(accentColor),
      ),
    );
  }

  Widget _coloredPlaylistThumb(Color color) {
    return Container(
      color: color,
      child: const Center(
        child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 32),
      ),
    );
  }

  // ─── ARTISTS ─────────────────────────────────────────────────────────────────

  Widget _buildArtistsView(double bottomPad) {
    final audioService = context.watch<AudioPlayerService>();
    final audioFiles = audioService.getPlaylistSongs('offline');
    final artistMap = <String, List<File>>{};
    final artistAlbumArt = <String, String>{};

    for (var file in audioFiles) {
      final song = _metadataCache.createSongFromFile(file);
      final rawArtist = song.artist;
      if (rawArtist == 'Unknown Artist' || rawArtist.isEmpty) continue;

      // Split compound artist strings into individual names
      final artists = rawArtist
          .split(RegExp(r'\s*,\s*|\s*&\s*|\s+(?:feat\.?|ft\.?|x)\s+', caseSensitive: false))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();

      for (final artist in artists) {
        artistMap.putIfAbsent(artist, () => []).add(file);
        if (!artistAlbumArt.containsKey(artist) && song.albumArt.isNotEmpty) {
          artistAlbumArt[artist] = song.albumArt;
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
      padding: EdgeInsets.only(top: 8, bottom: bottomPad),
      itemCount: displayedArtists.length,
      itemBuilder: (context, index) {
        final artist = displayedArtists[index];
        final songs = artistMap[artist]!;
        final albumArt = artistAlbumArt[artist];

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            color: Colors.white,
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
                              TextStyle(color: Colors.grey[500], fontSize: 13),
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
    final initials =
        artistName.isNotEmpty ? artistName[0].toUpperCase() : '?';
    final hue = (artistName.codeUnits.fold(0, (a, b) => a + b) % 360)
        .toDouble();
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
    bool dismissed = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) {
        void dismiss(BuildContext c) {
          if (dismissed) return;
          dismissed = true;
          Navigator.of(c, rootNavigator: true).pop();
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTap: () => dismiss(ctx),
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! > 8) {
                    dismiss(ctx);
                  }
                },
                onVerticalDragEnd: (details) {
                  if (details.velocity.pixelsPerSecond.dy > 450) dismiss(ctx);
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: DraggableScrollableSheet(
                initialChildSize: 0.3,
                minChildSize: 0.25,
                maxChildSize: 0.5,
                snap: true,
                snapSizes: const [0.3],
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildListDelegate(
                            options.map((opt) {
                              final isSelected = _sortOption == opt.value;
                              return ListTile(
                                leading: Icon(opt.icon,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey),
                                title: Text(
                                  opt.label,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        _isAscending
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        color: Colors.white,
                                      )
                                    : null,
                                onTap: () {
                                  dismiss(ctx);
                                  setState(() {
                                    if (_sortOption == opt.value) {
                                      _isAscending = !_isAscending;
                                    } else {
                                      _sortOption = opt.value;
                                      _isAscending = true;
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                              height:
                                  MediaQuery.of(context).padding.bottom + 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool dismissed = false;
        void dismiss() {
          if (dismissed) return;
          dismissed = true;
          Navigator.of(ctx, rootNavigator: true).pop();
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (context) {
                  final viewInsets = MediaQuery.of(context).viewInsets.bottom;
                  final isKeyboardVisible = viewInsets > 0;
                  final targetSize = isKeyboardVisible ? 0.85 : 0.55;

                  return DraggableScrollableSheet(
                    initialChildSize: targetSize,
                    minChildSize: targetSize,
                    maxChildSize: targetSize,
                    expand: false,
                    builder: (context, scrollController) {
                      return CreatePlaylistDialog(
                        useBottomSheetStyle: true,
                        sheetScrollController: scrollController,
                      );
                    },
                  );
                },
              ),
            ),
          ],
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
    bool dismissed = false;
    void dismiss(BuildContext ctx) {
      if (dismissed) return;
      dismissed = true;
      Navigator.of(ctx, rootNavigator: true).pop();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => dismiss(ctx),
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! > 8) {
                  dismiss(ctx);
                }
              },
              onVerticalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dy > 450) {
                  dismiss(ctx);
                }
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.3,
              minChildSize: 0.25,
              maxChildSize: 0.4,
              snap: true,
              snapSizes: const [0.3, 0.4],
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: playlist.artworkColor != null
                                          ? Color(playlist.artworkColor!)
                                          : Colors.deepPurple.shade200,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: playlist.artworkPath != null &&
                                            playlist.artworkPath!.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.file(
                                              File(playlist.artworkPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.queue_music,
                                                      color: Colors.white,
                                                      size: 28),
                                            ),
                                          )
                                        : Icon(Icons.queue_music,
                                            color: Colors.white, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$songCount ${songCount == 1 ? 'song' : 'songs'}',
                                          style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Colors.grey),
                          ],
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildListDelegate([
                          ListTile(
                            leading: Icon(Icons.edit, color: accentColor),
                            title: const Text('Edit',
                                style: TextStyle(color: Colors.white)),
                            onTap: () {
                              dismiss(ctx);
                              _showEditPlaylistDialog(playlist);
                            },
                          ),
                          ListTile(
                            leading:
                                Icon(Icons.delete, color: Colors.red.shade400),
                            title: const Text('Delete',
                                style: TextStyle(color: Colors.white)),
                            onTap: () {
                              dismiss(ctx);
                              _showDeletePlaylistDialog(playlist);
                            },
                          ),
                          SizedBox(
                              height:
                                  MediaQuery.of(context).padding.bottom + 20),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditPlaylistDialog(dynamic playlist) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool dismissed = false;
        void dismiss() {
          if (dismissed) return;
          dismissed = true;
          Navigator.of(ctx, rootNavigator: true).pop();
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (context) {
                  final viewInsets = MediaQuery.of(context).viewInsets.bottom;
                  final isKeyboardVisible = viewInsets > 0;
                  final targetSize = isKeyboardVisible ? 0.85 : 0.55;

                  return DraggableScrollableSheet(
                    initialChildSize: targetSize,
                    minChildSize: targetSize,
                    maxChildSize: targetSize,
                    expand: false,
                    builder: (context, scrollController) {
                      return CreatePlaylistDialog(
                        initialName: playlist.name,
                        initialArtworkPath: playlist.artworkPath,
                        initialColor: playlist.artworkColor,
                        titleText: 'Edit Playlist',
                        actionText: 'Save',
                        useBottomSheetStyle: true,
                        sheetScrollController: scrollController,
                      );
                    },
                  );
                },
              ),
            ),
          ],
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.3,
        minChildSize: 0.25,
        maxChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
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
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Delete Playlist?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${playlist.name}"? This action cannot be undone.',
                  style: TextStyle(color: Colors.grey[300]),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel',
                          style: TextStyle(color: Colors.grey[400])),
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
