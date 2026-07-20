import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../services/song_metadata_cache.dart';
import '../services/itunes_service.dart';
import '../services/playlist_handler.dart';
import '../services/metadata_service.dart';
import '../widgets/create_playlist_dialog.dart';
import '../models/song.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/voxel_toast.dart';
import '../widgets/applyable_metadata_item.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/edit_metadata_sheet.dart';
import '../widgets/player_theme_wrapper.dart';
import 'dart:typed_data';
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

  String? _cachedArtistImagePath;

  @override
  void initState() {
    super.initState();
    _metadataCache.initialize();
    _fetchArtistInfo();
    _loadOrFetchArtistImage();
  }

  Future<void> _loadOrFetchArtistImage() async {
    final cacheDir = await getApplicationDocumentsDirectory();
    final safeName = widget.artistName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final filePath = '${cacheDir.path}/artist_img_$safeName.jpg';
    final file = File(filePath);
    if (await file.exists()) {
      setState(() {
        _cachedArtistImagePath = filePath;
      });
      return;
    }
    // Try to fetch from iTunes
    final artistInfo =
        await _itunesService.searchArtist(artistName: widget.artistName);
    if (artistInfo != null && artistInfo.artistLinkUrl.isNotEmpty) {
      // Try to get image from artistLinkUrl (iTunes API does not provide direct artist image, but try to get from albums)
      final albums = await _itunesService.getArtistAlbumArtworks(
          artistId: artistInfo.artistId, limit: 1);
      if (albums.isNotEmpty && albums.first.artworkUrl.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(albums.first.artworkUrl));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            await file.writeAsBytes(resp.bodyBytes);
            setState(() {
              _cachedArtistImagePath = filePath;
            });
            return;
          }
        } catch (_) {}
      }
    }
    // If not available, fallback will be handled in build
  }

  Future<void> _fetchArtistInfo() async {
    try {
      final artistInfo =
          await _itunesService.searchArtist(artistName: widget.artistName);

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

    return PlayerThemeWrapper(
      artPath: widget.artistArtwork,
      builder: (context, colorScheme, extractedColor) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: colorScheme),
          child: Builder(
            builder: (context) {
              return Scaffold(
                backgroundColor: colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 12),
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            final opacity = ((_scrollController.hasClients
                        ? _scrollController.offset
                        : 0.0) /
                    375.0)
                .clamp(0.0, 1.0);
            return AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(opacity),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: kToolbarHeight + 12,
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
                      if (_cachedArtistImagePath != null &&
                          _cachedArtistImagePath!.isNotEmpty)
                        Image.file(
                          File(_cachedArtistImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        )
                      else if (widget.artistArtwork != null &&
                          widget.artistArtwork!.isNotEmpty)
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
                          if (_artistInfo?.primaryGenre.isNotEmpty ??
                              false) ...[
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
                            widget.songs.isEmpty
                                ? 'Not in your library'
                                : '${widget.songs.length} ${widget.songs.length == 1 ? 'song' : 'songs'}',
                            style: TextStyle(
                              color: widget.songs.isEmpty
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
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

          // Play and shuffle buttons — only when songs are in library
          if (widget.songs.isNotEmpty)
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
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          audioService.playFiles(widget.songs, artistName: widget.artistName);
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
                          final shuffledSongs = List<File>.from(widget.songs)
                            ..shuffle();
                          audioService.playFiles(shuffledSongs, artistName: widget.artistName);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Songs section — only shown when songs are in library
          if (widget.songs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: const Text(
                  'Songs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: widget.songs.length > 5 ? 5 : widget.songs.length,
              itemBuilder: (context, index) {
                final file = widget.songs[index];
                final song = _metadataCache.createSongFromFile(file);
                final isCurrentPlaying = !audioService.isRadioPlaying &&
                    audioService.currentTrack?.id == file.path;

                return InkWell(
                  onTap: () {
                    audioService.playFileInContext(file, widget.songs, artistName: widget.artistName);
                  },
                  onLongPress: () {
                    final settings = Provider.of<SettingsModel>(context, listen: false);
                    if (settings.hapticsEnabled && settings.hapticsOnLongPress) {
                      HapticFeedback.mediumImpact();
                    }
                    _showSongOptionsSheet(file);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 24, right: 0, top: 6, bottom: 6),
                    child: Row(
                      children: [
                        // Album art
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: song.albumArt.isNotEmpty
                              ? Image.file(
                                  File(song.albumArt),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildDefaultAlbumArt(48),
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
                                style: TextStyle(
                                  color: isCurrentPlaying
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist.isNotEmpty
                                    ? song.artist
                                    : widget.artistName,
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
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
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
                              width: (index % 3 == 0)
                                  ? 120.0
                                  : (index % 3 == 1)
                                      ? 90.0
                                      : 105.0,
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
                        final miniPlayerHeight =
                            _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
                        final bottomPad =
                            MediaQuery.of(context).padding.bottom +
                                kBottomNavigationBarHeight +
                                miniPlayerHeight;
                        VoxelToast.show(
                          context,
                          'This album is not in your library',
                          bottomPadding: bottomPad,
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
                                placeholder: (context, url) =>
                                    const _ShimmerBox(),
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
                  childCount: _isLoadingAlbums
                      ? 4
                      : (_albums.length > 6 ? 6 : _albums.length),
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
                final isCurrentPlaying = !audioService.isRadioPlaying &&
                    audioService.currentTrack?.id == file.path;

                return InkWell(
                  onTap: () {
                    audioService.playFileInContext(file, widget.songs, artistName: widget.artistName);
                  },
                  onLongPress: () {
                    final settings = Provider.of<SettingsModel>(context, listen: false);
                    if (settings.hapticsEnabled && settings.hapticsOnLongPress) {
                      HapticFeedback.mediumImpact();
                    }
                    _showSongOptionsSheet(file);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 24, right: 0, top: 8, bottom: 8),
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
                                  errorBuilder: (_, __, ___) =>
                                      _buildDefaultAlbumArt(48),
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
                                style: TextStyle(
                                  color: isCurrentPlaying
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.album.isNotEmpty
                                    ? song.album
                                    : 'Unknown Album',
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
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
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
              height: MediaQuery.of(context).padding.bottom + 16.0,
            ),
          ),
        ],
      ),
    );
  }),
        );
      },
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => SongMenuSheet(
        song: cachedSong,
        accentColor: Colors.deepPurple.shade400,
        options: [
          SongMenuOption(
            icon: audioService.isFileLiked(file.path)
                ? Icons.favorite
                : Icons.favorite_border,
            title: audioService.isFileLiked(file.path)
                ? 'Remove from Liked Songs'
                : 'Add to Liked Songs',
            color: Colors.deepPurple.shade200,
            onTap: () {
              audioService.toggleLikeFile(file.path);
            },
          ),
          SongMenuOption(
            icon: Icons.playlist_add_rounded,
            title: 'Add to playlist',
            color: Colors.tealAccent.shade400,
            onTap: () {
              _showAddToPlaylistDialog(file);
            },
          ),
          SongMenuOption(
            icon: Icons.queue_music_rounded,
            title: 'Add to queue',
            color: Colors.blue.shade400,
            onTap: () {
              if (audioService.isRadioPlaying) {
                audioService.addToQueue(cachedSong);
                return;
              }
              if (_isMiniPlayerActive(audioService)) {
                final playlistHandler = context.read<PlaylistHandler>();
                final insertIndex = (audioService.player.currentIndex ?? 0) + 1;
                playlistHandler.insertAtQueue(cachedSong, insertIndex);

                VoxelToast.show(
                  context,
                  'Added to queue',
                  icon: Icons.queue_music_rounded,
                );
              } else {
                audioService.playFileInContextWithPlaylistId(
                    file, widget.songs, 'artist-${widget.artistName}');

                VoxelToast.show(
                  context,
                  'Playing now',
                  icon: Icons.play_arrow_rounded,
                );
              }
            },
          ),
          SongMenuOption(
            icon: Icons.edit_note_rounded,
            title: 'Edit metadata',
            color: Colors.orange.shade400,
            onTap: () async {
              return await _showManualEditDialog(
                  file, cachedSong, Colors.deepPurple.shade400);
            },
          ),
        ],
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
                                              color:
                                                  Color(playlist.artworkColor!),
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
                      VoxelToast.show(
                        context,
                        'Added to ${playlist.name}',
                        icon: Icons.playlist_add_rounded,
                      );
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
      final playlist = await audioService.createCustomPlaylist(
        result['name'],
        artworkPath: result['artworkPath'],
        artworkColor: result['color'],
      );

      // Add the song to the newly created playlist
      audioService.addSongToCustomPlaylist(playlist.id, song);

      VoxelToast.show(
        context,
        'Created "${result['name']}" and added song',
        icon: Icons.playlist_add_check_rounded,
      );
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
        VoxelToast.show(
          context,
          'Error updating metadata',
          icon: Icons.error_outline_rounded,
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
              Icon(Icons.info_outline, color: Colors.deepPurple.shade400),
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
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _showManualEditDialog(
                    file, song, Colors.deepPurple.shade400);
              },
              child: Text('Edit',
                  style: TextStyle(color: Colors.deepPurple.shade400)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK',
                  style: TextStyle(color: Colors.deepPurple.shade400)),
            ),
          ],
        ),
      );
    }
  }

  Future<Song?> _showManualEditDialog(
      File file, Song song, Color accentColor) async {
    final result = await EditMetadataSheet.show(
      context,
      song,
      file,
      accentColor,
      onAdvancedSearch: () async {
        Map<String, dynamic>? searchResult;
        await _showMetadataSearchSheet(
          context: context,
          accentColor: accentColor,
          setParentState: (fn) {},
          onApply: (res, artPath) {
            searchResult = {
              'title': res.title,
              'artist': res.artist,
              'album': res.album.isNotEmpty ? res.album : 'Unknown',
              'albumArt': artPath ?? song.albumArt,
            };
          },
          currentTitle: song.title,
          currentArtist: song.artist,
        );
        return searchResult;
      },
    );

    if (result != null && mounted) {
      final editedSong = song.copyWith(
        title: result['title'] as String,
        artist: result['artist'] as String,
        album: result['album'] as String,
        albumArt: result['albumArt'] as String,
      );
      await _metadataCache.saveMetadata(editedSong);
      final audioService = context.read<AudioPlayerService>();
      await audioService.refreshCurrentMetadata();
      if (mounted) setState(() {});
      if (mounted) {
        final bottomPad = MediaQuery.of(context).padding.bottom + 8.0;
        VoxelToast.show(context, 'Metadata updated', bottomPadding: bottomPad);
      }
      return editedSong;
    }
    return null;
  }

  Future<void> _showMetadataSearchSheet({
    required BuildContext context,
    required Color accentColor,
    required void Function(void Function()) setParentState,
    required void Function(MetadataResult result, String? artPath) onApply,
    required String currentTitle,
    required String currentArtist,
  }) async {
    final titleController = TextEditingController(text: currentTitle);
    final artistController = TextEditingController(text: currentArtist);
    Future<List<MetadataResult>>? futureResults;
    final Map<String, Future<Uint8List?>> artPreviewCache = {};

    InputDecoration searchFieldDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFF232327),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
    }

    Future<Uint8List?> fetchCoverArtPreview(String? url) async {
      if (url == null || url.isEmpty) return null;
      final candidates = <String>{
        url,
        url.replaceAll('1000x1000', '600x600'),
        url.replaceAll('1000x1000', '300x300'),
        url.replaceFirst('front-500', 'front-250'),
      }.where((e) => e.isNotEmpty).toList();
      for (final candidate in candidates) {
        try {
          final uri = Uri.parse(candidate);
          final response =
              await http.get(uri).timeout(const Duration(seconds: 3));
          if (response.statusCode >= 200 &&
              response.statusCode < 300 &&
              response.bodyBytes.isNotEmpty) {
            return response.bodyBytes;
          }
        } catch (_) {}
      }
      return null;
    }

    Future<Uint8List?> getPreviewFuture(String? url) {
      if (url == null || url.isEmpty) return Future.value(null);
      return artPreviewCache.putIfAbsent(url, () => fetchCoverArtPreview(url));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          void triggerSearch() {
            setState(() {
              futureResults = _metadataService.searchMetadataOptions(
                title: titleController.text.trim(),
                artist: artistController.text.trim(),
                limit: 12,
              );
            });
          }

          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: FractionallySizedBox(
                heightFactor: 0.88,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF151518),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                        child: Row(
                          children: [
                            Icon(Icons.travel_explore, color: accentColor),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Find Metadata',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            TextField(
                              controller: titleController,
                              style: const TextStyle(color: Colors.white),
                              decoration: searchFieldDecoration('Song title'),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: artistController,
                              style: const TextStyle(color: Colors.white),
                              decoration:
                                  searchFieldDecoration('Artist (optional)'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => triggerSearch(),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: triggerSearch,
                                icon:
                                    const Icon(Icons.search_rounded, size: 18),
                                label: const Text('Search metadata'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131316),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: FutureBuilder<List<MetadataResult>>(
                            future: futureResults,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2),
                                  ),
                                );
                              }

                              if (futureResults == null) {
                                return Center(
                                  child: Text(
                                    'Search by title and artist to get matches',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 13),
                                  ),
                                );
                              }

                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Search failed: ${snapshot.error}',
                                    style: const TextStyle(
                                        color: Colors.redAccent),
                                  ),
                                );
                              }

                              final results = snapshot.data ?? [];
                              if (results.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No matches found. Try different keywords.',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 13),
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                itemCount: results.length,
                                physics: const BouncingScrollPhysics(),
                                separatorBuilder: (_, __) => Divider(
                                    color: Colors.grey.shade800, height: 1),
                                itemBuilder: (context, index) {
                                  final res = results[index];
                                  final isITunes =
                                      (res.source ?? '').toLowerCase() ==
                                          'itunes';

                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: RepaintBoundary(
                                      child: ApplyableMetadataItem(
                                        result: res,
                                        isITunes: isITunes,
                                        metadataService: _metadataService,
                                        onApply: (artPath) {
                                          Navigator.of(ctx).pop();
                                          onApply(res, artPath);
                                        },
                                        getPreviewFuture: getPreviewFuture,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
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
