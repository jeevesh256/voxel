import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';

class SongMenuOption {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const SongMenuOption({
    required this.icon,
    required this.title,
    required this.color,
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1F).withOpacity(0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
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
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildArtwork(),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: const TextStyle(
                              color: Colors.white,
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
                              color: Colors.white.withOpacity(0.7),
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
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackArt() {
    return Container(
      color: accentColor.withOpacity(0.2),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: accentColor,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildArtwork() {
    if (song.albumArt.isEmpty) {
      return _buildFallbackArt();
    }

    final uri = Uri.tryParse(song.albumArt);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImage(
        imageUrl: song.albumArt,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildFallbackArt(),
        errorWidget: (_, __, ___) => _buildFallbackArt(),
      );
    }

    final file = File(song.albumArt);
    if (!file.existsSync()) {
      return _buildFallbackArt();
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildFallbackArt(),
    );
  }

  Widget _buildOptionTile(BuildContext context, SongMenuOption option) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        option.onTap();
      },
      splashColor: option.color.withOpacity(0.1),
      highlightColor: option.color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: option.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(option.icon, color: option.color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                option.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
