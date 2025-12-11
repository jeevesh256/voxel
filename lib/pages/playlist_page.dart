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
import 'package:palette_generator/palette_generator.dart';
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
  Color? _dominantColor;
  bool _isLoadingColor = false;
  final MetadataService _metadataService = MetadataService();
  final SongMetadataCache _metadataCache = SongMetadataCache();

  @override
  void initState() {
    super.initState();
    _initializeCache();
    // Extract color when the widget initializes - do it once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extractColorIfNeeded();
    });
  }

  Future<void> _initializeCache() async {
    await _metadataCache.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Color?> _extractDominantColor(String imagePath) async {
    try {
      setState(() {
        _isLoadingColor = true;
      });
      
      final imageProvider = FileImage(File(imagePath));
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 6, // Reduced for better performance
      );
      
      // Simple fallback chain - just get any available color
      Color? dominantColor = paletteGenerator.vibrantColor?.color ?? 
                           paletteGenerator.dominantColor?.color;
      
      setState(() {
        _dominantColor = dominantColor;
        _isLoadingColor = false;
      });
      
      return dominantColor;
    } catch (e) {
      setState(() {
        _isLoadingColor = false;
      });
      return null;
    }
  }

  void _extractColorIfNeeded() {
    final audioService = context.read<AudioPlayerService>();
    final customPlaylist = audioService.getCustomPlaylist(widget.playlistId);
    if (customPlaylist?.artworkPath != null && _dominantColor == null && !_isLoadingColor) {
      // Only extract if the image file exists to avoid unnecessary work
      if (File(customPlaylist!.artworkPath!).existsSync()) {
        _extractDominantColor(customPlaylist.artworkPath!);
      }
    }
  }

  bool _isMiniPlayerActive(AudioPlayerService audioService) {
    final seqState = audioService.player.sequenceState;
    return seqState?.sequence.isNotEmpty ?? false;
  }

  List<File> _getFilteredAndSortedSongs(List<File> songs) {
    final entries = songs.map((file) => MapEntry(file, _metadataCache.createSongFromFile(file))).toList();

    // Filter by search query (use title/artist/filename)
    final query = _searchQuery.toLowerCase();
    List<MapEntry<File, Song>> filtered = entries.where((entry) {
      final song = entry.value;
      final filename = entry.key.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
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
          final cmp = _isAscending ? artistA.compareTo(artistB) : artistB.compareTo(artistA);
          if (cmp != 0) return cmp;
          final nameA = a.value.title.toLowerCase();
          final nameB = b.value.title.toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
      case SortOption.album:
        filtered.sort((a, b) {
          final albumA = (a.value.album.isNotEmpty ? a.value.album : 'Unknown').toLowerCase();
          final albumB = (b.value.album.isNotEmpty ? b.value.album : 'Unknown').toLowerCase();
          final albumCompare = _isAscending ? albumA.compareTo(albumB) : albumB.compareTo(albumA);
          if (albumCompare != 0) return albumCompare;
          final nameA = a.value.title.toLowerCase();
          final nameB = b.value.title.toLowerCase();
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
    }

    return filtered.map((e) => e.key).toList();
  }

  Future<void> _showAddToPlaylistDialog(File song) async {
    final audioService = context.read<AudioPlayerService>();
    final customPlaylists = audioService.customPlaylists;
    final currentCustomPlaylist = audioService.getCustomPlaylist(widget.playlistId);
    
    // Determine the color to use
    Color dialogColor = Colors.deepPurple.shade400; // Default color
    if (currentCustomPlaylist?.artworkColor != null) {
      dialogColor = Color(currentCustomPlaylist!.artworkColor!);
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Create new playlist option
            ListTile(
              leading: Icon(Icons.add, color: dialogColor),
              title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
              subtitle: Text('Create a new playlist with this song', style: TextStyle(color: Colors.grey[400])),
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
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
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
                      )
                    : playlist.artworkColor != null
                        ? Container(
                            width: 40,
                            height: 40,
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
                        : Icon(Icons.queue_music, color: Colors.deepPurple.shade400),
                title: Text(playlist.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${playlist.songPaths.length} songs', style: TextStyle(color: Colors.grey[400])),
                onTap: () {
                  Navigator.of(context).pop();
                  audioService.addSongToCustomPlaylist(playlist.id, song);
                  Future.delayed(const Duration(milliseconds: 100), () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created "${result['name']}" and added song'),
            backgroundColor: result['color'] != null ? Color(result['color']) : Colors.deepPurple.shade400,
          ),
        );
      });
    }
  }

  Future<void> _updateMetadata(File file) async {
    final audioService = context.read<AudioPlayerService>();
    final customPlaylist = audioService.getCustomPlaylist(widget.playlistId);
    
    Color dialogColor = Colors.deepPurple.shade400;
    if (customPlaylist?.artworkColor != null) {
      dialogColor = Color(customPlaylist!.artworkColor!);
    }

    // Get current song data from cache or file
    final currentSong = await _metadataCache.createSongFromFile(file);
    
    Song? updatedSong;
    String? errorMessage;

    try {
      // Fetch from API by default
      updatedSong = await _metadataService.updateSongMetadata(currentSong).timeout(
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
      audioService.notifyListeners();
      
      print('Metadata update completed successfully and saved to cache');
      
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
              Icon(Icons.info_outline, color: dialogColor),
              const SizedBox(width: 8),
              const Text('Updated Metadata', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (song.albumArt.isNotEmpty) ...[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(song.albumArt),
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildMetadataRow('Title', song.title, dialogColor),
              const SizedBox(height: 8),
              _buildMetadataRow('Artist', song.artist, dialogColor),
              const SizedBox(height: 8),
              _buildMetadataRow('Album', song.album.isNotEmpty ? song.album : 'Unknown', dialogColor),
              if (song.duration != const Duration(minutes: 3)) ...[
                const SizedBox(height: 8),
                _buildMetadataRow('Duration', _formatDuration(song.duration), dialogColor),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // Show edit dialog for manual correction
                await _showManualEditDialog(file, song, dialogColor);
              },
              child: Text('Edit', style: TextStyle(color: dialogColor)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK', style: TextStyle(color: dialogColor)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showManualEditDialog(File file, Song song, Color accentColor) async {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    final albumController = TextEditingController(text: song.album.isEmpty ? 'Unknown' : song.album);
    String? selectedAlbumArt = song.albumArt.isNotEmpty ? song.albumArt : null;
    bool applyingCandidate = false;
    String? applyingCandidateId;
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: [
              Icon(Icons.edit, color: accentColor),
              const SizedBox(width: 8),
              const Text('Edit Metadata', style: TextStyle(color: Colors.white)),
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
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    
                    if (image != null) {
                      // Copy image to app directory
                      final appDir = await getApplicationDocumentsDirectory();
                      final fileName = 'album_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');
                      
                      setDialogState(() {
                        selectedAlbumArt = savedImage.path;
                      });
                    }
                  },
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: selectedAlbumArt != null && selectedAlbumArt!.isNotEmpty
                        ? ClipRRect(
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          albumController.text = result.album.isNotEmpty ? result.album : 'Unknown';
                          setDialogState(() {
                            selectedAlbumArt = artPath ?? selectedAlbumArt ?? song.albumArt;
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
      audioService.notifyListeners();
      
      // Refresh UI
      setState(() {});
      
      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Metadata updated'),
            backgroundColor: accentColor,
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
                final response = await http.get(uri).timeout(const Duration(seconds: 3));
                if (response.statusCode >= 200 && response.statusCode < 300 && response.bodyBytes.isNotEmpty) {
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
                const Text('Suggestions', style: TextStyle(color: Colors.white)),
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
                              borderSide: BorderSide(color: Colors.grey.shade700),
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
                              borderSide: BorderSide(color: Colors.grey.shade700),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }

                        if (futureResults == null) {
                          return const Center(
                            child: Text('Enter a title/artist to search', style: TextStyle(color: Colors.white70)),
                          );
                        }

                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Text('Search failed: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                          );
                        }

                        final results = snapshot.data ?? [];
                        if (results.isEmpty) {
                          return const Center(
                            child: Text('No results found', style: TextStyle(color: Colors.white70)),
                          );
                        }

                        return ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.grey),
                          itemBuilder: (context, index) {
                            final result = results[index];
                            bool isApplying = false;
                            final isITunes = (result.source ?? '').toLowerCase() == 'itunes';

                            return StatefulBuilder(
                              builder: (context, setRowState) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: FutureBuilder<Uint8List?>(
                                      future: getPreviewFuture(result.coverArtUrl),
                                      builder: (context, artSnap) {
                                        if (artSnap.connectionState == ConnectionState.waiting) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey[850],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Center(
                                              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                            ),
                                          );
                                        }

                                        if (artSnap.data != null) {
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: Image.memory(
                                              artSnap.data!,
                                              fit: BoxFit.cover,
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
                                  title: Text(result.title, style: const TextStyle(color: Colors.white)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [result.artist, result.album].where((e) => e != null && e.isNotEmpty).join(' • '),
                                        style: TextStyle(color: Colors.grey[400]),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.public,
                                            size: 16,
                                            color: isITunes ? Colors.red.shade300 : Colors.green.shade300,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: isApplying
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : TextButton(
                                          onPressed: () async {
                                            if (isApplying) return;
                                            setRowState(() => isApplying = true);

                                            String? artPath;
                                            final identifier = '${result.artist}_${result.title}';

                                            // Try official cover art download first
                                            if (result.releaseId != null && result.releaseId!.isNotEmpty) {
                                              artPath = await _metadataService.downloadCoverArtForRelease(
                                                releaseId: result.releaseId!,
                                                identifier: identifier,
                                              );
                                            }

                                            // Fallback: use preview-loaded bytes if download failed
                                            if (artPath == null) {
                                              final previewBytes = await fetchCoverArtPreview(result.coverArtUrl);
                                              if (previewBytes != null) {
                                                artPath = await _metadataService.saveAlbumArtBytes(
                                                  bytes: previewBytes,
                                                  identifier: identifier,
                                                );
                                              }
                                            }

                                            // Last resort: direct download from URL if still nothing (e.g., iTunes high-res art)
                                            if (artPath == null && result.coverArtUrl != null && result.coverArtUrl!.isNotEmpty) {
                                              artPath = await _metadataService.downloadCoverArtFromUrl(
                                                url: result.coverArtUrl!,
                                                identifier: identifier,
                                              );
                                            }

                                            onApply(result, artPath);
                                            Navigator.of(ctx).pop();
                                          },
                                          child: Text('Use', style: TextStyle(color: accentColor)),
                                        ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close', style: TextStyle(color: Colors.grey)),
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
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: cachedSong.albumArt.isNotEmpty
                                        ? Image.file(
                                            File(cachedSong.albumArt),
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 60,
                                              height: 60,
                                              color: Colors.grey[800],
                                              child: const Icon(Icons.music_note, color: Colors.white),
                                            ),
                                          )
                                        : Container(
                                            width: 60,
                                            height: 60,
                                            color: Colors.grey[800],
                                            child: const Icon(Icons.music_note, color: Colors.white),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cachedSong.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          cachedSong.artist,
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
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
                              final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + 70.0;

                              if (_isMiniPlayerActive(audioService)) {
                                final playlistHandler = context.read<PlaylistHandler>();
                                final song = _metadataCache.createSongFromFile(file);
                                final insertIndex = (audioService.player.currentIndex ?? 0) + 1;
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
                                // No mini player active: start playback with this song immediately
                                audioService.playFileInContextWithPlaylistId(file, songs, widget.playlistId);

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
                              audioService.removeSongFromPlaylist(widget.playlistId, file);

                              final bottomMargin = (MediaQuery.of(context).padding.bottom) + kBottomNavigationBarHeight + 70.0;

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
                          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
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

  Widget _buildSortMenu(Color playlistColor, Color playlistColorSubtle, {Color? iconColor}) {
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

    final resolvedIconColor = iconColor ?? playlistColor;

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
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notification) {
                      // Dismiss after the sheet settles near min extent (release)
                      if (!notification.extent.isNaN &&
                          notification.extent <= notification.minExtent + 0.02) {
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
                                      margin: const EdgeInsets.symmetric(vertical: 12),
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
                                      leading: Icon(opt.icon, color: isSelected ? Colors.white : Colors.grey),
                                      title: Text(
                                        opt.label,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(
                                              _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
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
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
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
    final isCustomPlaylist = audioService.getCustomPlaylist(widget.playlistId) != null;
    final customPlaylist = audioService.getCustomPlaylist(widget.playlistId);
    
    // Only extract color once - don't call in build method
    
    // Determine the color to use for the playlist
    Color playlistColor = Colors.deepPurple.shade400; // Default color
    
    // Use dynamic color from image if available, otherwise use stored color
    if (_dominantColor != null) {
      playlistColor = _dominantColor!;
    } else if (customPlaylist?.artworkColor != null) {
      playlistColor = Color(customPlaylist!.artworkColor!);
    }
    
    // Create subtle variations for different UI elements
    final playlistColorSubtle = playlistColor.withOpacity(0.7);
    final playlistColorFaint = playlistColor.withOpacity(0.15);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            toolbarHeight: 72,
            collapsedHeight: 86,
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.title,
                textAlign: TextAlign.center,
              ),
              centerTitle: true,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Background image if available
                  if (customPlaylist?.artworkPath != null)
                    Image.file(
                      File(customPlaylist!.artworkPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              playlistColorSubtle,
                              playlistColorFaint,
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            playlistColorSubtle,
                            playlistColorFaint,
                          ],
                        ),
                      ),
                    ),
                  // Simple gradient overlay - darker for image playlists
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: customPlaylist?.artworkPath != null
                            ? [
                                Colors.black.withOpacity(0.1),
                                Colors.black.withOpacity(0.7),
                              ]
                            : [
                                Colors.black.withOpacity(0.2),
                                Colors.black.withOpacity(0.6),
                              ],
                      ),
                    ),
                  ),
                  // Icon overlay
                  Center(
                    child: customPlaylist?.artworkPath != null
                        ? Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icon,
                              size: 40,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            widget.icon,
                            size: 64,
                            color: Colors.white.withOpacity(0.9),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildSortMenu(
                  playlistColor,
                  playlistColorSubtle,
                  iconColor: isCustomPlaylist ? Colors.white : null,
                ),
              ),
              if (isCustomPlaylist)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton(
                    icon: const Icon(Icons.edit),
                    color: Colors.white,
                    tooltip: 'Edit playlist',
                    onPressed: () => _showEditPlaylistDialog(customPlaylist!),
                  ),
                ),
              if (!_isSearching)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton(
                    icon: const Icon(Icons.search),
                    color: isCustomPlaylist ? Colors.white : null,
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                ),
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  ),
                ),
            ],
          ),
          // Search Bar (only when searching)
          if (_isSearching)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search songs...',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Play All Button
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, _isSearching ? 0 : 16, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: songs.isEmpty ? null : () {
                    // Play the filtered and sorted songs that the user actually sees
                    audioService.playFilteredPlaylist(widget.playlistId, songs);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: playlistColorSubtle,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text('Play All (${songs.length} songs)'),
                ),
              ),
            ),
          ),
          // Songs List
          if (isCustomPlaylist && !_isSearching && _searchQuery.isEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final file = songs[index];
                  final cachedSong = _metadataCache.createSongFromFile(file);
                  
                  return StreamBuilder<MediaItem?>(
                    key: ValueKey(file.path),
                    stream: audioService.currentMediaStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data?.id == file.path;
                      
                      return ListTile(
                        leading: cachedSong.albumArt.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.file(
                                  File(cachedSong.albumArt),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 40,
                                    width: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Colors.deepPurple.shade200,
                                    ),
                                    child: isPlaying
                                        ? const Icon(Icons.play_circle, color: Colors.white)
                                        : const Icon(Icons.music_note),
                                  ),
                                ),
                              )
                            : Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: Colors.deepPurple.shade200,
                                ),
                                child: isPlaying
                                    ? const Icon(Icons.play_circle, color: Colors.white)
                                    : const Icon(Icons.music_note),
                              ),
                        title: Text(
                          cachedSong.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          cachedSong.artist,
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                          onPressed: () => _showSongOptionsSheet(file, playlistColorSubtle),
                        ),
                        onTap: () {
                          audioService.playFileInContextWithPlaylistId(file, songs, widget.playlistId);
                        },
                      );
                    },
                  );
                },
                childCount: songs.length,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final file = songs[index];
                  final cachedSong = _metadataCache.createSongFromFile(file);
                  
                  return StreamBuilder<MediaItem?>(
                    stream: audioService.currentMediaStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data?.id == file.path;
                      
                      return ListTile(
                        leading: cachedSong.albumArt.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.file(
                                  File(cachedSong.albumArt),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 40,
                                    width: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Colors.deepPurple.shade200,
                                    ),
                                    child: isPlaying
                                        ? const Icon(Icons.play_circle, color: Colors.white)
                                        : const Icon(Icons.music_note),
                                  ),
                                ),
                              )
                            : Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: Colors.deepPurple.shade200,
                                ),
                                child: isPlaying
                                    ? const Icon(Icons.play_circle, color: Colors.white)
                                    : const Icon(Icons.music_note),
                              ),
                        title: Text(
                          cachedSong.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          cachedSong.artist,
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                          onPressed: () => _showSongOptionsSheet(file, playlistColorSubtle),
                        ),
                        onTap: () {
                          audioService.playFileInContextWithPlaylistId(file, songs, widget.playlistId);
                        },
                      );
                    },
                  );
                },
                childCount: songs.length,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + // Device bottom padding
                        kBottomNavigationBarHeight + // Navigation bar height (usually 56)
                        60.0, // Mini player height
              ),
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

      // Update dominant color if provided
      if (result['artworkPath'] != null) {
        _extractDominantColor(result['artworkPath'] as String);
      } else if (result['color'] != null) {
        setState(() {
          _dominantColor = Color(result['color'] as int);
        });
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Playlist updated'),
            backgroundColor: Colors.deepPurple.shade400,
          ),
        );
      }
    }
  }
}
