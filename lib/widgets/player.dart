import 'dart:ui' show lerpDouble, ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:provider/provider.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:math';
import 'dart:io';
import 'dart:async';
import '../services/audio_service.dart';
import '../services/song_metadata_cache.dart';
import '../models/settings_model.dart';
import '../models/radio_station.dart';
import '../models/song.dart';
import '../widgets/edit_metadata_sheet.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/radio_menu_sheet.dart';
import 'queue.dart';
import 'bottom_chrome_metrics.dart';
import 'lyrics.dart';
import '../services/artwork_validator.dart';
import '../widgets/voxel_like_button.dart';
import '../widgets/voxel_play_pause_button.dart';
import 'player_theme_wrapper.dart';
import 'package:m3e_slider/m3e_slider.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class SlidingPlayer extends StatefulWidget {
  final AnimationController controller;
  final void Function(String? playlistId, bool isRadio, String? artistName)? onPlayingFromTap;

  const SlidingPlayer({
    super.key,
    required this.controller,
    this.onPlayingFromTap,
  });

  @override
  State<SlidingPlayer> createState() => _SlidingPlayerState();
}

class _SlidingPlayerState extends State<SlidingPlayer> {


  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.delta.dy;
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight > 0) {
      widget.controller.value -= delta / screenHeight;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) {
      widget.controller.animateTo(0.0, curve: Curves.easeOutCubic);
    } else if (velocity < -300) {
      widget.controller.animateTo(1.0, curve: Curves.easeOutCubic);
    } else if (widget.controller.value < 0.5) {
      widget.controller.animateTo(0.0, curve: Curves.easeOutCubic);
    } else {
      widget.controller.animateTo(1.0, curve: Curves.easeOutCubic);
    }
  }

  void _triggerHapticTap() {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
      HapticFeedback.lightImpact();
    }
  }

  void _triggerHapticPlayPause() {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
      HapticFeedback.mediumImpact();
    }
  }

  void _triggerHapticScrub() {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnSliderScrubbing) {
      HapticFeedback.selectionClick();
    }
  }

  void _triggerHapticLike() {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnLikes) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final topInset = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;
    final metrics = BottomChromeMetrics.of(context);
    final audioService = context.watch<AudioPlayerService>();

    return StreamBuilder<(PlayerState, MediaItem?)>(
      stream: Rx.combineLatest2(
        audioService.player.playerStateStream,
        audioService.currentMediaStream,
        (state, media) => (state, media),
      ).asBroadcastStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData ||
            snapshot.data?.$1.processingState == ProcessingState.idle ||
            snapshot.data?.$2 == null) {
          return const SizedBox.shrink();
        }

        final isRadio = audioService.isRadioPlaying;
        final radio = audioService.currentRadioStation;
        final isPlaying = snapshot.data?.$1.playing ?? false;
        final metadata = snapshot.data?.$2;

        final isLiked = !isRadio
            ? audioService.isLiked
            : isRadio &&
                radio != null &&
                audioService
                    .getPlaylistRadios('favourite_radios')
                    .any((r) => r.id == radio.id);

        final String? artPath = isRadio && radio != null
            ? (radio.artworkUrl.isNotEmpty && isValidArtwork(radio.artworkUrl)
                ? radio.artworkUrl
                : null)
            : metadata?.artUri?.scheme == 'file'
                ? metadata?.artUri?.toFilePath()
                : (metadata?.artUri != null && isValidArtwork(metadata!.artUri!.toString())
                    ? metadata!.artUri!.toString()
                    : null);

        // Retrieve fallback color from playlist custom artwork theme or pinned folder theme
        Color? playlistFallbackColor;
        if (!isRadio && metadata?.album != null) {
          final customPlaylist = audioService.getCustomPlaylist(metadata!.album!);
          if (customPlaylist?.artworkColor != null) {
            playlistFallbackColor = Color(customPlaylist!.artworkColor!);
          } else {
            // Check pinned folders from SettingsModel
            final settings = Provider.of<SettingsModel>(context, listen: false);
            final pinned = settings.pinnedFolders.firstWhere(
              (f) => f.name == metadata!.album || f.id == metadata!.album,
              orElse: () => PinnedNetworkFolder(id: '', name: '', type: '', serverId: '', serverName: '', path: ''),
            );
            if (pinned.artworkColor != null) {
              playlistFallbackColor = Color(pinned.artworkColor!);
            }
          }
        }

        return PlayerThemeWrapper(
          artPath: artPath,
          fallbackColor: playlistFallbackColor,
          builder: (context, dynamicScheme, extractedColor) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: dynamicScheme,
                primaryColor: extractedColor,
              ),
              child: Builder(
                builder: (context) {
                  return AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, child) {
                      final t = widget.controller.value;

            final collapsedColor = Colors.grey.shade900;

            // Container top rounded corners (0 to 32 depending on progress)
            final radius = BorderRadius.vertical(
              top: Radius.circular(t * 32.0),
            );

            // Artwork Position calculations
            final collapsedSize = metrics.miniPlayerArtworkSize;
            final expandedSize = screenWidth - 48.0;
            final currentSize = collapsedSize + (expandedSize - collapsedSize) * t;

            final collapsedLeft = metrics.miniPlayerHeight * 0.16;
            final collapsedTop = (metrics.miniPlayerHeight - collapsedSize) / 2;
            final expandedLeft = 24.0;
            final expandedTop = topInset + 80.0;

            final currentLeft = collapsedLeft + (expandedLeft - collapsedLeft) * t;
            final currentTop = collapsedTop + (expandedTop - collapsedTop) * t;

            // MiniPlayer content fades out as t goes to 1.0
            final miniPlayerOpacity = (1.0 - t * 4.0).clamp(0.0, 1.0);
            final showMiniPlayer = miniPlayerOpacity > 0.0;

            // FullScreen content fades in as t goes to 1.0
            final fullScreenOpacity = ((t - 0.4) * 1.67).clamp(0.0, 1.0);
            final showFullScreen = fullScreenOpacity > 0.0;

            return GestureDetector(
              onTap: t == 0.0
                  ? () => widget.controller.animateTo(1.0, curve: Curves.easeOutCubic)
                  : null,
              onVerticalDragUpdate: _handleDragUpdate,
              onVerticalDragEnd: _handleDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // FullScreen background gradient
                      Positioned.fill(
                        child: Opacity(
                          opacity: t,
                          child: RepaintBoundary(
                            child: DynamicBackground(
                              metadata: metadata,
                              fallbackColor: extractedColor,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),

                      // MiniPlayer controls & details
                      if (showMiniPlayer)
                        Positioned(
                          left: collapsedLeft + collapsedSize + (metrics.miniPlayerHeight * 0.16),
                          right: 0,
                          top: 0,
                          height: metrics.miniPlayerHeight,
                          child: Opacity(
                            opacity: miniPlayerOpacity,
                            child: RepaintBoundary(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            height: metrics.miniPlayerTitleHeight,
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 300),
                                              child: AutoScrollText(
                                                key: ValueKey(metadata?.id ?? 'no_title'),
                                                isRadio && radio != null
                                                    ? radio.name
                                                    : metadata?.title ?? 'No Track Playing',
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                velocity: 20.0,
                                                pauseAfterRound: const Duration(milliseconds: 1600),
                                                syncKey: isRadio && radio != null
                                                    ? 'radio-${radio.id}'
                                                    : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            height: metrics.miniPlayerArtistHeight,
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 300),
                                              child: Text(
                                                key: ValueKey(metadata?.id ?? 'no_artist'),
                                                isRadio && radio != null
                                                    ? (radio.genre)
                                                    : primaryArtist(metadata?.artist),
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  VoxelLikeButton(
                                    isLiked: isLiked,
                                    iconSize: 24.0,
                                    color: Colors.white,
                                    onPressed: () {
                                      _triggerHapticLike();
                                      if (isRadio && radio != null) {
                                        if (audioService
                                            .getPlaylistRadios('favourite_radios')
                                            .any((r) => r.id == radio.id)) {
                                          audioService.removeRadioFromPlaylist(
                                              'favourite_radios', radio);
                                        } else {
                                          audioService.addRadioToPlaylist(
                                              'favourite_radios', radio);
                                        }
                                      } else {
                                        audioService.toggleLike();
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                    color: Theme.of(context).colorScheme.onSurface,
                                    iconSize: 30,
                                    onPressed: () {
                                      _triggerHapticPlayPause();
                                      audioService.playPause();
                                    },
                                  ),
                                  SizedBox(width: metrics.miniPlayerHeight * 0.16),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // FullScreen Header
                      if (showFullScreen)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Opacity(
                            opacity: fullScreenOpacity,
                            child: RepaintBoundary(
                              child: _buildHeader(context),
                            ),
                          ),
                        ),

                      // FullScreen Controls
                      if (showFullScreen)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: bottomInset + 16.0,
                          top: expandedTop + expandedSize + 8.0,
                          child: Opacity(
                            opacity: fullScreenOpacity,
                            child: RepaintBoundary(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: (screenHeight - (expandedTop + expandedSize + 8.0) - (bottomInset + 16.0)).clamp(0.0, double.infinity),
                                  ),
                                  child: Center(
                                    child: _buildControls(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Artwork — wrapped in pressable spring widget when fully expanded
                      Positioned(
                        left: currentLeft,
                        top: currentTop,
                        width: currentSize,
                        height: currentSize,
                        child: _PressableArtwork(
                          enabled: t > 0.85,
                          borderRadius: t * 15.0 + 5.0,
                          cardColor: const Color(0xFF121212),
                          boxShadow: t > 0.05
                              ? BoxShadow(
                                  color: Colors.black.withOpacity(0.35 * t),
                                  blurRadius: 15.0 * t,
                                  offset: Offset(0, 10.0 * t),
                                )
                              : null,
                          child: RepaintBoundary(
                            child: _buildArtworkWidget(
                              context,
                              isRadio: isRadio,
                              radio: radio,
                              metadata: metadata,
                            ),
                          ),
                        ),
                      ),

                      // MiniPlayer progress bar
                      if (showMiniPlayer)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3,
                          child: Opacity(
                            opacity: miniPlayerOpacity,
                            child: _buildMiniProgressBar(context, audioService, Theme.of(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
  },
);
},
);
}

  Widget _buildArtworkWidget(
    BuildContext context, {
      required bool isRadio,
      required RadioStation? radio,
      required MediaItem? metadata,
  }) {
    Widget getFallbackIcon(bool isRadioItem) {
      final scheme = Theme.of(context).colorScheme;
      
      // If playing a song in a custom playlist or pinned folder, use its custom color theme
      Color? playlistColor;
      if (!isRadioItem && metadata?.album != null) {
        final audioService = Provider.of<AudioPlayerService>(context, listen: false);
        final customPlaylist = audioService.getCustomPlaylist(metadata!.album!);
        if (customPlaylist?.artworkColor != null) {
          playlistColor = Color(customPlaylist!.artworkColor!);
        } else {
          // Check pinned folders from SettingsModel
          final settings = Provider.of<SettingsModel>(context, listen: false);
          final pinned = settings.pinnedFolders.firstWhere(
            (f) => f.name == metadata!.album || f.id == metadata!.album,
            orElse: () => PinnedNetworkFolder(id: '', name: '', type: '', serverId: '', serverName: '', path: ''),
          );
          if (pinned.artworkColor != null) {
            playlistColor = Color(pinned.artworkColor!);
          }
        }
      }

      if (playlistColor != null) {
        return Container(
          color: playlistColor.withOpacity(0.12),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              size: 80,
              color: playlistColor,
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              scheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Icon(
                isRadioItem ? Icons.radio_rounded : Icons.music_note_rounded,
                size: 80,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      );
    }

    final String keyStr = isRadio ? (radio?.id ?? '') : (metadata?.id ?? '');
    Widget artwork;

    if (isRadio && radio != null && radio.artworkUrl.isNotEmpty && isValidArtwork(radio.artworkUrl)) {
      artwork = Image.network(
        radio.artworkUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => getFallbackIcon(true),
      );
    } else if (metadata?.artUri != null) {
      final artUrlStr = metadata!.artUri!.toString();
      if (metadata.artUri!.scheme == 'file') {
        artwork = Image.file(
          File(metadata.artUri!.toFilePath()),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => getFallbackIcon(false),
        );
      } else if (isValidArtwork(artUrlStr)) {
        artwork = Image.network(
          artUrlStr,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => getFallbackIcon(false),
        );
      } else {
        artwork = getFallbackIcon(isRadio);
      }
    } else {
      artwork = getFallbackIcon(isRadio);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: SizedBox.expand(
        key: ValueKey(keyStr.isEmpty ? 'placeholder' : keyStr),
        child: artwork,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final playlistName = audioService.currentPlaylistName;
    final isRadio = audioService.isRadioPlaying;
    final topInset = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(top: topInset + 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    iconSize: 36,
                    color: Colors.white.withOpacity(0.9),
                    onPressed: () {
                      widget.controller.animateTo(0.0, curve: Curves.easeOutCubic);
                    },
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      widget.onPlayingFromTap?.call(
                        audioService.currentPlaylistId,
                        isRadio,
                        audioService.currentArtistName,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isRadio ? 'Tuned into' : 'Playing from',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            isRadio ? 'Radio' : (playlistName ?? 'Library'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 56),
            ],
          ),
        ),
        Positioned(
          top: topInset + 4.0,
          right: -8,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: const Icon(Icons.more_vert),
              iconSize: 32,
              color: Colors.white.withOpacity(0.9),
              onPressed: () => _showCurrentSongMenu(context),
            ),
          ),
        ),
      ],
    );
  }

  Song? _songForCurrentTrack(AudioPlayerService audioService) {
    if (audioService.isRadioPlaying) return null;

    final currentTrack = audioService.currentTrack;
    if (currentTrack == null) return null;

    final artUri = currentTrack.artUri;
    final albumArt = artUri == null
        ? ''
        : artUri.scheme == 'file'
            ? artUri.toFilePath()
            : artUri.toString();

    return Song(
      id: currentTrack.id,
      filePath: currentTrack.id,
      title: currentTrack.title,
      artist: currentTrack.artist ?? 'Unknown Artist',
      album: currentTrack.album ?? '',
      albumArt: albumArt,
      duration: currentTrack.duration ?? Duration.zero,
    );
  }

  void _showCurrentSongMenu(BuildContext context) {
    final audioService = context.read<AudioPlayerService>();
    final accentColor = Theme.of(context).colorScheme.primary;

    if (audioService.isRadioPlaying) {
      final radio = audioService.currentRadioStation;
      if (radio == null) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (ctx) => Theme(
          data: Theme.of(context),
          child: RadioMenuSheet(
            radio: radio,
            accentColor: accentColor,
            audioService: audioService,
          ),
        ),
      );
      return;
    }

    final song = _songForCurrentTrack(audioService);
    if (song == null || song.filePath.isEmpty) {
      return;
    }

    final secondaryColor = Theme.of(context).colorScheme.secondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => Theme(
        data: Theme.of(context),
        child: SongMenuSheet(
          song: song,
          accentColor: accentColor,
          options: [
            SongMenuOption(
              icon: audioService.isFileLiked(song.filePath)
                  ? Icons.favorite
                  : Icons.favorite_border,
              title: audioService.isFileLiked(song.filePath)
                  ? 'Remove from Liked Songs'
                  : 'Add to Liked Songs',
              color: secondaryColor,
              onTap: () {
                audioService.toggleLikeFile(song.filePath);
              },
            ),
            SongMenuOption(
              icon: Icons.playlist_add_rounded,
              title: 'Add to queue',
              color: Colors.tealAccent.shade400,
              onTap: () {
                final insertIndex = (audioService.player.currentIndex ?? 0) + 1;
                audioService.insertAtQueue(song, insertIndex);
              },
            ),
            SongMenuOption(
              icon: Icons.edit_note_rounded,
              title: 'Edit metadata',
              color: Colors.orange.shade400,
              onTap: () async {
                final result = await EditMetadataSheet.show(
                  context,
                  song,
                  File(song.filePath),
                  accentColor,
                );
                if (result != null) {
                  final editedSong = song.copyWith(
                    title: result['title'] as String,
                    artist: result['artist'] as String,
                    album: result['album'] as String,
                    albumArt: result['albumArt'] as String,
                  );
                  final cache = SongMetadataCache();
                  await cache.saveMetadata(editedSong);
                  await audioService.refreshCurrentMetadata();
                  return editedSong;
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;
    final radio = audioService.currentRadioStation;
    final metrics = BottomChromeMetrics.of(context);
    
    final isLiked = !isRadio
        ? audioService.isLiked
        : isRadio &&
            radio != null &&
            audioService
                .getPlaylistRadios('favourite_radios')
                .any((r) => r.id == radio.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<MediaItem?>(
            stream: audioService.currentMediaStream,
            builder: (context, snapshot) {
              final metadata = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: metrics.fullScreenTitleHeight,
                          child: AutoScrollText(
                            isRadio && radio != null
                                ? (metadata?.title ?? radio.name)
                                : metadata?.title ?? 'No Track Playing',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            velocity: 30,
                            pauseAfterRound: const Duration(milliseconds: 2000),
                            syncKey: isRadio && radio != null
                                ? 'radio-${radio.id}'
                                : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      VoxelLikeButton(
                        isLiked: isLiked,
                        iconSize: 28.0,
                        color: Colors.white.withOpacity(0.8),
                        onPressed: () {
                          _triggerHapticLike();
                          if (isRadio && radio != null) {
                            if (audioService
                                .getPlaylistRadios('favourite_radios')
                                .any((r) => r.id == radio.id)) {
                              audioService.removeRadioFromPlaylist(
                                  'favourite_radios', radio);
                            } else {
                              audioService.addRadioToPlaylist(
                                  'favourite_radios', radio);
                            }
                          } else {
                            audioService.toggleLike();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: metrics.fullScreenArtistHeight,
                    child: AutoScrollText(
                      isRadio && radio != null
                          ? (metadata?.artist ?? radio.genre)
                          : metadata?.artist ?? 'Unknown Artist',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 16,
                      ),
                      velocity: 30,
                      pauseAfterRound: const Duration(milliseconds: 2000),
                      syncKey: isRadio && radio != null
                          ? 'radio-${radio.id}'
                          : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const _PlayerProgressBar(),
          const SizedBox(height: 20),
          const _PlayerPlaybackControls(),
        ],
      ),
    );
  }

  Widget _buildMiniProgressBar(
      BuildContext context, AudioPlayerService audioService, ThemeData globalTheme) {
    return StreamBuilder<(Duration, Duration?)>(
      stream: Rx.combineLatest2(
        audioService.player.positionStream,
        audioService.player.durationStream,
        (position, duration) => (position, duration),
      ).asBroadcastStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 3);

        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2 ?? Duration.zero;
        final isRadio = audioService.isRadioPlaying;

        if (isRadio) return const SizedBox.shrink();

        final double value = (duration == Duration.zero)
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3.0)),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: globalTheme.colorScheme.primary.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(globalTheme.colorScheme.primary),
            minHeight: 3.0,
          ),
        );
      },
    );
  }
}

class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackWidth = parentBox.size.width;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;

    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

/// A small helper widget that auto-scrolls (marquee) the given [text]
/// when it doesn't fit into the available horizontal space.
///
/// - Uses a duplicated text row and translates it left to create a smooth loop.
/// - Honors [MediaQuery.disableAnimations] and will show an ellipsized text when
///   animations are disabled or when the text fits.
// Return the primary artist from the given artist string. Splits on common
// separators like commas or 'feat' markers and returns the first part.
String primaryArtist(String? artist) {
  if (artist == null || artist.trim().isEmpty) return 'Unknown Artist';
  // Split on commas, ampersands, and 'feat' patterns (case-insensitive)
  final parts =
      artist.split(RegExp(r',| & | feat\.? | ft\.? ', caseSensitive: false));
  return parts.first.trim();
}

/// Public helper to request resetting auto-scroll for a given `syncKey`.
/// This bumps the internal sync start and causes any `AutoScrollText`
/// instances sharing that `syncKey` to restart from the initial position.
void resetAutoScrollForKey(String key) =>
    _SyncRegistry.bumpStart(key, DateTime.now());

class AutoScrollText extends StatefulWidget {
  /// Auto-scrolling text that mimics Spotify's marquee behaviour.
  ///
  /// - `velocity` is pixels/second for the forward scroll.
  /// - `pauseAfterRound` is the duration to pause at the start/end of a round.
  /// - `syncKey` lets multiple `AutoScrollText` instances synchronize their
  ///   cycle starts (useful for title + artist pairs). If null no syncing is used.
  /// - `enableInitialDelay` adds a small extra delay before this instance
  ///   starts its first round (useful for starting artist slightly after title).
  const AutoScrollText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 20.0, // pixels per second
    this.pauseAfterRound = const Duration(milliseconds: 1200),
    this.syncKey,
    this.enableInitialDelay = false,
    this.gap = 48.0,
  });

  final String text;
  final TextStyle? style;
  final double velocity;
  final Duration pauseAfterRound;
  final String? syncKey;
  final bool enableInitialDelay;

  /// Gap between repeated text copies in pixels (controls spacing between cycles).
  final double gap;

  @override
  State<AutoScrollText> createState() => _SpotifyMarqueeState();
}

class _SpotifyMarqueeState extends State<AutoScrollText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _textWidth = 0.0;
  double _containerWidth = 0.0;
  bool _shouldScroll = false;
  bool _isDisposed = false;
  bool _running = false;
  // When true the next start should begin from the initial position (0.0)
  bool _needReset = false;
  // Track the last seen sync generation so external bumps can reset us.
  int _seenSyncGen = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() {
        // controller.value is 0..1; we apply it to offset when active
        if (_shouldScroll) setState(() {});
      });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  // no-op: animation is handled via [_controller] listener
  Future<void> _startMarquee() async {
    if (!_shouldScroll || _isDisposed) return;

    // continuous leftward loop with a small gap so text doesn't butt up against itself
    final double gap = widget.gap;
    final loopDistance = _textWidth + gap;
    final loopMs =
        (loopDistance / (widget.velocity <= 0 ? 1.0 : widget.velocity) * 1000)
            .round();
    if (loopMs <= 0) return;

    _running = true;

    _controller.duration = Duration(milliseconds: loopMs);

    if (_needReset) {
      // Force starting from the initial position
      if (widget.syncKey != null)
        _SyncRegistry.setStart(widget.syncKey!, DateTime.now());
      _controller.value = 0.0;
      _needReset = false;
    } else if (widget.syncKey != null) {
      // Align to a shared start time so synced items (title+artist) scroll in-phase
      final start =
          _SyncRegistry.getOrCreateStart(widget.syncKey!, DateTime.now());
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final initialValue =
          ((elapsed % loopMs) / loopMs).clamp(0.0, 1.0).toDouble();
      _controller.value = initialValue;
    } else {
      _controller.value = 0.0;
    }

    // start continuous repeating animation
    _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the text or sync key changed, ensure we start from the initial pos
    if (oldWidget.text != widget.text || oldWidget.syncKey != widget.syncKey) {
      _needReset = true;
      if (_running && !_isDisposed) {
        // restart animation from initial position immediately
        _controller.stop();
        _controller.value = 0.0;
        _controller.repeat();
        _needReset = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final TextStyle textStyle = DefaultTextStyle.of(context).style.merge(widget.style);
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final textWidth = tp.width;
        final textHeight = tp.height;
        final shouldScrollNow = textWidth > maxWidth - 1.0;

        // Always check for external sync bumps so we can reset even if sizes
        // did not change (important when opening/closing the full screen player).
        if (widget.syncKey != null) {
          final gen = _SyncRegistry.generation(widget.syncKey!);
          if (gen != _seenSyncGen) {
            _seenSyncGen = gen;
            // Schedule reset after build to avoid calling setState during build.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _isDisposed) return;
              if (_running) {
                _controller.stop();
                _controller.value = 0.0;
                _controller.repeat();
              } else {
                _needReset = true;
              }
            });
          }
        }

        if (textWidth != _textWidth ||
            maxWidth != _containerWidth ||
            shouldScrollNow != _shouldScroll) {
          final wasRunning = _running;
          final oldTextWidth = _textWidth;
          _textWidth = textWidth;
          _containerWidth = maxWidth;
          _shouldScroll = shouldScrollNow;

          if (_shouldScroll && !wasRunning) {
            // start marquee in a microtask so layout completes
            Future.microtask(() => _startMarquee());
          } else if (_shouldScroll && wasRunning) {
            // update running animation to match new text width while preserving phase
            final double gap = widget.gap;
            final oldLoop = oldTextWidth + gap;
            final newLoop = _textWidth + gap;
            if (oldLoop > 0 && newLoop > 0) {
              final fraction = _controller.value;
              final newLoopMs = (newLoop /
                      (widget.velocity <= 0 ? 1.0 : widget.velocity) *
                      1000)
                  .round();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _isDisposed) return;
                _controller.duration = Duration(milliseconds: max(1, newLoopMs));
                _controller.value = fraction.clamp(0.0, 1.0);
                _controller.repeat();
              });
              // Check for external bump to the sync start time and reset if seen
              if (widget.syncKey != null) {
                final gen = _SyncRegistry.generation(widget.syncKey!);
                if (gen != _seenSyncGen) {
                  _seenSyncGen = gen;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _isDisposed) return;
                    _controller.stop();
                    _controller.value = 0.0;
                    _controller.repeat();
                  });
                }
              }
            }
          } else if (!_shouldScroll && wasRunning) {
            // stop running animation if it's no longer needed
            _controller.stop();
            _running = false;
          }
        }
        if (!_shouldScroll || media.disableAnimations) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }
        // Add a soft fade at the left/right edges to mask wrapping and make
        // continuous motion feel more natural.
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: const [0.0, 0.06, 0.94, 1.0],
          ).createShader(Rect.fromLTWH(0, 0, _containerWidth, textHeight)),
          child: ClipRect(
            child: SizedBox(
              height: textHeight,
              width: _containerWidth,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Continuous loop: draw two copies with a small gap and translate
                  // them left by controller.value * loopDistance so the motion loops.
                  Builder(builder: (context) {
                    final double gap = widget.gap;
                    final loopDistance = _textWidth + gap;
                    final left = -(_controller.value * loopDistance);

                    // Calculate how many copies we need to ensure the visible
                    // area is always covered (defensive against edge cases where
                    // loopDistance < containerWidth).
                    final minCopies =
                        ((_containerWidth / loopDistance).ceil() + 2)
                            .clamp(2, 8);

                    return Stack(
                      children: List.generate(minCopies, (i) {
                        return Positioned(
                          left: left + i * loopDistance,
                          top: 0,
                          child: SizedBox(
                            width: _textWidth,
                            child: Text(
                              widget.text,
                              style: widget.style,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Registry to coordinate synchronized starts for groups of [AutoScrollText]
/// instances that share a `syncKey`.
class _SyncRegistry {
  static final Map<String, DateTime> _starts = {};
  static final Map<String, int> _gens = {};

  /// Returns the existing start time for [key], or sets it to [proposedStart]
  /// if not present and returns that.
  static DateTime getOrCreateStart(String key, DateTime proposedStart) {
    return _starts.putIfAbsent(key, () => proposedStart);
  }

  /// Set or overwrite the start time for [key].
  static void setStart(String key, DateTime start) => _starts[key] = start;

  /// Increment generation for [key] and set start time; used to notify
  /// listeners that a reset was requested.
  static void bumpStart(String key, DateTime start) {
    _starts[key] = start;
    _gens[key] = (_gens[key] ?? 0) + 1;
  }

  /// Return current generation for a given key (0 if none).
  static int generation(String key) => _gens[key] ?? 0;
}

class DynamicBackground extends StatelessWidget {
  final MediaItem? metadata;
  final Color fallbackColor;
  final Widget child;

  const DynamicBackground({
    super.key,
    required this.metadata,
    required this.fallbackColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = fallbackColor;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor.withOpacity(0.85),
            scheme.surfaceContainerLow.withOpacity(0.95),
            scheme.surface,
          ],
        ),
      ),
      child: child,
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  final Color accentColor;
  const _LivePulseDot({required this.accentColor});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8 + (3 * _controller.value),
          height: 8 + (3 * _controller.value),
          decoration: BoxDecoration(
            color: widget.accentColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withOpacity(0.6 * (1.0 - _controller.value)),
                blurRadius: 6,
                spreadRadius: 3 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LivePlayingLine extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  final bool reverse;

  const _LivePlayingLine({
    required this.color,
    required this.isPlaying,
    this.reverse = false,
  });

  @override
  State<_LivePlayingLine> createState() => _LivePlayingLineState();
}

class _LivePlayingLineState extends State<_LivePlayingLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _LivePlayingLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 12),
          painter: _WavePainter(
            color: widget.color,
            progress: _controller.value,
            reverse: widget.reverse,
            isPlaying: widget.isPlaying,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool reverse;
  final bool isPlaying;

  _WavePainter({
    required this.color,
    required this.progress,
    required this.reverse,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height / 2;
    const double barHeight = 12.0;

    final Rect rect = Rect.fromLTWH(0, midY - (barHeight / 2), size.width, barHeight);

    // Fade out as the bars approach the central LIVE text
    final shader = LinearGradient(
      colors: reverse
          ? [color.withOpacity(0.0), color]
          : [color, color.withOpacity(0.0)],
    ).createShader(rect);

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;

    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(barHeight / 2),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isPlaying != isPlaying;
  }
}

class _M3TrackHeadThumbShape extends SliderComponentShape {
  const _M3TrackHeadThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isInteractive) {
    return const Size(12.0, 34.0);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;

    // Beautiful vertical pill shape from Material 3
    final double t = activationAnimation.value;
    const double width = 6.0;
    final double height = 24.0 + (34.0 - 24.0) * t;
    const double radius = 3.0;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      const Radius.circular(radius),
    );
    canvas.drawRRect(rrect, paint);
  }
}

class _M3ExpressiveSliderTrackShape extends SliderTrackShape {
  final double dragFactor;
  const _M3ExpressiveSliderTrackShape({required this.dragFactor});

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 12.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? startThumbCenter,
    Offset? endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    Offset? secondaryOffset,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.blue
      ..style = PaintingStyle.fill;

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final double trackHeight = sliderTheme.trackHeight!;
    final double radius = trackHeight / 2;

    // Track gap interpolates from 3.0px (resting) to 6.0px (dragging)
    final double currentGap = 3.0 + (6.0 - 3.0) * dragFactor;
    const double thumbWidth = 4.0;

    // Draw active track
    final double activeRight = thumbCenter.dx - (thumbWidth / 2) - currentGap;

    if (activeRight > trackRect.left) {
      final Rect activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        activeRight,
        trackRect.bottom,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          activeRect,
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          topRight: const Radius.circular(2.0),
          bottomRight: const Radius.circular(2.0),
        ),
        activePaint,
      );
    }

    // Draw inactive track
    final double inactiveStart = thumbCenter.dx + (thumbWidth / 2) + currentGap;
    final double inactiveEnd = trackRect.right;

    if (inactiveStart < inactiveEnd) {
      final Rect inactiveRect = Rect.fromLTRB(
        inactiveStart,
        trackRect.top,
        inactiveEnd,
        trackRect.bottom,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          inactiveRect,
          topLeft: const Radius.circular(2.0),
          bottomLeft: const Radius.circular(2.0),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        ),
        inactivePaint,
      );
    }
  }
}


// ── Pressable Artwork ──────────────────────────────────────────────────────
//
// Pixel-lockscreen-style press interaction: gentle scale-down on tap,
// single-overshoot spring snap-back on release.
//
class _PressableArtwork extends StatefulWidget {
  const _PressableArtwork({
    required this.child,
    required this.borderRadius,
    required this.cardColor,
    this.boxShadow,
    this.enabled = true,
  });

  final Widget child;
  final double borderRadius;
  final BoxShadow? boxShadow;
  final Color cardColor;

  /// Only respond to touches when the player is fully open.
  final bool enabled;

  @override
  State<_PressableArtwork> createState() => _PressableArtworkState();
}

class _PressableArtworkState extends State<_PressableArtwork>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    lowerBound: -0.15,
    upperBound: 1.15,
    value: 0.0,
  );

  late final AnimationController _rotationCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );

  Timer? _longPressTimer;
  bool _isLockedMorphed = false;
  Offset? _startOffset;

  double get _scale => lerpDouble(1.0, 0.96, _ctrl.value.clamp(0.0, 1.0))!;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _startOffset = event.position;
    _longPressTimer?.cancel();
    
    if (_isLockedMorphed) {
      // If already morphed, a tap will unlock and reset it
      _isLockedMorphed = false;
      _handleRelease();
      return;
    }
    
    // Scale down first smoothly (0.0 -> 0.15 progress)
    _ctrl.animateTo(
      0.15,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );

    _longPressTimer = Timer(const Duration(milliseconds: 250), () {
      _isLockedMorphed = true;
      final settings = context.read<SettingsModel>();
      if (settings.hapticsEnabled && settings.hapticsOnLongPress) {
        HapticFeedback.lightImpact();
      }
      // Silky-smooth spring morph transition
      const desc = SpringDescription(mass: 1.0, stiffness: 150.0, damping: 20.0);
      _ctrl.animateWith(SpringSimulation(desc, _ctrl.value, 1.0, 0.0));
      _rotationCtrl.repeat();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_startOffset == null) return;
    final difference = (event.position - _startOffset!).distance;
    if (difference > 12.0) { // If they moved their finger > 12 pixels, cancel the long press
      _longPressTimer?.cancel();
      if (!_isLockedMorphed) {
        _handleRelease();
      }
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    _startOffset = null;
    // Only release if we didn't complete the long press to lock the morph
    if (!_isLockedMorphed) {
      _handleRelease();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _startOffset = null;
    if (!_isLockedMorphed) {
      _handleRelease();
    }
  }

  void _handleRelease() {
    _longPressTimer?.cancel();
    _rotationCtrl.stop();
    _rotationCtrl.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    
    // Silky-smooth spring release transition
    const desc = SpringDescription(mass: 1.0, stiffness: 180.0, damping: 22.0);
    _ctrl.animateWith(SpringSimulation(desc, _ctrl.value, 0.0, 0.0));
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _ctrl.dispose();
    _rotationCtrl.dispose();
    super.dispose();
  }

  // Pre-calculate path points once per frame using polar superellipse (squircle) math
  Path _generateMorphedPath(Size size, double progress, double rotationAngle) {
    if (progress == 0.0 && rotationAngle == 0.0) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(widget.borderRadius),
        ));
    }

    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double maxR = min(w, h) / 2;
    
    // Cookie shape parameters
    final double amp = maxR * 0.065; 
    final double avgR = maxR - amp; 

    final Path path = Path();
    const int totalPoints = 180; // Perfectly uniform sample density

    for (int i = 0; i < totalPoints; i++) {
      final double phi = (i * 2.0 * pi) / totalPoints;
      final double cosPhi = cos(phi);
      final double sinPhi = sin(phi);

      // Squircle (Superellipse) radius: r = 1 / (|cos(phi)/a|^n + |sin(phi)/b|^n)^(1/n)
      // n = 16.0 renders a standard rounded square with subtle corners (matching 20px border radius)
      final double termX = pow((cosPhi / (w / 2)).abs(), 16.0).toDouble();
      final double termY = pow((sinPhi / (h / 2)).abs(), 16.0).toDouble();
      final double rSquircle = 1.0 / pow(termX + termY, 1.0 / 16.0);

      // Cookie radius (7 lobes, rotated dynamically)
      final double rCookie = avgR + amp * cos(7 * (phi - rotationAngle));
      
      // Lerp the radius at the exact same angle to guarantee perfect symmetry and zero distortion
      final double r = lerpDouble(rSquircle, rCookie, progress)!;
      
      final double x = cx + r * cosPhi;
      final double y = cy + r * sinPhi;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? _onPointerDown : null,
      onPointerMove: widget.enabled ? _onPointerMove : null,
      onPointerUp: widget.enabled ? _onPointerUp : null,
      onPointerCancel: widget.enabled ? _onPointerCancel : null,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_ctrl, _rotationCtrl]),
          builder: (context, child) {
            final double progress = _ctrl.value.clamp(0.0, 1.0);
            final double rotationAngle = _rotationCtrl.value * 2.0 * pi;
            
            return LayoutBuilder(
              builder: (context, constraints) {
                final Size size = Size(constraints.maxWidth, constraints.maxHeight);
                final Path morphedPath = _generateMorphedPath(size, progress, rotationAngle);
                
                return Transform.scale(
                  scale: _scale,
                  child: CustomPaint(
                    painter: widget.boxShadow != null
                        ? _SharedPathShadowPainter(
                            path: morphedPath,
                            shadow: widget.boxShadow!,
                          )
                        : null,
                    child: ClipPath(
                      clipper: _SharedPathClipper(path: morphedPath),
                      clipBehavior: Clip.antiAliasWithSaveLayer,
                      child: Container(
                        color: const Color(0xFF121212),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (progress > 0.0)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      colors: [
                                        Theme.of(context).primaryColor.withOpacity(0.4 * progress),
                                        Colors.transparent,
                                      ],
                                      radius: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            child!,
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _SharedPathShadowPainter extends CustomPainter {
  final Path path;
  final BoxShadow shadow;

  _SharedPathShadowPainter({required this.path, required this.shadow});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = shadow.color
      ..isAntiAlias = true
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurRadius);
    
    canvas.save();
    canvas.translate(shadow.offset.dx, shadow.offset.dy);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SharedPathShadowPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.shadow != shadow;
  }
}

class _SharedPathClipper extends CustomClipper<Path> {
  final Path path;

  _SharedPathClipper({required this.path});

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _SharedPathClipper oldClipper) {
    return oldClipper.path != path;
  }
}

class _PlayerProgressBar extends StatefulWidget {
  const _PlayerProgressBar();

  @override
  State<_PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<_PlayerProgressBar> {
  double? _dragValue;
  DateTime? _lastSeekTime;

  void _triggerHapticScrub() {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnSliderScrubbing) {
      HapticFeedback.selectionClick();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;

    return StreamBuilder<(Duration, Duration)>(
      stream: Rx.combineLatest2(
        audioService.player.positionStream,
        audioService.stableDurationStream,
        (position, duration) => (position, duration),
      ).asBroadcastStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 48);

        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2;

        if (isRadio || duration == Duration.zero) {
          final theme = Theme.of(context);
          final trackColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
          final isPlaying = audioService.player.playing;
          return Container(
            height: 48,
            alignment: Alignment.center,
            child: Row(
              children: [
                Expanded(
                  child: _LivePlayingLine(
                    color: trackColor,
                    isPlaying: isPlaying,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: _LivePlayingLine(
                    color: trackColor,
                    isPlaying: isPlaying,
                    reverse: true,
                  ),
                ),
              ],
            ),
          );
        }

        final double value = min<double>(
          (_dragValue ?? position.inMilliseconds.toDouble()),
          duration.inMilliseconds.toDouble(),
        );

        final percent = duration.inMilliseconds > 0 ? value / duration.inMilliseconds : 0.0;
        final isPlaying = audioService.player.playing;

        return Column(
          children: [
            M3ESlider(
              value: value.clamp(0.0, duration.inMilliseconds.toDouble()),
              min: 0.0,
              max: duration.inMilliseconds.toDouble(),
              onChanged: duration.inMilliseconds > 0
                  ? (val) {
                      final maxVal = duration.inMilliseconds.toDouble();
                      final threshold = (maxVal * 0.025).clamp(1000.0, 3000.0);
                      double adjustedVal = val;
                      if (val <= threshold) {
                        adjustedVal = 0.0;
                      } else if (maxVal - val <= threshold) {
                        adjustedVal = maxVal;
                      }

                      final prevVal = _dragValue ?? position.inMilliseconds.toDouble();
                      final step = (duration.inMilliseconds / 10).clamp(5000.0, 30000.0);
                      final prevStepIndex = (prevVal / step).floor();
                      final currentStepIndex = (adjustedVal / step).floor();
                      if (currentStepIndex != prevStepIndex) {
                        _triggerHapticScrub();
                      }
                      setState(() => _dragValue = adjustedVal);
                    }
                  : null,
              onChangeEnd: duration.inMilliseconds > 0
                  ? (value) {
                      final targetVal = _dragValue ?? value;
                      final maxVal = duration.inMilliseconds.toDouble();
                      final threshold = (maxVal * 0.025).clamp(1000.0, 3000.0);
                      double adjustedVal = targetVal;
                      if (targetVal <= threshold) {
                        adjustedVal = 0.0;
                      } else if (maxVal - targetVal <= threshold) {
                        adjustedVal = maxVal;
                      }

                      audioService.player.seek(Duration(milliseconds: adjustedVal.round()));
                      setState(() {
                        _dragValue = null;
                        _lastSeekTime = null;
                      });
                    }
                  : null,
              decoration: M3ESliderDecoration(
                trackHeight: 12.0,
                thumbWidth: 4.0,
                thumbHeight: 24.0,
                haptic: M3EHapticFeedback.light,
                colors: M3ESliderDefaults.colors(context).copyWith(
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  thumbColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PlayerPlaybackControls extends StatelessWidget {
  const _PlayerPlaybackControls();

  void _triggerHapticTap(BuildContext context) {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
      HapticFeedback.lightImpact();
    }
  }

  void _triggerHapticPlayPause(BuildContext context) {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final settings = context.watch<SettingsModel>();
    final isRadio = audioService.isRadioPlaying;

    return StreamBuilder<PlayerState>(
      stream: audioService.player.playerStateStream,
      initialData: audioService.player.playerState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? audioService.player.playing;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                VoxelPlayerControlButton(
                  isActive: !isRadio && audioService.isShuffling,
                  onPressed: isRadio
                      ? null
                      : () {
                          _triggerHapticTap(context);
                          audioService.toggleShuffle();
                        },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 4.0),
                    child: Icon(
                      Icons.shuffle,
                      color: isRadio
                          ? Colors.grey.shade600
                          : audioService.isShuffling
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                      size: 28,
                    ),
                  ),
                ),
                // Central grouped controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VoxelPlayerControlButton(
                      onPressed: isRadio
                          ? null
                          : () {
                              _triggerHapticTap(context);
                              audioService.player.seekToPrevious();
                            },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                        child: Icon(
                          Icons.skip_previous,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    VoxelPlayPauseButton(
                      isPlaying: playing,
                      isCookieEnabled: settings.cookiePlayPauseEnabled,
                      size: 72.0,
                      onPressed: () {
                        _triggerHapticPlayPause(context);
                        audioService.playPause();
                      },
                    ),
                    const SizedBox(width: 16),
                    VoxelPlayerControlButton(
                      onPressed: isRadio
                          ? null
                          : () {
                              _triggerHapticTap(context);
                              audioService.player.seekToNext();
                            },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                        child: Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ],
                ),
                VoxelPlayerControlButton(
                  isActive: !isRadio && audioService.loopMode != LoopMode.off,
                  onPressed: isRadio
                      ? null
                      : () {
                          _triggerHapticTap(context);
                          audioService.cycleRepeatMode();
                        },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 4.0),
                    child: Icon(
                      audioService.loopMode == LoopMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: isRadio
                          ? Colors.grey.shade600
                          : audioService.loopMode != LoopMode.off
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                VoxelActionButton(
                  icon: Icons.music_note,
                  label: 'Lyrics',
                  onPressed: () {
                    _triggerHapticTap(context);
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.black54,
                        barrierDismissible: true,
                        transitionDuration: const Duration(milliseconds: 300),
                        reverseTransitionDuration:
                            const Duration(milliseconds: 250),
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return const FullScreenLyricsView();
                        },
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            )),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                VoxelActionButton(
                  icon: Icons.queue_music,
                  label: 'Queue',
                  onPressed: () {
                    _triggerHapticTap(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useRootNavigator: true,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      builder: (ctx) => Theme(
                        data: Theme.of(context),
                        child: const DraggableQueueSheet(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
