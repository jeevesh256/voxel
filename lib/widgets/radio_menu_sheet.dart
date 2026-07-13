import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import '../services/radio_playback_guard.dart';
import '../widgets/voxel_toast.dart';

import '../services/artwork_validator.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final isFavourite = audioService
        .getPlaylistRadios('favourite_radios')
        .any((r) => r.id == radio.id);

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
                      color: scheme.shadow.withOpacity(0.25),
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
                      radio.genre,
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
              children: [
                // Play Option
                _buildOptionTile(
                  context,
                  icon: Icons.play_arrow_rounded,
                  title: 'Play Station',
                  color: scheme.primary,
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
                  _buildOptionTile(
                    context,
                    icon: Icons.favorite,
                    title: 'Remove from Library',
                    color: scheme.error,
                    onTap: onRemove!,
                  )
                else
                  _buildOptionTile(
                    context,
                    icon: isFavourite ? Icons.favorite : Icons.favorite_border,
                    title: isFavourite ? 'Remove from Library' : 'Add to Library',
                    color: isFavourite ? scheme.error : scheme.tertiary,
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
    );
  }

  Widget _buildFallbackArt(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.radio_rounded,
          color: scheme.onPrimaryContainer,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    if (radio.artworkUrl.isEmpty || !isValidArtwork(radio.artworkUrl)) {
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      splashColor: color.withOpacity(0.1),
      highlightColor: color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
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
