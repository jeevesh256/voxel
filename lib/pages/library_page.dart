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

// Helper for Cupertino-style page transitions
void pushMaterialPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => RepaintBoundary(child: page),
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

class _LibraryPageState extends State<LibraryPage> {
  final StorageService _storageService = StorageService();
  final SongMetadataCache _metadataCache = SongMetadataCache();

  @override
  void initState() {
    super.initState();
    _metadataCache.initialize();
    // Check if offline files are already loaded, if not, load them
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioService = context.read<AudioPlayerService>();
      final offlineSongs = audioService.getPlaylistSongs('offline');
      if (offlineSongs.isEmpty) {
        _loadAudioFiles();
      }
    });
  }

  Future<void> _loadAudioFiles() async {
    try {
      final entities = await _storageService.getAudioFiles();
      final files = entities.whereType<File>().toList();

      if (mounted) {
        // Load files into offline playlist
        context.read<AudioPlayerService>().loadOfflineFiles(files);
      }
    } catch (e) {
      if (mounted) {
        // Error handling - could show a snackbar or error message
        debugPrint('Error loading audio files: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Radios'),
            ],
            indicatorColor: Colors.deepPurple.shade400,
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlaylistsView(),
            _buildArtistsView(),
            _buildFavouriteRadiosView(),
          ],
        ),
      ),
    );
    // ...existing code...
  }

  Widget _buildFavouriteRadiosView() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Consumer<AudioPlayerService>(
        builder: (context, audioService, child) {
          final radios = audioService.getPlaylistRadios('favourite_radios');

          if (radios.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.radio,
                    size: 64,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No radios yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add stations by tapping the heart icon',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header with view all button (only if needed)
              if (radios.length > 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${radios.length} stations',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          pushMaterialPage(
                              context, const FavouriteRadiosPage());
                        },
                        icon: Icon(
                          Icons.arrow_forward,
                          color: Colors.deepPurple.shade400,
                          size: 16,
                        ),
                        label: Text(
                          'View All',
                          style: TextStyle(
                            color: Colors.deepPurple.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Show first 3-5 radios or all if less than 6
              Expanded(
                child: ListView.builder(
                  itemCount: radios.length > 5 ? 5 : radios.length,
                  itemBuilder: (context, index) {
                    final radio = radios[index];
                    final hasArt = radio.artworkUrl.isNotEmpty;
                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: hasArt
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  radio.artworkUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 48,
                                    height: 48,
                                    color: Colors.deepPurple.shade200,
                                    child: const Icon(Icons.radio,
                                        color: Colors.white, size: 24),
                                  ),
                                ),
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.radio,
                                    color: Colors.white, size: 24),
                              ),
                        title: Text(
                          radio.name,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Flexible(
                              child: Text(
                                radio.genre,
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (radio.country.isNotEmpty) ...[
                              Text(
                                ' • ',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                              Flexible(
                                child: Text(
                                  radio.country,
                                  style: TextStyle(color: Colors.grey[400]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.favorite,
                            color: Colors.deepPurple.shade400,
                            size: 20,
                          ),
                          tooltip: 'Remove radio',
                          onPressed: () {
                            // Show confirmation dialog for better UX
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  backgroundColor: Colors.grey[900],
                                  title: Text(
                                    'Remove radio?',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Remove "${radio.name}" from your radios?',
                                    style: TextStyle(color: Colors.grey[300]),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text(
                                        'Cancel',
                                        style:
                                            TextStyle(color: Colors.grey[400]),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        audioService.removeRadioFromPlaylist(
                                            'favourite_radios', radio);
                                        Navigator.of(context).pop();
                                      },
                                      child: Text(
                                        'Remove',
                                        style: TextStyle(
                                            color: Colors.deepPurple.shade400),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        onTap: () => audioService.playRadioStation(radio),
                      ),
                    );
                  },
                ),
              ),
              // Add spacing for mini player
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsView() {
    final audioService = context.watch<AudioPlayerService>();
    final playlists = audioService.allPlaylists;
    final customPlaylists = audioService.customPlaylists;

    // Show liked songs in stack order (newest first)
    final likedSongs = List<File>.from(playlists
        .firstWhere(
          (e) => e.key == 'liked',
          orElse: () => const MapEntry('liked', []),
        )
        .value
        .reversed);

    return ListView(
      children: [
        // Default playlists
        _buildPlaylistTile(
          title: 'Liked Songs',
          icon: Icons.favorite,
          playlistId: 'liked',
          songs: likedSongs,
        ),
        _buildPlaylistTile(
          title: 'Offline',
          icon: Icons.offline_pin,
          playlistId: 'offline',
          songs: playlists
              .firstWhere(
                (e) => e.key == 'offline',
                orElse: () => const MapEntry('offline', []),
              )
              .value,
        ),
        const Divider(),
        // Custom playlists
        ...customPlaylists
            .map((playlist) => _buildCustomPlaylistTile(playlist)),
        // Create new playlist button at the bottom
        ListTile(
          leading: Icon(
            Icons.add,
            color: Colors.deepPurple.shade400,
          ),
          title: const Text(
            'Create Playlist',
            style: TextStyle(color: Colors.white),
          ),
          onTap: _showCreatePlaylistDialog,
        ),
        const SizedBox(height: 100), // Extra space for mini player
      ],
    );
  }

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

  Widget _buildCustomPlaylistTile(dynamic playlist) {
    final audioService = context.watch<AudioPlayerService>();
    final songs = audioService.getPlaylistSongs(playlist.id);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      horizontalTitleGap: 12,
      leading: playlist.artworkPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(playlist.artworkPath!),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => playlist.artworkColor != null
                    ? Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(playlist.artworkColor!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.queue_music,
                          color: Colors.white,
                          size: 20,
                        ),
                      )
                    : Icon(
                        Icons.queue_music,
                        color: Colors.deepPurple.shade400,
                      ),
              ),
            )
          : playlist.artworkColor != null
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(playlist.artworkColor!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.queue_music,
                    color: Colors.white,
                    size: 20,
                  ),
                )
              : Icon(
                  Icons.queue_music,
                  color: Colors.deepPurple.shade400,
                ),
      title: Text(
        playlist.name,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        '${songs.length} songs',
        style: TextStyle(color: Colors.grey[400]),
      ),
      trailing: IconButton(
        icon: Icon(Icons.more_vert, color: Colors.grey[400]),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: () => _showPlaylistOptionsSheet(playlist),
      ),
      onTap: () {
        pushMaterialPage(
          context,
          PlaylistPage(
            playlistId: playlist.id,
            title: playlist.name,
            icon: Icons.queue_music,
            allowReorder: true,
          ),
        );
      },
    );
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

  Future<void> _showRenamePlaylistDialog(dynamic playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Rename Playlist',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Playlist Name',
            labelStyle: TextStyle(color: Colors.grey[400]),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurple.shade400),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text('Rename',
                style: TextStyle(color: Colors.deepPurple.shade400)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != playlist.name) {
      final audioService = context.read<AudioPlayerService>();
      await audioService.updateCustomPlaylist(playlist.id, name: result);
    }
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

  Widget _buildPlaylistTile({
    required String title,
    required IconData icon,
    required String playlistId,
    required List<File> songs,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Colors.deepPurple.shade400,
      ),
      title: Text(title),
      subtitle: Text('${songs.length} songs'),
      onTap: () {
        pushMaterialPage(
          context,
          PlaylistPage(
            playlistId: playlistId,
            title: title,
            icon: icon,
          ),
        );
      },
    );
  }

  Widget _buildArtistsView() {
    final audioService = context.watch<AudioPlayerService>();
    final audioFiles = audioService.getPlaylistSongs('offline');
    
    // Group songs by artist using metadata cache
    final artistMap = <String, List<File>>{};
    final artistAlbumArt = <String, String>{};

    for (var file in audioFiles) {
      final song = _metadataCache.createSongFromFile(file);
      final artist = song.artist;
      
      // Skip Unknown Artist
      if (artist == 'Unknown Artist' || artist.isEmpty) continue;
      
      artistMap.putIfAbsent(artist, () => []).add(file);
      
      // Store first album art found for this artist
      if (!artistAlbumArt.containsKey(artist) && song.albumArt.isNotEmpty) {
        artistAlbumArt[artist] = song.albumArt;
      }
    }

    final sortedArtists = artistMap.keys.toList()..sort();

    if (sortedArtists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 80,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                'No artists found',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Add songs with artist metadata to see them here',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100), // Space for nav bar and mini player
      itemCount: sortedArtists.length,
      itemBuilder: (context, index) {
        final artist = sortedArtists[index];
        final songs = artistMap[artist]!;
        final albumArt = artistAlbumArt[artist];

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: albumArt != null && albumArt.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image.file(
                    File(albumArt),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade400,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                )
              : Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade400,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
          title: Text(
            artist,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
            style: TextStyle(color: Colors.grey[400]),
          ),
          onTap: () {
            pushMaterialPage(
              context,
              ArtistPage(
                artistName: artist,
                songs: songs,
                artistArtwork: albumArt,
              ),
            );
          },
        );
      },
    );
  }
}
