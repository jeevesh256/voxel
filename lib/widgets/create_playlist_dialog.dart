import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math' as math;

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
    } else if (widget.initialArtworkPath == null || widget.initialArtworkPath!.isEmpty) {
      // Auto-assign a random color from the curated pool
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
      // Show options for image source or color selection
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Choose Artwork', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.deepPurple),
                title: const Text('From Gallery', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop({'type': 'gallery'}),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop({'type': 'camera'}),
              ),
              ListTile(
                leading: const Icon(Icons.palette, color: Colors.deepPurple),
                title: const Text('Choose Color', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop({'type': 'color'}),
              ),
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
      
      if (result == null) return;
      
      if (result['type'] == 'color') {
        _showColorPicker();
      } else {
        final source = result['type'] == 'gallery' ? ImageSource.gallery : ImageSource.camera;
        await _pickImageFromSource(source);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error opening picker. Try choosing a color instead.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Choose Color',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  _showColorPicker();
                }
              },
            ),
          ),
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
          _selectedColor = null; // Clear color if image is selected
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error selecting image. Try choosing a color instead.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Choose Color',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  _showColorPicker();
                }
              },
            ),
          ),
        );
      }
    }
  }
  
  void _showColorPicker() {
    if (!mounted) return;

    final colors = kPlaylistColors;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Choose Color', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _selectedColor = color;
                      _selectedImagePath = null; // Clear image if color is selected
                    });
                  }
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: _selectedColor == color
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                  ),
                  child: _selectedColor == color
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.useBottomSheetStyle) {
      return _buildBottomSheetContent(context);
    }

    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text(
        widget.titleText,
        style: const TextStyle(color: Colors.white),
      ),
      content: _buildFormContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop({
              'name': _nameController.text.trim(),
              'artworkPath': _selectedImagePath,
              'color': _selectedColor?.value,
            });
          },
          child: Text(widget.actionText, style: TextStyle(color: Colors.deepPurple.shade400)),
        ),
      ],
    );
  }

  Widget _buildFormContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.deepPurple.shade400,
                width: 2,
              ),
            ),
            child: _selectedImagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(_selectedImagePath!),
                      fit: BoxFit.cover,
                      width: 156,
                      height: 156,
                    ),
                  )
                : _selectedColor != null
                    ? Container(
                        width: 156,
                        height: 156,
                        decoration: BoxDecoration(
                          color: _selectedColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.queue_music,
                          color: Colors.white,
                          size: 64,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.image,
                            color: Colors.white70,
                            size: 40,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add Artwork',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Playlist Name',
            labelStyle: TextStyle(color: Colors.deepPurple.shade200),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurple.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSheetContent(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
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
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildFormContent(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade400,
                        foregroundColor: Colors.white,
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
