import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class CreatePlaylistDialog extends StatefulWidget {
  const CreatePlaylistDialog({super.key});

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _selectedImagePath;
  Color? _selectedColor;

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
    if (!mounted) return; // Check if widget is still mounted
    
    final colors = [
      Colors.deepPurple,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
    ];
    
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
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text(
        'Create Playlist',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Playlist artwork selector
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 120,
              height: 120,
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
                        width: 116,
                        height: 116,
                      ),
                    )
                  : _selectedColor != null
                      ? Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            color: _selectedColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.queue_music,
                            color: Colors.white,
                            size: 48,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              color: Colors.deepPurple.shade400,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add Cover',
                              style: TextStyle(
                                color: Colors.deepPurple.shade400,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 20),
          // Playlist name input
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Playlist Name',
              labelStyle: TextStyle(color: Colors.grey[400]),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[600]!),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.deepPurple.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ),          TextButton(
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop({
                  'name': name,
                  'artworkPath': _selectedImagePath,
                  'color': _selectedColor?.value, // Store color as int
                });
              }
            },
          child: Text(
            'Create',
            style: TextStyle(color: Colors.deepPurple.shade400),
          ),
        ),
      ],
    );
  }
}
