import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math' as math;
import 'voxel_toast.dart';

/// Curated pool of playlist accent colors — medium-brightness tones
/// similar in feel to the app's deepPurple.shade400, but distinct from it.
const List<Color> kPlaylistColors = [
  Color(0xFF26A69A), // Teal 400
  Color(0xFF42A5F5), // Blue 400
  Color(0xFFEC407A), // Pink 400
  Color(0xFF66BB6A), // Green 400
  Color(0xFFFF7043), // Deep Orange 400
  Color(0xFF5C6BC0), // Indigo 400
  Color(0xFF26C6DA), // Cyan 400
  Color(0xFFAB47BC), // Purple 400
  Color(0xFFEF5350), // Red 400
  Color(0xFF29B6F6), // Light Blue 400
  Color(0xFFFFCA28), // Amber 400
  Color(0xFF9CCC65), // Light Green 400
  Color(0xFF8D6E63), // Brown 300
  Color(0xFF78909C), // Blue Grey 400
  Color(0xFFF06292), // Pink 300
  Color(0xFF4DD0E1), // Cyan 300
];

class CreatePlaylistDialog extends StatefulWidget {
  final String? initialName;
  final String? initialArtworkPath;
  final int? initialColor;
  final String titleText;
  final String actionText;
  final bool useBottomSheetStyle;
  final ScrollController? sheetScrollController;

  const CreatePlaylistDialog({
    super.key,
    this.initialName,
    this.initialArtworkPath,
    this.initialColor,
    this.titleText = 'Create Playlist',
    this.actionText = 'Create',
    this.useBottomSheetStyle = false,
    this.sheetScrollController,
  });

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  late final TextEditingController _nameController;
  final ImagePicker _picker = ImagePicker();
  String? _selectedImagePath;
  Color? _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedImagePath = widget.initialArtworkPath;
    if (widget.initialColor != null) {
      _selectedColor = Color(widget.initialColor!);
    } else if ((widget.initialArtworkPath == null || widget.initialArtworkPath!.isEmpty) &&
               (widget.initialName == null || widget.initialName!.isEmpty)) {
      // Auto-assign a random color from the curated pool ONLY for new creations
      _selectedColor = kPlaylistColors[math.Random().nextInt(kPlaylistColors.length)];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final scheme = Theme.of(context).colorScheme;
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: scheme.surfaceContainerHigh,
          title: Text('Choose Artwork Source', style: TextStyle(color: scheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(Icons.photo_library, color: _selectedColor ?? scheme.primary),
                  title: Text('From Gallery', style: TextStyle(color: scheme.onSurface)),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(Icons.camera_alt, color: _selectedColor ?? scheme.primary),
                  title: Text('Take Photo', style: TextStyle(color: scheme.onSurface)),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      );
      
      if (source != null) {
        await _pickImageFromSource(source);
      }
    } catch (e) {
      if (mounted) {
        VoxelToast.show(
          context,
          'Error opening camera/gallery.',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }
  
  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 85,
      );
      
      if (image != null && mounted) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        VoxelToast.show(
          context,
          'Error selecting image.',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.useBottomSheetStyle) {
      return _buildBottomSheetContent(context);
    }

    final accentColor = _selectedColor ?? scheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 320,
        decoration: BoxDecoration(
          color: Color.lerp(accentColor, scheme.surfaceContainerHigh, 0.88),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: accentColor.withOpacity(0.24),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                children: [
                  Icon(
                    widget.titleText.contains('Folder')
                        ? Icons.folder_rounded
                        : Icons.queue_music_rounded,
                    color: accentColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.titleText,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form
              _buildFormContent(),
              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant.withOpacity(0.8),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: accentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop({
                        'name': _nameController.text.trim(),
                        'artworkPath': _selectedImagePath,
                        'color': _selectedColor?.value,
                      });
                    },
                    child: Text(
                      widget.actionText,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = _selectedColor ?? scheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Artwork block
        Center(
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withOpacity(0.4),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: _selectedImagePath != null
                  ? Image.file(
                      File(_selectedImagePath!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : Container(
                      color: accentColor,
                      alignment: Alignment.center,
                      child: Icon(
                        widget.titleText.contains('Folder')
                            ? Icons.folder_open_rounded
                            : Icons.queue_music_rounded,
                        color: accentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                        size: 48,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Image pick buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: _pickImage,
              icon: Icon(Icons.add_photo_alternate_rounded, size: 16, color: accentColor),
              label: Text('Artwork', style: TextStyle(color: scheme.onSurface, fontSize: 12)),
            ),
            if (_selectedImagePath != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.error.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => setState(() {
                  _selectedImagePath = null;
                  _selectedColor = kPlaylistColors[0];
                }),
                icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
                label: Text('Remove', style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Text Field
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 14.5),
          cursorColor: accentColor,
          decoration: InputDecoration(
            labelText: widget.titleText.contains('Folder') ? 'Bookmark Name' : 'Playlist Name',
            labelStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(0.7), fontSize: 13),
            floatingLabelStyle: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Quick Inline Color presets selector
        if (_selectedImagePath == null) ...[
          Text(
            'THEME ACCENT',
            style: TextStyle(
              color: scheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kPlaylistColors.length,
              itemBuilder: (context, index) {
                final color = kPlaylistColors[index];
                final isSelected = _selectedColor?.value == color.value;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2.5)
                          : Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 6,
                                spreadRadius: 1.5,
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            size: 14,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomSheetContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SingleChildScrollView(
            controller: widget.sheetScrollController,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titleText,
                  style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildFormContent(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop({
                          'name': _nameController.text.trim(),
                          'artworkPath': _selectedImagePath,
                          'color': _selectedColor?.value,
                        });
                      },
                      child: Text(widget.actionText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
