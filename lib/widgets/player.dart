import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';  // Add this import at the top with other imports
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:math';
import 'dart:io';
import 'dart:async';
import '../services/audio_service.dart';
import 'queue.dart';
import 'lyrics.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
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

        // Determine liked state for current item
        final isLiked = !isRadio
            ? audioService.isLiked
            : isRadio && radio != null && audioService.getPlaylistRadios('favourite_radios').any((r) => r.id == radio.id);

        return GestureDetector(
          onTap: () async {
            final syncKey = isRadio && radio != null
                ? 'radio-${radio.id}'
                : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}';
            // bump start so mini-player begins from initial position when opening
            resetAutoScrollForKey(syncKey);
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const FullScreenPlayer(),
            );
            // bump again on close so mini-player restarts from initial position
            resetAutoScrollForKey(syncKey);
          },
          child: Container(
            height: 60,
            color: Colors.grey.shade900,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: Colors.deepPurple.shade200,
                          image: isRadio && radio != null
                            ? DecorationImage(image: NetworkImage(radio.artworkUrl))
                            : metadata?.artUri != null 
                              ? DecorationImage(
                                  image: metadata!.artUri!.scheme == 'file'
                                    ? FileImage(File(metadata.artUri!.toFilePath()))
                                    : NetworkImage(metadata.artUri.toString()) as ImageProvider,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: (!isRadio && metadata?.artUri == null)
                          ? const Icon(Icons.music_note)
                          : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 18,
                                child: AutoScrollText(
                                  isRadio && radio != null
                                      ? radio.name
                                      : metadata?.title ?? 'No Track Playing',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  // Slower and slightly longer pause to feel smoother in the mini player
                                  velocity: 20,
                                  pauseAfterRound: const Duration(milliseconds: 1600),
                                  // Sync key so title and artist start together for the current item
                                  syncKey: isRadio && radio != null ? 'radio-${radio.id}' : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                                ),
                            ),
                            SizedBox(
                              height: 16,
                              child: Text(
                                isRadio && radio != null
                                    ? (radio.genre)
                                    : primaryArtist(metadata?.artist),
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? Colors.deepPurple.shade400 : Colors.white,
                        ),
                        onPressed: () {
                          if (isRadio && radio != null) {
                            // Only update favourite_radios for radios
                            if (audioService.getPlaylistRadios('favourite_radios').any((r) => r.id == radio.id)) {
                              audioService.removeRadioFromPlaylist('favourite_radios', radio);
                            } else {
                              audioService.addRadioToPlaylist('favourite_radios', radio);
                            }
                          } else {
                            // Only update liked songs for songs
                            audioService.toggleLike();
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        color: Colors.white,
                        onPressed: () => audioService.playPause(),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
                _buildMiniProgressBar(context, audioService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniProgressBar(BuildContext context, AudioPlayerService audioService) {
    return StreamBuilder<(Duration, Duration?)>(
      stream: Rx.combineLatest2(
        audioService.player.positionStream,
        audioService.player.durationStream,
        (position, duration) => (position, duration),
      ).asBroadcastStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 2);
        
        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2 ?? Duration.zero;
        final isRadio = audioService.isRadioPlaying;
        
        // For radio streams, show a filled progress bar to indicate live streaming
        if (isRadio || duration == Duration.zero) {
          return LinearProgressIndicator(
            value: 1.0, // Always full for radio streams
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade400),
            minHeight: 2,
          );
        }

        return LinearProgressIndicator(
          value: position.inMilliseconds / duration.inMilliseconds,
          backgroundColor: Colors.grey.shade800,
          valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade400),
          minHeight: 2,
        );
      },
    );
  }
}

