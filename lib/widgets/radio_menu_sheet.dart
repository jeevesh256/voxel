import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import '../services/radio_playback_guard.dart';
import '../widgets/voxel_toast.dart';
import '../services/artwork_validator.dart';
import 'squishy_action_button.dart';
import 'player_theme_wrapper.dart';


class RadioMenuSheet extends StatefulWidget {
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
  State<RadioMenuSheet> createState() => _RadioMenuSheetState();
}

class _RadioMenuSheetState extends State<RadioMenuSheet> {
  void _showToast(BuildContext context, String message) {
    VoxelToast.show(
      context,
      message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFavourite = widget.audioService
        .getPlaylistRadios('favourite_radios')
        .any((r) => r.id == widget.radio.id);

    return PlayerThemeWrapper(
      artPath: widget.radio.artworkUrl,
      fallbackColor: widget.accentColor,
      builder: (context, dynamicScheme, extractedColor) {
        return AnimatedTheme(
          data: Theme.of(context).copyWith(
            colorScheme: dynamicScheme,
            primaryColor: extractedColor,
          ),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          child: Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              // Blended legible container color based on the station artwork
              final backgroundColor = Color.lerp(extractedColor, scheme.surfaceContainerHigh, 0.85) ?? scheme.surfaceContainerHigh;

              return AnimatedContainer(
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
                  children: [
                    // Drag Handle
                    Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2.25),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Radio Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFF121212),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: _buildArtwork(context),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.radio.name,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.radio.genre,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant.withOpacity(0.7),
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
                    const SizedBox(height: 24),

                    // Options
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Builder(builder: (context) {
                        final builderScheme = Theme.of(context).colorScheme;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Row 1: Play Station + Like / Remove
                            ExpressiveButtonRow(
                              leftFlex: 3.0,
                              rightFlex: 1.0,
                              left: SquishyButtonParams(
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play Station'),
                                backgroundColor: builderScheme.primary,
                                foregroundColor: builderScheme.onPrimary,
                                onTap: () async {
                                  final blockReason =
                                      await RadioPlaybackGuard.blockingMessage();
                                  if (blockReason != null) {
                                    final miniPlayerActive =
                                        widget.audioService.isMiniPlayerVisible;
                                    final bottomPad =
                                        MediaQuery.of(context).padding.bottom +
                                            kBottomNavigationBarHeight +
                                            (miniPlayerActive ? 70.0 : 0.0);
                                    if (context.mounted) {
                                      VoxelToast.show(context, blockReason);
                                    }
                                    return;
                                  }
                                  _showToast(context, 'Playing station');
                                  widget.audioService.playRadioStation(widget.radio);
                                },
                              ),
                              right: SquishyButtonParams(
                                icon: Icon(isFavourite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded),
                                backgroundColor: builderScheme.surfaceContainerHighest,
                                foregroundColor: isFavourite ? builderScheme.primary : builderScheme.onSurface,
                                onTap: () {
                                  if (isFavourite) {
                                    _showToast(context, 'Removed from Library');
                                    if (widget.onRemove != null) {
                                      widget.onRemove!();
                                    } else {
                                      widget.audioService.removeRadioFromPlaylist(
                                          'favourite_radios', widget.radio);
                                    }
                                  } else {
                                    _showToast(context, 'Added to Library');
                                    widget.audioService.addRadioToPlaylist(
                                        'favourite_radios', widget.radio);
                                  }
                                  // Instantly reflect the new state
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Row 2: Hide Station (full width)
                            SquishyActionButton(
                              icon: const Icon(Icons.visibility_off_outlined),
                              label: const Text('Hide Station'),
                              backgroundColor: builderScheme.errorContainer,
                              foregroundColor: builderScheme.onErrorContainer,
                              onTap: () {
                                _showToast(context, 'Station hidden');
                                widget.audioService.hideRadioStation(widget.radio);
                              },
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
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
          size: 28,
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    if (widget.radio.artworkUrl.isEmpty || !isValidArtwork(widget.radio.artworkUrl)) {
      return _buildFallbackArt(context);
    }

    final uri = Uri.tryParse(widget.radio.artworkUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImage(
        imageUrl: widget.radio.artworkUrl,
        fit: BoxFit.cover,
        errorListener: (_) {},
        placeholder: (_, __) => _buildFallbackArt(context),
        errorWidget: (_, __, ___) => _buildFallbackArt(context),
      );
    }

    return _buildFallbackArt(context);
  }


}
