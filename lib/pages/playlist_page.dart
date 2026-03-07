import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/playlist_handler.dart';
import '../services/metadata_service.dart';
import '../services/song_metadata_cache.dart';
import '../widgets/create_playlist_dialog.dart';
import '../models/custom_playlist.dart';
import '../models/song.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:io';

enum SortOption { name, dateAdded, artist, album }

class PlaylistPage extends StatefulWidget {
  final String playlistId;
  final String title;
  final IconData icon;
  final bool allowReorder;

  const PlaylistPage({
    super.key,
    required this.playlistId,
    required this.title,
    required this.icon,
    this.allowReorder = false,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  String _searchQuery = '';
  SortOption _sortOption = SortOption.dateAdded;
  bool _isAscending = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final MetadataService _metadataService = MetadataService();
  final SongMetadataCache _metadataCache = SongMetadataCache();
  
  // Performance optimization: Cache filtered songs
  List<File>? _cachedFilteredSongs;
  String _lastSearchQuery = '';
  SortOption _lastSortOption = SortOption.dateAdded;
  bool _lastIsAscending = false;
  int _lastSongCount = 0;
  bool _isLoadingSongs = false;
  
  // Consistent playlist colors - no extraction needed
  final Color _playlistColor = Colors.deepPurple.shade400;
  late final Color _playlistColorSubtle;
  late final Color _playlistColorFaint;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeCache();
    // Set consistent colors
    _playlistColorSubtle = _playlistColor.withOpacity(0.7);
    _playlistColorFaint = _playlistColor.withOpacity(0.15);
  }

  Future<void> _initializeCache() async {
    await _metadataCache.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isMiniPlayerActive(AudioPlayerService audioService) {
    final seqState = audioService.player.sequenceState;
    return seqState?.sequence.isNotEmpty ?? false;
  }

  List<File> _getFilteredAndSortedSongs(List<File> songs) {
    // Check if we can use cached results for performance
    if (_cachedFilteredSongs != null &&
        _lastSearchQuery == _searchQuery &&
        _lastSortOption == _sortOption &&
        _lastIsAscending == _isAscending &&
        _lastSongCount == songs.length) {
      return _cachedFilteredSongs!;
    }
    
    // Process songs in chunks to avoid blocking UI for large playlists
    if (songs.length > 200 && !_isLoadingSongs) {
      _processLargePlaylists(songs);
      return _cachedFilteredSongs ?? [];
    }
    
    final entries = songs
        .map((file) => MapEntry(file, _metadataCache.createSongFromFile(file)))
        .toList();

    // Filter by search query (use title/artist/filename)
    final query = _searchQuery.toLowerCase();
    List<MapEntry<File, Song>> filtered = entries.where((entry) {
      final song = entry.value;
      final filename = entry.key.path
          .split('/')
          .last
          .replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          filename.toLowerCase().contains(query);
    }).toList();

    switch (_sortOption) {
      case SortOption.name:
        filtered.sort((a, b) {
          final nameA = a.value.title.toLowerCase();
          final nameB = b.value.title.toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
      case SortOption.dateAdded:
        if (widget.playlistId == 'liked') {
          if (_isAscending) {
            filtered = filtered.reversed.toList();
          }
        } else {
          filtered.sort((a, b) {
            final statA = a.key.statSync();
            final statB = b.key.statSync();
            return _isAscending
                ? statA.modified.compareTo(statB.modified)
                : statB.modified.compareTo(statA.modified);
          });
        }
        break;
      case SortOption.artist:
        filtered.sort((a, b) {
          final artistA = a.value.artist.toLowerCase();
          final artistB = b.value.artist.toLowerCase();
          final cmp = _isAscending
              ? artistA.compareTo(artistB)
              : artistB.compareTo(artistA);
          if (cmp != 0) return cmp;
          final nameA = a.value.title.toLowerCase();
          final nameB = b.value.title.toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
      case SortOption.album:
        filtered.sort((a, b) {
          final albumA = (a.value.album.isNotEmpty ? a.value.album : 'Unknown')
              .toLowerCase();
          final albumB = (b.value.album.isNotEmpty ? b.value.album : 'Unknown')
              .toLowerCase();
          final albumCompare = _isAscending
              ? albumA.compareTo(albumB)
              : albumB.compareTo(albumA);
          if (albumCompare != 0) return albumCompare;
          final nameA = a.value.title.toLowerCase();
          final nameB = b.value.title.toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
    }

    final result = filtered.map((e) => e.key).toList();
    
    // Cache the results for better performance
    _cachedFilteredSongs = result;
    _lastSearchQuery = _searchQuery;
    _lastSortOption = _sortOption;
    _lastIsAscending = _isAscending;
    _lastSongCount = songs.length;
    
    return result;
  }
  
  // Process large playlists asynchronously to prevent UI blocking
  void _processLargePlaylists(List<File> songs) async {
    if (_isLoadingSongs) return;
    
    setState(() {
      _isLoadingSongs = true;
    });
    
    // Process in background
    final result = await Future.microtask(() {
      final entries = songs
          .map((file) => MapEntry(file, _metadataCache.createSongFromFile(file)))
          .toList();

      final query = _searchQuery.toLowerCase();
      List<MapEntry<File, Song>> filtered = entries.where((entry) {
        final song = entry.value;
        final filename = entry.key.path
            .split('/')
            .last
            .replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
        return song.title.toLowerCase().contains(query) ||
            song.artist.toLowerCase().contains(query) ||
            filename.toLowerCase().contains(query);
      }).toList();
      
      // Apply sorting logic (same as main method)
      switch (_sortOption) {
        case SortOption.name:
          filtered.sort((a, b) {
            final nameA = a.value.title.toLowerCase();
            final nameB = b.value.title.toLowerCase();
            return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
          });
          break;
        case SortOption.dateAdded:
          if (widget.playlistId == 'liked') {
            if (_isAscending) {
              filtered = filtered.reversed.toList();
            }
          } else {
            filtered.sort((a, b) {
              final statA = a.key.statSync();
              final statB = b.key.statSync();
              return _isAscending
                  ? statA.modified.compareTo(statB.modified)
                  : statB.modified.compareTo(statA.modified);
            });
          }
          break;
        case SortOption.artist:
          filtered.sort((a, b) {
            final artistA = a.value.artist.toLowerCase();
            final artistB = b.value.artist.toLowerCase();
            final cmp = _isAscending
                ? artistA.compareTo(artistB)
                : artistB.compareTo(artistA);
            if (cmp != 0) return cmp;
            final nameA = a.value.title.toLowerCase();
            final nameB = b.value.title.toLowerCase();
            return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
          });
          break;
        case SortOption.album:
          filtered.sort((a, b) {
            final albumA = (a.value.album.isNotEmpty ? a.value.album : 'Unknown')
                .toLowerCase();
            final albumB = (b.value.album.isNotEmpty ? b.value.album : 'Unknown')
                .toLowerCase();
            final albumCompare = _isAscending
                ? albumA.compareTo(albumB)
                : albumB.compareTo(albumA);
            if (albumCompare != 0) return albumCompare;
            final nameA = a.value.title.toLowerCase();
            final nameB = b.value.title.toLowerCase();
            return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
          });
          break;
      }
      
      return filtered.map((e) => e.key).toList();
    });
    
    if (mounted) {
      setState(() {
        _cachedFilteredSongs = result;
        _lastSearchQuery = _searchQuery;
        _lastSortOption = _sortOption;
        _lastIsAscending = _isAscending;
        _lastSongCount = songs.length;
        _isLoadingSongs = false;
      });
    }
  }
  
  // Clear cache when filters change
  void _clearSongCache() {
    _cachedFilteredSongs = null;
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
              leading: Icon(Icons.add, color: _playlistColor),
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
                                errorBuilder: (_, __, ___) => playlist
                                            .artworkColor !=
                                        null
                                    ? Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Color(playlist.artworkColor!),
                                          borderRadius: BorderRadius.circular(6),
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
                                  color: _playlistColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.queue_music,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : Icon(Icons.queue_music,
                                color: _playlistColor),
                    title: Text(playlist.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${playlist.songPaths.length} songs',
                        style: TextStyle(color: Colors.grey[400])),
                    onTap: () {
                      Navigator.of(context).pop();
                      audioService.addSongToCustomPlaylist(playlist.id, song);
                      Future.delayed(const Duration(milliseconds: 100), () {
                        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
                        final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + miniPlayerHeight;
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
        final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + miniPlayerHeight;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomMargin,
            ),
            content: Text('Created "${result['name']}" and added song'),
            backgroundColor: _playlistColor,
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

      // Clear song cache to force refresh
      _clearSongCache();

      // Trigger UI refresh
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error in _updateMetadata: $e');
      errorMessage = e.toString();
    }

    // Show results or error - no loading dialog needed
    if (errorMessage != null) {
      if (context.mounted) {
        final audioService = context.read<AudioPlayerService>();
        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
        final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + miniPlayerHeight;
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
      final song = updatedSong; // Non-null variable for safe access
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              Icon(Icons.info_outline, color: _playlistColor),
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
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildMetadataRow('Title', song.title, _playlistColor),
              const SizedBox(height: 8),
              _buildMetadataRow('Artist', song.artist, _playlistColor),
              const SizedBox(height: 8),
              _buildMetadataRow('Album',
                  song.album.isNotEmpty ? song.album : 'Unknown', _playlistColor),
              if (song.duration != const Duration(minutes: 3)) ...[
                const SizedBox(height: 8),
                _buildMetadataRow(
                    'Duration', _formatDuration(song.duration), _playlistColor),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // Show edit dialog for manual correction
                await _showManualEditDialog(file, song, _playlistColor);
              },
              child: Text('Edit', style: TextStyle(color: _playlistColor)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK', style: TextStyle(color: _playlistColor)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showManualEditDialog(
      File file, Song song, Color accentColor) async {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    final albumController = TextEditingController(
        text: song.album.isEmpty ? 'Unknown' : song.album);
    String? selectedAlbumArt = song.albumArt.isNotEmpty ? song.albumArt : null;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              Icon(Icons.edit, color: accentColor),
              const SizedBox(width: 8),
              const Text('Edit Metadata',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Album Art Picker
                GestureDetector(
                  onTap: () async {
                    final ImagePicker picker = ImagePicker();
                    final XFile? image =
                        await picker.pickImage(source: ImageSource.gallery);

                    if (image != null) {
                      // Copy image to app directory
                      final appDir = await getApplicationDocumentsDirectory();
                      final fileName =
                          'album_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      final savedImage = await File(image.path)
                          .copy('${appDir.path}/$fileName');

                      setDialogState(() {
                        selectedAlbumArt = savedImage.path;
                      });
                    }
                  },
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: selectedAlbumArt != null && selectedAlbumArt!.isNotEmpty
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(selectedAlbumArt!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.add_photo_alternate,
                                      size: 50,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.add_photo_alternate,
                                size: 50,
                                color: accentColor,
                              ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to change album art',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(color: accentColor),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade700),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: artistController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Artist',
                    labelStyle: TextStyle(color: accentColor),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade700),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: albumController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Album',
                    labelStyle: TextStyle(color: accentColor),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade700),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[850],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Advanced search'),
                    onPressed: () async {
                      await _showMusicBrainzSurfer(
                        context: context,
                        accentColor: accentColor,
                        setParentState: setDialogState,
                        onApply: (result, artPath) {
                          titleController.text = result.title;
                          artistController.text = result.artist;
                          albumController.text = result.album.isNotEmpty
                              ? result.album
                              : 'Unknown';
                          setDialogState(() {
                            selectedAlbumArt =
                                artPath ?? selectedAlbumArt ?? song.albumArt;
                          });
                        },
                        currentTitle: titleController.text,
                        currentArtist: artistController.text,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'title': titleController.text.trim(),
                'artist': artistController.text.trim(),
                'album': albumController.text.trim(),
                'albumArt': selectedAlbumArt ?? song.albumArt,
              }),
              child: Text('Save', style: TextStyle(color: accentColor)),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      // Save manual edits
      final editedSong = song.copyWith(
        title: result['title'] as String,
        artist: result['artist'] as String,
        album: result['album'] as String,
        albumArt: result['albumArt'] as String,
      );

      await _metadataCache.saveMetadata(editedSong);

      // Refresh player and queue metadata
      final audioService = context.read<AudioPlayerService>();
      await audioService.refreshCurrentMetadata();

      // Clear song cache to force refresh
      _clearSongCache();

      // Refresh UI
      setState(() {});

      // Show confirmation
      if (mounted) {
        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
        final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + miniPlayerHeight;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomMargin,
            ),
            content: const Text('Metadata updated'),
            backgroundColor: _playlistColor,
          ),
        );
      }
    }
  }

  Future<void> _showMusicBrainzSurfer({
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
    final Map<String, Future<Uint8List?>> _artPreviewCache = {};

    await showDialog(
      context: context,
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
              } catch (_) {
                // Best-effort only; keep quiet to avoid log spam
              }
            }
            return null;
          }

          Future<Uint8List?> getPreviewFuture(String? url) {
            if (url == null || url.isEmpty) return Future.value(null);
            if (_artPreviewCache.containsKey(url)) {
              return _artPreviewCache[url]!;
            }
            final future = fetchCoverArtPreview(url);
            _artPreviewCache[url] = future;
            return future;
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Row(
              children: [
                Icon(Icons.travel_explore, color: accentColor),
                const SizedBox(width: 8),
                const Text('Suggestions',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Title',
                            labelStyle: TextStyle(color: accentColor),
                            enabledBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: Colors.grey.shade700),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: accentColor),
                            ),
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => triggerSearch(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: artistController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Artist (optional)',
                            labelStyle: TextStyle(color: accentColor),
                            enabledBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: Colors.grey.shade700),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: accentColor),
                            ),
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => triggerSearch(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Search'),
                      onPressed: triggerSearch,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<MetadataResult>>(
                        future: futureResults,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            );
                          }

                          if (futureResults == null) {
                            return const Center(
                              child: Text('Enter a title/artist to search',
                                  style: TextStyle(color: Colors.white70)),
                            );
                          }

                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text('Search failed: ${snapshot.error}',
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                            );
                          }

                          final results = snapshot.data ?? [];
                          if (results.isEmpty) {
                            return const Center(
                              child: Text('No results found',
                                  style: TextStyle(color: Colors.white70)),
                            );
                          }

                          return ListView.separated(
                            itemCount: results.length,
                            physics: const BouncingScrollPhysics(),
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.grey),
                            itemBuilder: (context, index) {
                              final result = results[index];
                              final isITunes =
                                  (result.source ?? '').toLowerCase() ==
                                      'itunes';

                              return RepaintBoundary(
                                child: _ApplyableMetadataItem(
                                  result: result,
                                  isITunes: isITunes,
                                  metadataService: _metadataService,
                                  onApply: (artPath) {
                                    Navigator.of(ctx).pop();
                                    onApply(result, artPath);
                                  },
                                  getPreviewFuture: getPreviewFuture,
                                ),
                              );
                            },
                          );
                        }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child:
                    const Text('Close', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );

    // Intentionally not disposing controllers here to avoid use-after-dispose during closing animations
  }

  Widget _buildMetadataRow(String label, String value, Color accentColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label:',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showSongOptionsSheet(File file, Color accentColor) {
    final audioService = context.read<AudioPlayerService>();
    final allSongs = audioService.getPlaylistSongs(widget.playlistId);
    final songs = _getFilteredAndSortedSongs(allSongs);
    final cachedSong = _metadataCache.createSongFromFile(file);
    bool dismissed = false; // Prevent double-pop affecting parent routes
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
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
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
                                                  Container(
                                                width: 75,
                                                height: 75,
                                                color: accentColor,
                                                child: const Icon(
                                                    Icons.music_note,
                                                    color: Colors.white),
                                              ),
                                            )
                                          : Container(
                                              width: 75,
                                              height: 75,
                                              color: accentColor,
                                              child: const Icon(Icons.music_note,
                                                  color: Colors.white),
                                            ),
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
                                playlistHandler.insertAtQueue(
                                    song, insertIndex);

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
                                // No mini player active: start playback with this song immediately
                                audioService.playFileInContextWithPlaylistId(
                                    file, songs, widget.playlistId);
                                
                                final bottomMargin =
                                    (MediaQuery.of(context).padding.bottom) +
                                        kBottomNavigationBarHeight +
                                        70.0; // Mini player will be active after this

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
                          _buildOptionTile(
                            icon: Icons.remove,
                            title: 'Remove from playlist',
                            color: Colors.red.shade400,
                            onTap: () {
                              Navigator.pop(context);
                              audioService.removeSongFromPlaylist(
                                  widget.playlistId, file);

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
                                  content: const Text('Removed from playlist'),
                                  backgroundColor: Colors.red.shade400,
                                ),
                              );
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

  Widget _buildSortMenu(Color playlistColor, Color _playlistColorSubtle,
      {Color? iconColor}) {
    final options = [
      (
        icon: Icons.sort_by_alpha,
        label: 'Name',
        value: SortOption.name,
      ),
      (
        icon: Icons.schedule,
        label: 'Date Added',
        value: SortOption.dateAdded,
      ),
      (
        icon: Icons.person_outline,
        label: 'Artist',
        value: SortOption.artist,
      ),
      (
        icon: Icons.album,
        label: 'Album',
        value: SortOption.album,
      ),
    ];

    final resolvedIconColor = iconColor ?? _playlistColor;

    return IconButton(
      icon: const Icon(Icons.sort),
      color: resolvedIconColor,
      tooltip: 'Sort',
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (ctx) {
            bool dismissed = false;
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
                      if (details.primaryDelta != null &&
                          details.primaryDelta! > 8) {
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
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notification) {
                      // Dismiss after the sheet settles near min extent (release)
                      if (!notification.extent.isNaN &&
                          notification.extent <=
                              notification.minExtent + 0.02) {
                        dismiss(ctx);
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      initialChildSize: 0.35,
                      minChildSize: 0.25,
                      maxChildSize: 0.6,
                      snap: true,
                      snapSizes: const [0.35, 0.6],
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
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[700],
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
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
                                            _isAscending = false;
                                          }
                                        });
                                        _clearSongCache();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                    height:
                                        MediaQuery.of(context).padding.bottom +
                                            16),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final allSongs = audioService.getPlaylistSongs(widget.playlistId);
    final songs = _getFilteredAndSortedSongs(allSongs);
    final isCustomPlaylist =
        audioService.getCustomPlaylist(widget.playlistId) != null;
    final customPlaylist = audioService.getCustomPlaylist(widget.playlistId);

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
              actions: [
                _buildSortMenu(
                  _playlistColor,
                  _playlistColorSubtle,
                  iconColor: Colors.white,
                ),
                if (isCustomPlaylist)
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    tooltip: 'Edit playlist',
                    onPressed: () => _showEditPlaylistDialog(customPlaylist!),
                  ),
                if (!_isSearching)
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                      _clearSongCache();
                    },
                  ),
              ],
            );
          },
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Hero header
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 380,
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
                      // Artwork or icon background
                      if (customPlaylist?.artworkPath != null)
                        Image.file(
                          File(customPlaylist!.artworkPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _playlistColorSubtle,
                                  _playlistColorFaint,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                widget.icon,
                                size: 100,
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _playlistColorSubtle,
                                _playlistColorFaint,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              widget.icon,
                              size: 100,
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                        ),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.6, 1.0],
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.6),
                              Colors.black,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Playlist info at bottom of hero
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isLoadingSongs
                            ? 'Loading...'
                            : '${allSongs.length} ${allSongs.length == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search bar (when active)
          if (_isSearching)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Search songs...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    prefixIcon: Icon(Icons.search, color: Colors.grey, size: 20),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                    _clearSongCache();
                  },
                ),
              ),
            ),

          // Loading indicator
          if (_isLoadingSongs)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading songs...',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),

          // Play / shuffle buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Row(
                children: [
                  // Circular play button
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
                      onPressed: (songs.isEmpty || _isLoadingSongs)
                          ? null
                          : () => audioService.playFilteredPlaylist(
                              widget.playlistId, songs),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Shuffle button
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Colors.grey[800]!, width: 1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        size: 20,
                        color: Colors.grey[400],
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: (songs.isEmpty || _isLoadingSongs)
                          ? null
                          : () {
                              final shuffled = List<File>.from(songs)
                                ..shuffle();
                              audioService.playFilteredPlaylist(
                                  widget.playlistId, shuffled);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Songs list
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final file = songs[index];
              return RepaintBoundary(
                child: _OptimizedSongTile(
                  key: ValueKey(file.path),
                  file: file,
                  audioService: audioService,
                  metadataCache: _metadataCache,
                  playlistColor: _playlistColorSubtle,
                  onTap: () => audioService.playFileInContextWithPlaylistId(
                      file, songs, widget.playlistId),
                  onMoreTap: () =>
                      _showSongOptionsSheet(file, _playlistColorSubtle),
                ),
              );
            },
          ),

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

  Future<void> _showEditPlaylistDialog(CustomPlaylist playlist) async {
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
                        initialColor: playlist.artworkColor is int ? playlist.artworkColor : null,
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

      // Update dominant color if provided
      if (result['artworkPath'] != null) {
        // No color extraction needed
      }

      if (mounted) {
        setState(() {});
        final audioService = context.read<AudioPlayerService>();
        final miniPlayerHeight = _isMiniPlayerActive(audioService) ? 70.0 : 0.0;
        final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + miniPlayerHeight;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomMargin,
            ),
            content: const Text('Playlist updated'),
            backgroundColor: _playlistColor,
          ),
        );
      }
    }
  }
}

