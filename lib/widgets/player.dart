import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';  // Add this import at the top with other imports
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:math';
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
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const FullScreenPlayer(),
            );
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
                              ? DecorationImage(image: NetworkImage(metadata!.artUri.toString()))
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
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  isRadio && radio != null
                                    ? radio.name
                                    : metadata?.title ?? 'No Track Playing',
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 16,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  isRadio && radio != null
                                    ? radio.genre
                                    : metadata?.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12,
                                  ),
                                ),
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

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  double? _dragValue;
  double _dragOffset = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dy;
          if (_dragOffset < 0) _dragOffset = 0;
        });
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        
        // Simple logic: dismiss if dragged down 150px OR fast swipe
        if (_dragOffset > 150 || velocity > 500) {
          Navigator.pop(context);
        } else {
          setState(() {
            _dragOffset = 0;
          });
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: _dragOffset > 0 ? 0 : 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _dragOffset, 0),
        child: Container(
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
      ),
    ), // Transform.translate
    ); // GestureDetector
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
    final metadata = audioService.currentMedia;
    final padding = const EdgeInsets.symmetric(horizontal: 24);
    Widget artWidget;
    if ((isRadio && radio != null && radio.artworkUrl.isNotEmpty) || (metadata?.artUri != null && metadata!.artUri.toString().isNotEmpty)) {
      final imageUrl = isRadio && radio != null ? radio.artworkUrl : metadata!.artUri.toString();
      artWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: FadeInImage.assetNetwork(
          key: ValueKey(imageUrl),
          placeholder: 'assets/placeholder.png', // Add a placeholder image to your assets
          image: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
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
          child: artWidget,
        ),
      ),
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
                    height: 26,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        isRadio && radio != null
                          ? (metadata?.title ?? radio.name)
                          : _formatTitle(metadata?.title),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 20,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        isRadio && radio != null
                          ? (metadata?.artist ?? radio.genre)
                          : metadata?.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 16,
                        ),
                      ),
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

        final value = min(
          (_dragValue ?? position.inMilliseconds).toDouble(),
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