class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _dismissController;
  static const double _dismissDistance = 160;
  static const double _velocityThreshold = 600;
  double _dragExtent = 0;
  double? _dragValue; // Scrubber drag value

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _dismissController,
        builder: (context, child) {
          final offset = MediaQuery.of(context).size.height * _dismissController.value;
          return Transform.translate(offset: Offset(0, offset), child: child);
        },
        child: _buildPlayerBody(context),
      ),
    );
  }

  Widget _buildPlayerBody(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.deepPurple.shade400,
            Colors.grey.shade900,
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAlbumArt(),
                  _buildControls(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragExtent = (_dragExtent + details.delta.dy).clamp(0, double.infinity);
    final fraction = (_dragExtent / _dismissDistance).clamp(0.0, 1.0);
    _dismissController.value = fraction;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss = velocity > _velocityThreshold || _dragExtent > _dismissDistance;
    if (shouldDismiss) {
      _dismissController
          .fling(velocity: max(1.5, velocity / 1000))
          .whenComplete(() {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      _dismissController.animateBack(0, curve: Curves.easeOutCubic);
    }
    _dragExtent = 0;
  }

  Widget _buildHeader(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final playlistName = audioService.currentPlaylistName;
    
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 46),
          child: Row(
            children: [
              SizedBox(
                width: 56, // Width for chevron button (48) + left padding (8)
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    iconSize: 36,
                    color: Colors.white.withOpacity(0.9),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              Expanded(
                child: Center(  // Added Center widget
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Playing from',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        playlistName ?? 'Library',
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
              const SizedBox(width: 56), // Match left side width for symmetry
            ],
          ),
        ),
        Positioned(
          top: 46,
          right: -8,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: const Icon(Icons.more_vert),
              iconSize: 32,
              color: Colors.white.withOpacity(0.9),
              onPressed: () {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumArt() {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;
    final radio = audioService.currentRadioStation;
    final padding = const EdgeInsets.symmetric(horizontal: 24);
    
    return StreamBuilder<MediaItem?>(
      stream: audioService.currentMediaStream,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        
        Widget artWidget;
        
        if (isRadio && radio != null && radio.artworkUrl.isNotEmpty) {
          // Radio station - use network image
          artWidget = AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Image.network(
              key: ValueKey(radio.artworkUrl),
              radio.artworkUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 80, color: Colors.white),
            ),
          );
        } else if (metadata?.artUri != null) {
          // Local song - check if file URI
          if (metadata!.artUri!.scheme == 'file') {
            artWidget = AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Image.file(
                key: ValueKey(metadata.artUri.toString()),
                File(metadata.artUri!.toFilePath()),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 80, color: Colors.white),
              ),
            );
          } else {
            // Network URI
            artWidget = AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Image.network(
                key: ValueKey(metadata.artUri.toString()),
                metadata.artUri.toString(),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 80, color: Colors.white),
              ),
            );
          }
        } else {
          artWidget = const Icon(Icons.music_note, size: 80, color: Colors.white);
        }
        
        return Padding(
          padding: padding,
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.deepPurple.shade200,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: artWidget,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSongInfo(context),
          const SizedBox(height: 20),
          _buildProgressBar(context),
          const SizedBox(height: 20),
          _buildPlaybackControls(context),
        ],
      ),
    );
  }

  String _formatTitle(String? title) {
    if (title == null) return 'No Track Playing';
    return title.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
  }

  Widget _buildSongInfo(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;
    final radio = audioService.currentRadioStation;
    
    return StreamBuilder<MediaItem?>(
      stream: audioService.currentMediaStream,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    // Slightly increased height to avoid the song title being clipped at the bottom
                    height: 30,
                    child: AutoScrollText(
                      isRadio && radio != null
                          ? (metadata?.title ?? radio.name)
                          : _formatTitle(metadata?.title),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      // Full-screen title is a little faster than mini but still restrained
                      velocity: 30,
                      pauseAfterRound: const Duration(milliseconds: 2000),
                      syncKey: isRadio && radio != null ? 'radio-${radio.id}' : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    // Slightly larger to match the increased title area and avoid tight vertical spacing
                    height: 22,
                    child: AutoScrollText(
                      isRadio && radio != null
                          ? (metadata?.artist ?? radio.genre)
                          : metadata?.artist ?? 'Unknown Artist',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 16,
                      ),
                      // Full-screen artist matches title speed so both lines move together visually
                      velocity: 30,
                      pauseAfterRound: const Duration(milliseconds: 2000),
                      syncKey: isRadio && radio != null ? 'radio-${radio.id}' : 'song-${metadata?.id ?? metadata?.title ?? "unknown"}',
                    ),
                  ),
                ],
              ),
            ),
            if (isRadio && radio != null)
              IconButton(
                icon: Icon(
                  audioService.getPlaylistRadios('favourite_radios').any((r) => r.id == radio.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: audioService.getPlaylistRadios('favourite_radios').any((r) => r.id == radio.id)
                      ? Colors.deepPurple.shade400
                      : Colors.white,
                ),
                onPressed: () {
                  final isFav = audioService.getPlaylistRadios('favourite_radios').any((r) => r.id == radio.id);
                  if (isFav) {
                    audioService.removeRadioFromPlaylist('favourite_radios', radio);
                  } else {
                    audioService.addRadioToPlaylist('favourite_radios', radio);
                  }
                },
              ),
            if (!isRadio)
              IconButton(
                icon: Icon(
                  audioService.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: audioService.isLiked ? Colors.deepPurple.shade400 : Colors.white,
                ),
                onPressed: () => audioService.toggleLike(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;
    
    return StreamBuilder<(Duration, Duration?)>(
      stream: Rx.combineLatest2(
        audioService.player.positionStream,
        audioService.player.durationStream,
        (position, duration) => (position, duration),
      ).asBroadcastStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 48);
        
        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2 ?? Duration.zero;
        
        // For radio streams, show a full progress bar with "Live Radio Stream" text overlaid in the center
        if (isRadio || duration == Duration.zero) {
          return Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Full width progress bar
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 1.5,
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white,
                    ),
                    child: Slider(
                      value: 1.0, // Always full for radio
                      min: 0.0,
                      max: 1.0,
                      onChanged: null, // Disabled for radio
                    ),
                  ),
                  // Center text with background shape
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Live Radio Stream',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'LIVE',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ],
          );
        }

        final double value = min<double>(
          (_dragValue ?? position.inMilliseconds.toDouble()),
          duration.inMilliseconds.toDouble(),
        );

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.grey.shade600,
                thumbColor: Colors.white,
                overlayColor: Colors.white.withOpacity(0.2),
                trackShape: CustomTrackShape(),
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: duration.inMilliseconds.toDouble(),
                onChanged: duration.inMilliseconds > 0
                    ? (value) {
                        setState(() => _dragValue = value);
                      }
                    : null,
                onChangeEnd: duration.inMilliseconds > 0
                    ? (value) {
                        audioService.player.seek(Duration(milliseconds: value.round()));
                        setState(() => _dragValue = null);
                      }
                    : null,
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${minutes}:${twoDigits(seconds)}';
  }

  Widget _buildPlaybackControls(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final isRadio = audioService.isRadioPlaying;
    
    return StreamBuilder<PlayerState>(
      stream: audioService.player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: isRadio 
                        ? Colors.grey.shade600
                        : audioService.isShuffling
                            ? Colors.deepPurple.shade400
                            : Colors.grey.shade400,
                  ),
                  iconSize: 28,
                  onPressed: isRadio ? null : () => audioService.toggleShuffle(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: Colors.white,
                  iconSize: 40,
                  onPressed: isRadio ? null : () => audioService.player.seekToPrevious(),
                ),
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    color: Colors.black,
                    iconSize: 40,
                    onPressed: () => audioService.playPause(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: Colors.white,
                  iconSize: 40,
                  onPressed: isRadio ? null : () => audioService.player.seekToNext(),
                ),
                IconButton(
                  icon: Icon(
                    audioService.loopMode == LoopMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: isRadio
                        ? Colors.grey.shade600
                        : audioService.loopMode != LoopMode.off
                            ? Colors.deepPurple.shade400
                            : Colors.grey.shade400,
                  ),
                  iconSize: 28,
                  onPressed: isRadio ? null : () => audioService.cycleRepeatMode(),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.cast),
                  color: Colors.grey.shade400,
                  iconSize: 28,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.grey.shade900,
                        title: const Row(
                          children: [
                            Icon(Icons.cast, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Cast to Device',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: CircularProgressIndicator(
                                color: Colors.deepPurple.shade400,
                              ),
                              title: Text(
                                'Searching for devices...',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chromecast support coming soon',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Close',
                              style: TextStyle(color: Colors.deepPurple.shade400),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.queue_music),
                  color: Colors.grey.shade400,
                  iconSize: 28,
                  onPressed: isRadio ? null : () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      isDismissible: true,
                      enableDrag: true,
                      barrierColor: Colors.black54,
                      builder: (context) => const DraggableQueueSheet(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Show Lyrics button
            Center(
              child: SizedBox(
                width: 200, // Smaller width
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.black54,
                        barrierDismissible: true,
                        transitionDuration: const Duration(milliseconds: 300),
                        reverseTransitionDuration: const Duration(milliseconds: 250),
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return const FullScreenLyricsView();
                        },
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
                  icon: const Icon(Icons.music_note),
                  label: const Text('Show Lyrics'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade400,
                    side: BorderSide(color: Colors.grey.shade600, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;

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
  final parts = artist.split(RegExp(r',| & | feat\.? | ft\.? ', caseSensitive: false));
  return parts.first.trim();
}

/// Public helper to request resetting auto-scroll for a given `syncKey`.
/// This bumps the internal sync start and causes any `AutoScrollText`
/// instances sharing that `syncKey` to restart from the initial position.
void resetAutoScrollForKey(String key) => _SyncRegistry.bumpStart(key, DateTime.now());
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
    this.gap = 80.0,
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

class _SpotifyMarqueeState extends State<AutoScrollText> with SingleTickerProviderStateMixin {
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
    final loopMs = (loopDistance / (widget.velocity <= 0 ? 1.0 : widget.velocity) * 1000).round();
    if (loopMs <= 0) return;

    _running = true;

    _controller.duration = Duration(milliseconds: loopMs);

    if (_needReset) {
      // Force starting from the initial position
      if (widget.syncKey != null) _SyncRegistry.setStart(widget.syncKey!, DateTime.now());
      _controller.value = 0.0;
      _needReset = false;
    } else if (widget.syncKey != null) {
      // Align to a shared start time so synced items (title+artist) scroll in-phase
      final start = _SyncRegistry.getOrCreateStart(widget.syncKey!, DateTime.now());
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final initialValue = ((elapsed % loopMs) / loopMs).clamp(0.0, 1.0).toDouble();
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
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : media.size.width;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
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

        if (textWidth != _textWidth || maxWidth != _containerWidth || shouldScrollNow != _shouldScroll) {
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
              final newLoopMs = (newLoop / (widget.velocity <= 0 ? 1.0 : widget.velocity) * 1000).round();
              _controller.duration = Duration(milliseconds: max(1, newLoopMs));
              _controller.value = fraction.clamp(0.0, 1.0);
                      // Check for external bump to the sync start time and reset if seen
                      if (widget.syncKey != null) {
                        final gen = _SyncRegistry.generation(widget.syncKey!);
                        if (gen != _seenSyncGen) {
                          _seenSyncGen = gen;
                          // Restart from initial position
                          if (_running && !_isDisposed) {
                            _controller.stop();
                            _controller.value = 0.0;
                            _controller.repeat();
                          } else {
                            _needReset = true;
                          }
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
                    final minCopies = ((_containerWidth / loopDistance).ceil() + 2).clamp(2, 8);

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

  /// Clear a start (useful for tests or if you want to reset sync state).
  static void clear(String key) => _starts.remove(key);
}