// Optimized song tile widget for better performance
class _OptimizedSongTile extends StatefulWidget {
  final File file;
  final AudioPlayerService audioService;
  final SongMetadataCache metadataCache;
  final Color? playlistColor;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _OptimizedSongTile({
    super.key,
    required this.file,
    required this.audioService,
    required this.metadataCache,
    required this.playlistColor,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  State<_OptimizedSongTile> createState() => _OptimizedSongTileState();
}

class _OptimizedSongTileState extends State<_OptimizedSongTile>
    with AutomaticKeepAliveClientMixin {
  late Song _cachedSong;
  bool _isPlaying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cachedSong = widget.metadataCache.createSongFromFile(widget.file);
    _updatePlayingState();
    widget.audioService.currentMediaStream.listen(_onMediaChanged);
  }

  @override
  void didUpdateWidget(_OptimizedSongTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload cached song data when widget updates (e.g., after metadata edit)
    _cachedSong = widget.metadataCache.createSongFromFile(widget.file);
  }

  void _updatePlayingState() {
    final currentMedia = widget
        .audioService.player.sequenceState?.currentSource?.tag as MediaItem?;
    final newIsPlaying = currentMedia?.id == widget.file.path;
    if (_isPlaying != newIsPlaying) {
      setState(() {
        _isPlaying = newIsPlaying;
      });
    }
  }

  void _onMediaChanged(MediaItem? media) {
    _updatePlayingState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 0),
      horizontalTitleGap: 12,
      leading: _buildAlbumArt(),
      title: Text(
        _cachedSong.title,
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _cachedSong.artist,
        style: TextStyle(color: Colors.grey.shade400),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: Icon(Icons.more_vert, color: Colors.grey[400]),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: widget.onMoreTap,
      ),
      onTap: widget.onTap,
    );
  }

  Widget _buildAlbumArt() {
    if (_cachedSong.albumArt.isNotEmpty) {
      return RepaintBoundary(
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(_cachedSong.albumArt),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              cacheWidth: 150,
              cacheHeight: 150,
              errorBuilder: (_, __, ___) => _buildFallbackIcon(),
            ),
          ),
        ),
      );
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Container(
      height: 50,
      width: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: widget.playlistColor ?? Colors.deepPurple.shade400,
      ),
      child: _isPlaying
          ? const Icon(Icons.play_circle, color: Colors.white)
          : const Icon(Icons.music_note),
    );
  }
}

