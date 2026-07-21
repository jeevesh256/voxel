import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math' as math;
import 'voxel_toast.dart';
import 'squishy_action_button.dart';

/// Curated pool of vibrant Material accent colors for playlists.
const List<Color> kPlaylistColors = [
  Color(0xFF26A69A), // Teal 400
  Color(0xFF42A5F5), // Blue 400
  Color(0xFFEC407A), // Pink 400
  Color(0xFF66BB6A), // Green 400
  Color(0xFFFF7043), // Deep Orange 400
  Color(0xFFAB47BC), // Purple 400
  Color(0xFF5C6BC0), // Indigo 400
  Color(0xFF26C6DA), // Cyan 400
  Color(0xFFEF5350), // Red 400
  Color(0xFF29B6F6), // Light Blue 400
  Color(0xFFFFCA28), // Amber 400
  Color(0xFF9CCC65), // Light Green 400
  Color(0xFF8D6E63), // Brown 300
  Color(0xFF78909C), // Blue Grey 400
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
      _selectedColor = kPlaylistColors[math.Random().nextInt(kPlaylistColors.length)];
    } else {
      _selectedColor = kPlaylistColors[0];
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
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: scheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2.25),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Choose Artwork Source',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ExpressiveButtonRow(
                  leftFlex: 1.0,
                  rightFlex: 1.0,
                  left: SquishyButtonParams(
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                  ),
                  right: SquishyButtonParams(
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Camera'),
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    onTap: () => Navigator.of(context).pop(ImageSource.camera),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
      
      if (source != null) {
        final XFile? image = await _picker.pickImage(
          source: source,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 85,
        );
        if (image != null && mounted) {
          setState(() {
            _selectedImagePath = image.path;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        VoxelToast.show(context, 'Could not select image', icon: Icons.error_outline_rounded);
      }
    }
  }

  void _submit() {
    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'artworkPath': _selectedImagePath,
      'color': _selectedColor?.value,
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    final rawSeed = _selectedColor ?? appTheme.colorScheme.primary;

    // Generate dynamic M3 dark ColorScheme seeded by the vibrant playlist color!
    final dynamicScheme = ColorScheme.fromSeed(
      seedColor: rawSeed,
      brightness: Brightness.dark,
    );

    final isFolder = widget.titleText.contains('Folder');
    // Use Icons.queue_music_rounded for playlist artwork — matching Library & Home 1:1
    final playlistIcon = isFolder ? Icons.folder_open_rounded : Icons.queue_music_rounded;

    return AnimatedTheme(
      data: appTheme.copyWith(colorScheme: dynamicScheme),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final backgroundColor = scheme.surfaceContainerHigh;

          // Theme blended accent matching Homepage / Library Page
          final themedAccent = Color.lerp(rawSeed, scheme.surface, 0.70) ?? rawSeed;
          final gradientEnd = Color.lerp(themedAccent, scheme.primary, 0.15) != null
              ? Color.lerp(Color.lerp(themedAccent, scheme.primary, 0.15)!, Colors.black, 0.20)!
              : themedAccent;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.25),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header: 64x64 Artwork Tile + Title/Subtitle (matching Library 1:1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Interactive Cover Art Tile matching Library's Icons.queue_music_rounded 1:1
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _pickImage();
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: 64,
                                    height: 64,
                                    color: const Color(0xFF121212),
                                    child: _selectedImagePath != null
                                        ? Image.file(
                                            File(_selectedImagePath!),
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                          )
                                        : AnimatedContainer(
                                            duration: const Duration(milliseconds: 250),
                                            width: 64,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  themedAccent,
                                                  gradientEnd,
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              playlistIcon,
                                              size: 30,
                                              color: themedAccent.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                                // Floating Camera Badge
                                Positioned(
                                  bottom: -3,
                                  right: -3,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: backgroundColor, width: 2),
                                    ),
                                    child: Icon(
                                      Icons.photo_camera_rounded,
                                      size: 12,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                // Floating Remove Image Badge
                                if (_selectedImagePath != null)
                                  Positioned(
                                    top: -4,
                                    left: -4,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        setState(() {
                                          _selectedImagePath = null;
                                          _selectedColor = kPlaylistColors[0];
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: scheme.errorContainer,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: backgroundColor, width: 1.5),
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 10,
                                          color: scheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Title & Subtitle
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _nameController.text.isNotEmpty
                                      ? _nameController.text
                                      : (isFolder ? 'Pinned Folder' : 'Playlist'),
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.titleText,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
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
                    const SizedBox(height: 20),

                    // Full-Width Pill Input Field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _nameController,
                        builder: (context, value, _) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 54,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(27),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              children: [
                                Icon(
                                  isFolder ? Icons.folder_rounded : Icons.queue_music_rounded,
                                  color: scheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _nameController,
                                    cursorColor: scheme.primary,
                                    autofocus: widget.initialName == null || widget.initialName!.isEmpty,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: isFolder ? 'Folder Name' : 'Playlist Name',
                                      hintStyle: TextStyle(
                                        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      border: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) => _submit(),
                                  ),
                                ),
                                if (value.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _nameController.clear();
                                      setState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.cancel_rounded,
                                        size: 18,
                                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Vibrant & Colorful Theme Accent Swatches Row
                    if (_selectedImagePath == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Icon(Icons.palette_rounded, size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'THEME ACCENT',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: kPlaylistColors.length,
                          itemBuilder: (context, index) {
                            final rawColor = kPlaylistColors[index];
                            final isSelected = _selectedColor?.value == rawColor.value;

                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _selectedColor = rawColor;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOutCubic,
                                margin: const EdgeInsets.only(right: 12),
                                width: isSelected ? 48 : 42,
                                height: isSelected ? 48 : 42,
                                decoration: BoxDecoration(
                                  color: rawColor,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(color: Colors.white, width: 3)
                                      : Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: rawColor.withValues(alpha: 0.7),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: rawColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Expressive Action Buttons Row (Seeded M3 Colors)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ExpressiveButtonRow(
                        leftFlex: 2.0,
                        rightFlex: 1.0,
                        left: SquishyButtonParams(
                          icon: const Icon(Icons.check_rounded),
                          label: Text(widget.actionText),
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          onTap: _submit,
                        ),
                        right: SquishyButtonParams(
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Cancel'),
                          backgroundColor: scheme.surfaceContainerHighest,
                          foregroundColor: scheme.onSurfaceVariant,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
