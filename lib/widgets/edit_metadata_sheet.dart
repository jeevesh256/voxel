import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/metadata_service.dart';
import '../services/song_metadata_cache.dart';
import '../widgets/voxel_toast.dart';

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
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: widget.accentColor),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        bottomPadding: bottomMargin,
      );
    } finally {
      if (mounted) {
        setState(() => _isAutoUpdating = false);
      }
    }
  }

  Future<void> _revertMetadata() async {
    final cache = SongMetadataCache();
    await cache.removeMetadata(widget.song.filePath);
    final revertedSong = Song.fromFile(widget.file);
    setState(() {
      _titleController.text = revertedSong.title;
      _artistController.text = revertedSong.artist;
      _albumController.text =
          revertedSong.album.isNotEmpty ? revertedSong.album : 'Unknown';
      _selectedAlbumArt = revertedSong.albumArt.isNotEmpty ? revertedSong.albumArt : null;
    });
    if (mounted) {
      final audioService = context.read<AudioPlayerService>();
      final bottomMargin = MediaQuery.of(context).padding.bottom +
          kBottomNavigationBarHeight +
          (audioService.isMiniPlayerVisible ? 70.0 : 0.0) +
          8.0;
      VoxelToast.show(
        context,
        'Reverted to original metadata',
        bottomPadding: bottomMargin,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1F).withOpacity(0.95),
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
                    color: Colors.white.withOpacity(0.2),
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
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        // Album Art Picker
                        GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: _selectedAlbumArt != null && _selectedAlbumArt!.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Image.file(
                                          File(_selectedAlbumArt!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                            Icons.add_photo_alternate_rounded,
                                            size: 60,
                                            color: widget.accentColor.withOpacity(0.5),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.add_photo_alternate_rounded,
                                        size: 60,
                                        color: widget.accentColor.withOpacity(0.5),
                                      ),
                              ),
                              // Edit Overlay
                              Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedAlbumArt != null && _selectedAlbumArt!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: TextButton.icon(
                              onPressed: () => setState(() => _selectedAlbumArt = ''),
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              label: const Text('Remove album art', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.redAccent.withOpacity(0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: _metadataFieldDecoration('Title'),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _artistController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: _metadataFieldDecoration('Artist'),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _albumController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: _metadataFieldDecoration('Album'),
                        ),
                        const SizedBox(height: 32),
                        
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isAutoUpdating ? null : _autoUpdate,
                                icon: _isAutoUpdating
                                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor))
                                    : Icon(Icons.auto_fix_high_rounded, color: widget.accentColor),
                                label: Text(
                                  _isAutoUpdating ? 'Updating...' : 'Auto update',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.accentColor.withOpacity(0.15),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.onAdvancedSearch != null) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final result = await widget.onAdvancedSearch!();
                                    if (result != null && mounted) {
                                      setState(() {
                                        _titleController.text = result['title'];
                                        _artistController.text = result['artist'];
                                        _albumController.text = result['album'];
                                        _selectedAlbumArt = result['albumArt'];
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.travel_explore_rounded, color: Colors.blue),
                                  label: const Text('Search', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.blue.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _revertMetadata,
                            icon: const Icon(Icons.restore_rounded, color: Colors.orange),
                            label: const Text('Revert to Original', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop({
                              'title': _titleController.text.trim(),
                              'artist': _artistController.text.trim(),
                              'album': _albumController.text.trim(),
                              'albumArt': _selectedAlbumArt ?? widget.song.albumArt,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 4,
                            shadowColor: widget.accentColor.withOpacity(0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
