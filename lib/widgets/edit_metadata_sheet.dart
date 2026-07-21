import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/metadata_service.dart';
import '../services/song_metadata_cache.dart';
import '../widgets/voxel_toast.dart';
import 'applyable_metadata_item.dart';
import 'squishy_action_button.dart';

class EditMetadataSheet extends StatefulWidget {
  final Song song;
  final File file;
  final Color accentColor;
  final Future<Map<String, dynamic>?> Function()? onAdvancedSearch;

  const EditMetadataSheet({
    super.key,
    required this.song,
    required this.file,
    required this.accentColor,
    this.onAdvancedSearch,
  });

  static Future<Map<String, dynamic>?> show(
      BuildContext context, Song song, File file, Color accentColor,
      {Future<Map<String, dynamic>?> Function()? onAdvancedSearch}) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => EditMetadataSheet(
          song: song,
          file: file,
          accentColor: accentColor,
          onAdvancedSearch: onAdvancedSearch,
        ),
      ),
    );
  }

  @override
  State<EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<EditMetadataSheet> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  String? _selectedAlbumArt;
  bool _isAutoUpdating = false;
  final _metadataService = MetadataService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    _albumController = TextEditingController(
        text: widget.song.album.isEmpty ? 'Unknown' : widget.song.album);
    _selectedAlbumArt =
        widget.song.albumArt.isNotEmpty ? widget.song.albumArt : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  InputDecoration _metadataFieldDecoration(String label) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      floatingLabelStyle: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.accentColor, width: 1.5),
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'album_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');

      setState(() {
        _selectedAlbumArt = savedImage.path;
      });
    }
  }

  Future<void> _autoUpdate() async {
    setState(() => _isAutoUpdating = true);
    try {
      final seedSong = widget.song.copyWith(
        title: _titleController.text.trim().isEmpty
            ? widget.song.title
            : _titleController.text.trim(),
        artist: _artistController.text.trim().isEmpty
            ? widget.song.artist
            : _artistController.text.trim(),
        album: _albumController.text.trim(),
        albumArt: _selectedAlbumArt ?? widget.song.albumArt,
      );

      final metadataService = MetadataService();
      final updated = await metadataService
          .updateSongMetadata(seedSong)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => seedSong,
          );

      if (!mounted) return;
      setState(() {
        _titleController.text = updated.title;
        _artistController.text = updated.artist;
        _albumController.text =
            updated.album.isNotEmpty ? updated.album : 'Unknown';
        if (updated.albumArt.isNotEmpty) {
          _selectedAlbumArt = updated.albumArt;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final audioService = context.read<AudioPlayerService>();
      final bottomMargin = MediaQuery.of(context).padding.bottom +
          kBottomNavigationBarHeight +
          (audioService.isMiniPlayerVisible ? 70.0 : 0.0) +
          8.0;
      VoxelToast.show(
        context,
        'Auto update failed: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isAutoUpdating = false);
      }
    }
  }

  bool _shouldClearCache = false;

  Future<void> _revertMetadata() async {
    final revertedSong = Song.fromFile(widget.file);
    setState(() {
      _shouldClearCache = true;
      _titleController.text = revertedSong.title;
      _artistController.text = revertedSong.artist;
      _albumController.text =
          revertedSong.album.isNotEmpty ? revertedSong.album : 'Unknown';
      _selectedAlbumArt = ''; // Clear selected artwork instantly
    });
    if (mounted) {
      final audioService = context.read<AudioPlayerService>();
      final bottomMargin = MediaQuery.of(context).padding.bottom +
          kBottomNavigationBarHeight +
          (audioService.isMiniPlayerVisible ? 70.0 : 0.0) +
          8.0;
      VoxelToast.show(
        context,
        'Original metadata loaded. Tap Save Changes to apply.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: widget.accentColor, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Edit Metadata',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Album Art Picker
                        GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _selectedAlbumArt != null && _selectedAlbumArt!.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.file(
                                          File(_selectedAlbumArt!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                            Icons.add_photo_alternate_rounded,
                                            size: 40,
                                            color: widget.accentColor.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.add_photo_alternate_rounded,
                                        size: 40,
                                        color: widget.accentColor.withValues(alpha: 0.5),
                                      ),
                              ),
                              // Edit Overlay
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedAlbumArt != null && _selectedAlbumArt!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: TextButton.icon(
                              onPressed: () => setState(() => _selectedAlbumArt = ''),
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                              label: const Text('Remove album art', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: _metadataFieldDecoration('Title'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _artistController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: _metadataFieldDecoration('Artist'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _albumController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: _metadataFieldDecoration('Album'),
                        ),
                        const SizedBox(height: 16),
                        
                        // Action Buttons
                        ExpressiveButtonRow(
                          leftFlex: 1.0,
                          rightFlex: 1.0,
                          left: SquishyButtonParams(
                            icon: _isAutoUpdating
                                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor))
                                : Icon(Icons.auto_fix_high_rounded, color: widget.accentColor),
                            label: Text(_isAutoUpdating ? 'Updating...' : 'Auto update'),
                            backgroundColor: widget.accentColor.withValues(alpha: 0.15),
                            foregroundColor: Colors.white,
                            onTap: _isAutoUpdating ? null : _autoUpdate,
                          ),
                          right: SquishyButtonParams(
                            icon: const Icon(Icons.travel_explore_rounded, color: Colors.blueAccent),
                            label: const Text('Search'),
                            backgroundColor: Colors.blue.withValues(alpha: 0.15),
                            foregroundColor: Colors.white,
                            onTap: () async {
                              final result = widget.onAdvancedSearch != null
                                  ? await widget.onAdvancedSearch!()
                                  : await _showBuiltInSearch(context);
                              if (result != null && mounted) {
                                setState(() {
                                  _titleController.text = result['title'] ?? '';
                                  _artistController.text = result['artist'] ?? '';
                                  _albumController.text = result['album'] ?? '';
                                  _selectedAlbumArt = result['albumArt'];
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SquishyActionButton(
                          icon: const Icon(Icons.restore_rounded, color: Colors.orangeAccent),
                          label: const Text('Revert to Original'),
                          backgroundColor: Colors.orange.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          onTap: _revertMetadata,
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                  ),
                  child: ExpressiveButtonRow(
                    leftFlex: 1.0,
                    rightFlex: 2.0,
                    left: SquishyButtonParams(
                      label: const Text('Cancel'),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      foregroundColor: Colors.white70,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    right: SquishyButtonParams(
                      label: const Text('Save Changes'),
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.white,
                      onTap: () async {
                        if (_shouldClearCache) {
                          final cache = SongMetadataCache();
                          await cache.removeMetadata(widget.song.filePath);
                        }
                        if (context.mounted) {
                          Navigator.of(context).pop({
                            'title': _titleController.text.trim(),
                            'artist': _artistController.text.trim(),
                            'album': _albumController.text.trim(),
                            'albumArt': _selectedAlbumArt ?? '',
                          });
                        }
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
  }

  Future<Map<String, dynamic>?> _showBuiltInSearch(BuildContext context) async {
    final titleController = TextEditingController(text: _titleController.text);
    final artistController = TextEditingController(text: _artistController.text);
    Future<List<MetadataResult>>? futureResults;
    final Map<String, Future<Uint8List?>> artPreviewCache = {};

    InputDecoration searchFieldDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFF232327),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

    return showModalBottomSheet<Map<String, dynamic>>(
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
            if (artPreviewCache.containsKey(url)) {
              return artPreviewCache[url]!;
            }
            final future = fetchCoverArtPreview(url);
            artPreviewCache[url] = future;
            return future;
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
                  decoration: const BoxDecoration(
                    color: Color(0xFF151518),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                            Icon(Icons.travel_explore, color: widget.accentColor),
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
                              icon: const Icon(Icons.close_rounded, color: Colors.white70),
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
                              decoration: searchFieldDecoration('Artist (optional)'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => triggerSearch(),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.accentColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: triggerSearch,
                                icon: const Icon(Icons.search_rounded, size: 18),
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
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(strokeWidth: 2.2),
                                  ),
                                );
                              }

                              if (futureResults == null) {
                                return Center(
                                  child: Text(
                                    'Search by title and artist to get matches',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                                  ),
                                );
                              }

                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Search failed: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.redAccent),
                                  ),
                                );
                              }

                              final results = snapshot.data ?? [];
                              if (results.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No matches found. Try different keywords.',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: results.length,
                                physics: const BouncingScrollPhysics(),
                                separatorBuilder: (_, __) => Divider(color: Colors.grey.shade800, height: 1),
                                itemBuilder: (context, index) {
                                  final result = results[index];
                                  final isITunes = (result.source ?? '').toLowerCase() == 'itunes';

                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: RepaintBoundary(
                                      child: ApplyableMetadataItem(
                                        result: result,
                                        isITunes: isITunes,
                                        metadataService: _metadataService,
                                        onApply: (artPath) {
                                          final finalResult = {
                                            'title': result.title,
                                            'artist': result.artist,
                                            'album': result.album.isNotEmpty ? result.album : 'Unknown',
                                            'albumArt': artPath ?? widget.song.albumArt,
                                          };
                                          Navigator.of(ctx).pop(finalResult);
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
}
