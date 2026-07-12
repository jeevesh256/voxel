import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import '../services/radio_playback_guard.dart';
import '../widgets/voxel_toast.dart';

class RadioMenuSheet extends StatelessWidget {
  final RadioStation radio;
  final Color accentColor;
  final AudioPlayerService audioService;
  /// When provided (Library context), shows "Remove from Library" instead of toggle.
  final VoidCallback? onRemove;

  const RadioMenuSheet({
    super.key,
    required this.radio,
    required this.accentColor,
    required this.audioService,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isFavourite = audioService
        .getPlaylistRadios('favourite_radios')
        .any((r) => r.id == radio.id);

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
              // Radio Header
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
                        child: _buildArtwork(context),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            radio.name,
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
                            radio.genre,
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
                    children: [
                      // Play Option
                      _buildOptionTile(
                        context,
                        icon: Icons.play_arrow_rounded,
                        title: 'Play Station',
                        // Teal/cyan for play
                        color: const Color(0xFF26C6DA),
                        onTap: () async {
                          final blockReason = await RadioPlaybackGuard.blockingMessage();
                          if (blockReason != null) {
                            final miniPlayerActive = audioService.isMiniPlayerVisible;
                            final bottomPad = MediaQuery.of(context).padding.bottom +
                                kBottomNavigationBarHeight +
                                (miniPlayerActive ? 70.0 : 0.0);
                            if (context.mounted) {
                              VoxelToast.show(
                                context,
                                blockReason,
                                bottomPadding: bottomPad,
                              );
                            }
                            return;
                          }
                          audioService.playRadioStation(radio);
                        },
                      ),
                      // Library action
                      if (onRemove != null)
                        // Library context: show "Remove from Library" in red
                        _buildOptionTile(
                          context,
                          icon: Icons.heart_broken_rounded,
                          title: 'Remove from Library',
                          color: const Color(0xFFEF5350),
                          onTap: onRemove!,
                        )
                      else
                        // All/Genre stations context: toggle add/remove
                        _buildOptionTile(
                          context,
                          icon: isFavourite ? Icons.favorite : Icons.favorite_border,
                          title: isFavourite ? 'Remove from Library' : 'Add to Library',
                          // Pink/rose for library
                          color: const Color(0xFFEC407A),
                          onTap: () {
                            if (isFavourite) {
                              audioService.removeRadioFromPlaylist('favourite_radios', radio);
                            } else {
                              audioService.addRadioToPlaylist('favourite_radios', radio);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackArt(BuildContext context) {
    return Container(
      color: accentColor.withOpacity(0.2),
      child: Center(
        child: Icon(
          Icons.radio_rounded,
          color: accentColor,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    if (radio.artworkUrl.isEmpty) {
      return _buildFallbackArt(context);
    }

    final uri = Uri.tryParse(radio.artworkUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImage(
        imageUrl: radio.artworkUrl,
        fit: BoxFit.cover,
        errorListener: (_) {},
        placeholder: (_, __) => _buildFallbackArt(context),
        errorWidget: (_, __, ___) => _buildFallbackArt(context),
      );
    }

    return _buildFallbackArt(context);
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      splashColor: color.withOpacity(0.1),
      highlightColor: color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
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
