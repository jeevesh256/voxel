import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/song_metadata_cache.dart';
import '../services/itunes_service.dart';
import '../services/playlist_handler.dart';
import '../services/metadata_service.dart';
import '../widgets/create_playlist_dialog.dart';
import '../models/song.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class ArtistPage extends StatefulWidget {
  final String artistName;
  final List<File> songs;
  final String? artistArtwork;

  const ArtistPage({
    super.key,
    required this.artistName,
    required this.songs,
    this.artistArtwork,
  });

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  final SongMetadataCache _metadataCache = SongMetadataCache();
  final ITunesService _itunesService = ITunesService();
  final MetadataService _metadataService = MetadataService();
  final ScrollController _scrollController = ScrollController();
  
  ITunesArtist? _artistInfo;
  List<ITunesAlbum> _albums = [];
  bool _isLoadingAlbums = true;

  @override
  void initState() {
    super.initState();
    _metadataCache.initialize();
    _fetchArtistInfo();
  }

  Future<void> _fetchArtistInfo() async {
    try {
      final artistInfo = await _itunesService.searchArtist(artistName: widget.artistName);
      
      if (artistInfo != null && artistInfo.artistId != 0) {
        final albums = await _itunesService.getArtistAlbumArtworks(
          artistId: artistInfo.artistId,
          limit: 8,
        );
        
        if (mounted) {
          setState(() {
            _artistInfo = artistInfo;
            _albums = albums;
            _isLoadingAlbums = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingAlbums = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingAlbums = false);
    }
  }

  bool _isMiniPlayerActive(AudioPlayerService audioService) {
    final seqState = audioService.player.sequenceState;
    return seqState?.sequence.isNotEmpty ?? false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            final opacity = ((_scrollController.hasClients
                        ? _scrollController.offset
                        : 0.0) /
                    375.0)
                .clamp(0.0, 1.0);
            return AppBar(
              backgroundColor: Colors.black.withOpacity(opacity),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            );
          },
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Large hero header
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Background image with gradient
                Container(
                  height: 400,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.grey[900]!,
                        Colors.black,
                      ],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.artistArtwork != null && widget.artistArtwork!.isNotEmpty)
                        Image.file(
                          File(widget.artistArtwork!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        )
                      else if (_albums.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: _albums.first.artworkUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[900],
                          ),
                          errorWidget: (_, __, ___) => const SizedBox(),
                        ),
                      
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.7, 1.0],
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.8),
                              Colors.black,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Artist name at bottom
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.artistName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (_artistInfo?.primaryGenre.isNotEmpty ?? false) ...[
                            Text(
                              _artistInfo!.primaryGenre,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                          Text(
                            '${widget.songs.length} ${widget.songs.length == 1 ? 'song' : 'songs'}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Play and shuffle buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  // Large circular play button (Spotify style)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade400,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.shade400.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        audioService.playFiles(widget.songs);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Shuffle button
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[800]!, width: 1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        size: 20,
                        color: Colors.grey[400],
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final shuffledSongs = List<File>.from(widget.songs)..shuffle();
                        audioService.playFiles(shuffledSongs);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Songs section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Songs',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Top 5 songs
          SliverList.builder(
            itemCount: widget.songs.length > 5 ? 5 : widget.songs.length,
            itemBuilder: (context, index) {
              final file = widget.songs[index];
              final song = _metadataCache.createSongFromFile(file);
              
              return InkWell(
                onTap: () {
                  audioService.playFileInContext(file, widget.songs);
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 0, top: 6, bottom: 6),
                  child: Row(
                    children: [
                      // Track number
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Album art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: song.albumArt.isNotEmpty
                            ? Image.file(
                                File(song.albumArt),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildDefaultAlbumArt(48),
                              )
                            : _buildDefaultAlbumArt(48),
                      ),
                      const SizedBox(width: 16),
                      // Song info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.artist.isNotEmpty ? song.artist : widget.artistName,
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
                      // More options
                      IconButton(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey[400],
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onPressed: () {
                          _showSongOptionsSheet(file);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Featured In section
          if (_isLoadingAlbums || _albums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Text(
                  'Featured In',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    // Show skeleton cards while loading
                    if (_isLoadingAlbums) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: const _ShimmerBox(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: _ShimmerBox(
                              height: 12,
                              width: (index % 3 == 0) ? 120.0 : (index % 3 == 1) ? 90.0 : 105.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: _ShimmerBox(
                              height: 10,
                              width: (index % 2 == 0) ? 70.0 : 55.0,
                            ),
                          ),
                        ],
                      );
                    }

                    final album = _albums[index];
                    return InkWell(
                      onTap: () {
                        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'This album is not in your library',
                              style: TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.grey[900],
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom +
                                  kBottomNavigationBarHeight + miniPlayerHeight,
                              left: 16,
                              right: 16,
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: CachedNetworkImage(
                                imageUrl: album.artworkUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const _ShimmerBox(),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[900],
                                  child: Center(
                                    child: Icon(
                                      Icons.album,
                                      color: Colors.grey[700],
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            album.albumName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: _isLoadingAlbums ? 4 : (_albums.length > 6 ? 6 : _albums.length),
                ),
              ),
            ),
          ],
          
          // All songs section (if more than 5)
          if (widget.songs.length > 5) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Text(
                  'All Songs',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: widget.songs.length,
              itemBuilder: (context, index) {
                final file = widget.songs[index];
                final song = _metadataCache.createSongFromFile(file);
                
                return InkWell(
                  onTap: () {
                    audioService.playFileInContext(file, widget.songs);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, right: 0, top: 8, bottom: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: song.albumArt.isNotEmpty
                              ? Image.file(
                                  File(song.albumArt),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildDefaultAlbumArt(48),
                                )
                              : _buildDefaultAlbumArt(48),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.album.isNotEmpty ? song.album : 'Unknown Album',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: Colors.grey[400],
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          onPressed: () {
                            _showSongOptionsSheet(file);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          
          // Bottom padding
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.of(context).padding.bottom +
                  kBottomNavigationBarHeight +
                  80.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAlbumArt(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: Colors.grey[700],
        size: size * 0.5,
      ),
    );
  }

  void _showSongOptionsSheet(File file) {
    final audioService = context.read<AudioPlayerService>();
    final cachedSong = _metadataCache.createSongFromFile(file);
    bool dismissed = false;
    void dismissSheet(BuildContext ctx) {
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
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => dismissSheet(context),
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! > 8) {
                  dismissSheet(context);
                }
              },
              onVerticalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dy > 450) {
                  dismissSheet(context);
                }
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.25,
              maxChildSize: 0.5,
              snap: true,
              snapSizes: const [0.5],
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag handle
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // Song info header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: cachedSong.albumArt.isNotEmpty
                                          ? Image.file(
                                              File(cachedSong.albumArt),
                                              width: 75,
                                              height: 75,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _buildDefaultAlbumArt(75),
                                            )
                                          : _buildDefaultAlbumArt(75),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cachedSong.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          cachedSong.artist,
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
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
                          _buildOptionTile(
                            icon: audioService.isFileLiked(file.path)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            title: audioService.isFileLiked(file.path)
                                ? 'Remove from Liked Songs'
                                : 'Add to Liked Songs',
                            color: Colors.deepPurple.shade200,
                            onTap: () {
                              audioService.toggleLikeFile(file.path);
                              Navigator.pop(context);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.playlist_add,
                            title: 'Add to playlist',
                            color: Colors.tealAccent.shade400,
                            onTap: () {
                              Navigator.pop(context);
                              _showAddToPlaylistDialog(file);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.queue,
                            title: 'Add to queue',
                            color: Colors.blue.shade400,
                            onTap: () {
                              Navigator.pop(context);

                              if (_isMiniPlayerActive(audioService)) {
                                final bottomMargin =
                                    (MediaQuery.of(context).padding.bottom) +
                                        kBottomNavigationBarHeight +
                                        70.0;
                                final playlistHandler =
                                    context.read<PlaylistHandler>();
                                final song =
                                    _metadataCache.createSongFromFile(file);
                                final insertIndex =
                                    (audioService.player.currentIndex ?? 0) + 1;
                                playlistHandler.insertAtQueue(song, insertIndex);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: bottomMargin,
                                    ),
                                    content: const Text('Added to queue'),
                                    backgroundColor: Colors.deepPurple.shade400,
                                  ),
                                );
                              } else {
                                audioService.playFileInContextWithPlaylistId(
                                    file, widget.songs, 'artist-${widget.artistName}');

                                final bottomMargin =
                                    (MediaQuery.of(context).padding.bottom) +
                                        kBottomNavigationBarHeight +
                                        70.0;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: bottomMargin,
                                    ),
                                    content: const Text('Playing now'),
                                    backgroundColor: Colors.deepPurple.shade400,
                                  ),
                                );
                              }
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.edit,
                            title: 'Update metadata',
                            color: Colors.orange.shade400,
                            onTap: () {
                              Navigator.pop(context);
                              _updateMetadata(file);
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

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddToPlaylistDialog(File song) async {
    final audioService = context.read<AudioPlayerService>();
    final customPlaylists = audioService.customPlaylists;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Add to Playlist',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Create new playlist option
            ListTile(
              leading: Icon(Icons.add, color: Colors.deepPurple.shade400),
              title: const Text('Create New Playlist',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Create a new playlist with this song',
                  style: TextStyle(color: Colors.grey[400])),
              onTap: () async {
                Navigator.of(context).pop();
                await _createPlaylistWithSong(song);
              },
            ),
            if (customPlaylists.isNotEmpty) ...[
              const Divider(color: Colors.grey),
              // Existing playlists
              ...customPlaylists.map((playlist) => ListTile(
                    leading: playlist.artworkPath != null
                        ? Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(playlist.artworkPath!),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    playlist.artworkColor != null
                                        ? Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: Color(playlist.artworkColor!),
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                            ),
                          )
                        : playlist.artworkColor != null
                            ? Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade400,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.queue_music,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : Icon(Icons.queue_music,
                                color: Colors.deepPurple.shade400),
                    title: Text(playlist.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${playlist.songPaths.length} songs',
                        style: TextStyle(color: Colors.grey[400])),
                    onTap: () {
                      Navigator.of(context).pop();
                      audioService.addSongToCustomPlaylist(playlist.id, song);
                      Future.delayed(const Duration(milliseconds: 100), () {
                        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
                        final bottomMargin =
                            (MediaQuery.of(context).padding.bottom) +
                                kBottomNavigationBarHeight +
                                miniPlayerHeight;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: bottomMargin,
                            ),
                            content: Text('Added to ${playlist.name}'),
                            backgroundColor: Colors.deepPurple.shade400,
                          ),
                        );
                      });
                    },
                  )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylistWithSong(File song) async {
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
                        initialName: '',
                        initialArtworkPath: '',
                        initialColor: null,
                        titleText: 'Create Playlist',
                        actionText: 'Create',
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
      final playlist = await audioService.createCustomPlaylist(
        result['name'],
        artworkPath: result['artworkPath'],
        artworkColor: result['color'],
      );

      // Add the song to the newly created playlist
      audioService.addSongToCustomPlaylist(playlist.id, song);

      Future.delayed(const Duration(milliseconds: 100), () {
        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
        final bottomMargin = (MediaQuery.of(context).padding.bottom) +
            kBottomNavigationBarHeight +
            miniPlayerHeight;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomMargin,
            ),
            content: Text('Created "${result['name']}" and added song'),
            backgroundColor: Colors.deepPurple.shade400,
          ),
        );
      });
    }
  }

  Future<void> _updateMetadata(File file) async {
    final audioService = context.read<AudioPlayerService>();

    // Get current song data from cache or file
    final currentSong = await _metadataCache.createSongFromFile(file);

    Song? updatedSong;
    String? errorMessage;

    try {
      // Fetch from API by default
      updatedSong =
          await _metadataService.updateSongMetadata(currentSong).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('Metadata update timed out');
          return currentSong;
        },
      );

      // Save the updated metadata to cache
      await _metadataCache.saveMetadata(updatedSong);

      // Refresh player and queue metadata
      await audioService.refreshCurrentMetadata();

      print('Metadata update completed successfully and saved to cache');

      // Trigger UI refresh
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error in _updateMetadata: $e');
      errorMessage = e.toString();
    }

    // Show results or error
    if (errorMessage != null) {
      if (context.mounted) {
        final audioService = context.read<AudioPlayerService>();
        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
        final bottomMargin = (MediaQuery.of(context).padding.bottom) +
            kBottomNavigationBarHeight +
            miniPlayerHeight;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomMargin,
            ),
            content: Text('Error updating metadata: $errorMessage'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } else if (updatedSong != null && context.mounted) {
      final song = updatedSong;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              Icon(Icons.info_outline,
                  color: Colors.deepPurple.shade400),
              const SizedBox(width: 8),
              const Text('Updated Metadata',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (song.albumArt.isNotEmpty) ...[
                Center(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(song.albumArt),
                        width: 180,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildMetadataRow('Title', song.title),
              _buildMetadataRow('Artist', song.artist),
              _buildMetadataRow('Album', song.album),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Close',
                  style: TextStyle(color: Colors.deepPurple.shade400)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double? height;
  final double? width;

  const _ShimmerBox({this.height, this.width});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                Colors.grey[900]!,
                Colors.grey[850]!,
                Colors.grey[800]!,
                Colors.grey[850]!,
                Colors.grey[900]!,
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
          ),
        );
      },
    );
  }
}
