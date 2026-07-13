import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';

class SongMenuOption {
  final IconData icon;
  final String title;
  final Color? color; // null = use onSurface (default action)
  final VoidCallback onTap;

  const SongMenuOption({
    required this.icon,
    required this.title,
    this.color,
    required this.onTap,
  });
}

class SongMenuSheet extends StatelessWidget {
  final Song song;
  final Color accentColor;
  final List<SongMenuOption> options;

  const SongMenuSheet({
    super.key,
    required this.song,
    required this.accentColor,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // M3-style drag handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 20),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Song Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildArtwork(scheme),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      song.artist,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 15,
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
        const SizedBox(height: 24),
        // Options List
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              children: options.map((option) => _buildOptionTile(context, option)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackArt(ColorScheme scheme) {
    return Container(
      color: scheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: scheme.onPrimaryContainer,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildArtwork(ColorScheme scheme) {
    if (song.albumArt.isEmpty) {
      return _buildFallbackArt(scheme);
    }

    final uri = Uri.tryParse(song.albumArt);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImage(
        imageUrl: song.albumArt,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildFallbackArt(scheme),
        errorWidget: (_, __, ___) => _buildFallbackArt(scheme),
      );
    }

    final file = File(song.albumArt);
    if (!file.existsSync()) {
      return _buildFallbackArt(scheme);
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildFallbackArt(scheme),
    );
  }

  Widget _buildOptionTile(BuildContext context, SongMenuOption option) {
    final scheme = Theme.of(context).colorScheme;
    final titleLower = option.title.toLowerCase();
    
    // Material 3 semantic colors:
    // Destructive/removals = scheme.error (red)
    // Favorites/likes = scheme.primary (brand color)
    // Standard actions = scheme.onSurfaceVariant (neutral grey/slate)
    Color itemColor;
    if (titleLower.contains('liked') || titleLower.contains('library')) {
      itemColor = scheme.primary;
    } else if (titleLower.contains('delete') || titleLower.contains('remove')) {
      itemColor = scheme.error;
    } else if (titleLower.contains('metadata') || titleLower.contains('edit')) {
      itemColor = const Color(0xFFC8E6C9); // Very subtle light green for editing
    } else {
      itemColor = scheme.onSurfaceVariant;
    }

    // Unify iconography: Map outline/variant icons to premium solid/rounded icons
    IconData displayIcon = option.icon;
    if (titleLower.contains('liked') || titleLower.contains('library')) {
      if (titleLower.contains('remove')) {
        displayIcon = Icons.favorite_rounded;
        itemColor = scheme.primary; // Keep theme primary color for liked toggle
      } else {
        displayIcon = Icons.favorite_border_rounded;
        itemColor = scheme.primary; // Keep theme primary color for liked toggle
      }
    } else if (titleLower.contains('playlist')) {
      if (titleLower.contains('add')) {
        displayIcon = Icons.playlist_add_rounded;
      } else if (titleLower.contains('remove') || titleLower.contains('delete')) {
        displayIcon = Icons.remove_circle_rounded;
      }
    } else if (titleLower.contains('queue')) {
      displayIcon = Icons.queue_music_rounded;
    } else if (titleLower.contains('metadata') || titleLower.contains('edit')) {
      displayIcon = Icons.edit_note_rounded;
    }

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        option.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(displayIcon, color: itemColor, size: 24),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                option.title,
                style: TextStyle(
                  color: itemColor == scheme.error ? scheme.error : scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