/// Widget for a metadata search result item with apply functionality
class _ApplyableMetadataItem extends StatefulWidget {
  final MetadataResult result;
  final bool isITunes;
  final MetadataService metadataService;
  final Function(String? artPath) onApply;
  final Future<Uint8List?> Function(String? url) getPreviewFuture;

  const _ApplyableMetadataItem({
    required this.result,
    required this.isITunes,
    required this.metadataService,
    required this.onApply,
    required this.getPreviewFuture,
  });

  @override
  State<_ApplyableMetadataItem> createState() => _ApplyableMetadataItemState();
}

class _ApplyableMetadataItemState extends State<_ApplyableMetadataItem> {
  bool _isApplying = false;

  Future<void> _applyMetadata() async {
    if (_isApplying) return;

    setState(() {
      _isApplying = true;
    });

    String? artPath;
    if (widget.result.coverArtUrl != null && widget.result.coverArtUrl!.isNotEmpty) {
      if (widget.isITunes) {
        artPath = await widget.metadataService.downloadCoverArtFromUrl(
          url: widget.result.coverArtUrl!,
          identifier: '${widget.result.artist}_${widget.result.album.isNotEmpty ? widget.result.album : widget.result.title}',
        );
      } else if (widget.result.releaseId != null) {
        artPath = await widget.metadataService.downloadCoverArtForRelease(
          releaseId: widget.result.releaseId!,
          identifier: '${widget.result.artist}_${widget.result.album.isNotEmpty ? widget.result.album : widget.result.title}',
        );
      }
    }

    if (mounted) {
      widget.onApply(artPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: FutureBuilder<Uint8List?>(
          future: widget.getPreviewFuture(widget.result.coverArtUrl),
          builder: (context, artSnap) {
            if (artSnap.connectionState == ConnectionState.waiting) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            if (artSnap.data != null) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    artSnap.data!,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.album, color: Colors.white54),
            );
          },
        ),
      ),
      title: Text(
        widget.result.title,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [widget.result.artist, widget.result.album]
                .where((e) => e.isNotEmpty)
                .join(' • '),
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.public,
                size: 16,
                color: widget.isITunes
                    ? Colors.red.shade300
                    : Colors.green.shade300,
              ),
            ],
          ),
        ],
      ),
      trailing: _isApplying
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(Icons.check_circle_outline, color: Colors.grey[400]),
              onPressed: _applyMetadata,
            ),
      onTap: _applyMetadata,
    );
  }
}
