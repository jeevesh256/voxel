import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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
    
    return StreamBuilder<PlayerState>(
      stream: audioService.player.playerStateStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.processingState == ProcessingState.idle) {
          return const SizedBox.shrink();
        }

        final isPlaying = snapshot.data?.playing ?? false;
        final metadata = audioService.currentTrack;

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
                          image: metadata?.artUri != null 
                            ? DecorationImage(image: NetworkImage(metadata!.artUri.toString()))
                            : null,
                        ),
                        child: metadata?.artUri == null ? const Icon(Icons.music_note) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metadata?.title ?? 'No Track Playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              metadata?.artist ?? 'Unknown Artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          audioService.isLiked ? Icons.favorite : Icons.favorite_border,
                          color: audioService.isLiked ? Colors.deepPurple.shade400 : Colors.white,
                        ),
                        onPressed: () => audioService.toggleLike(),
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
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 2);
        
        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2 ?? Duration.zero;
        
        if (duration == Duration.zero) return const SizedBox(height: 2);

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

  @override
  Widget build(BuildContext context) {
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
            const Spacer(flex: 2),
            _buildAlbumArt(),
            const Spacer(flex: 3),
            _buildControls(context),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
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
    final padding = const EdgeInsets.symmetric(horizontal: 24);
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
          child: const Icon(Icons.music_note, size: 80, color: Colors.white),
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
    final metadata = audioService.currentTrack;
    
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTitle(metadata?.title),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                metadata?.artist ?? 'Unknown Artist',
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            audioService.isLiked ? Icons.favorite : Icons.favorite_border,
            color: audioService.isLiked ? Colors.deepPurple.shade400 : Colors.white,
          ),
          onPressed: () => audioService.toggleLike(),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    
    return StreamBuilder<(Duration, Duration?)>(
      stream: Rx.combineLatest2(
        audioService.player.positionStream,
        audioService.player.durationStream,
        (position, duration) => (position, duration),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 48);
        
        final position = snapshot.data!.$1;
        final duration = snapshot.data!.$2 ?? Duration.zero;
        
        if (duration == Duration.zero) {
          return const SizedBox(height: 48);
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
                    color: audioService.player.shuffleModeEnabled
                        ? Colors.deepPurple.shade400
                        : Colors.grey.shade400,
                  ),
                  iconSize: 28,
                  onPressed: () => audioService.player.setShuffleModeEnabled(
                    !audioService.player.shuffleModeEnabled,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: Colors.white,
                  iconSize: 40,
                  onPressed: () => audioService.player.seekToPrevious(),
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
                  onPressed: () => audioService.player.seekToNext(),
                ),
                IconButton(
                  icon: Icon(
                    Icons.repeat,
                    color: audioService.player.loopMode != LoopMode.off
                        ? Colors.deepPurple.shade400
                        : Colors.grey.shade400,
                  ),
                  iconSize: 28,
                  onPressed: () {
                    final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
                    final index = modes.indexOf(audioService.player.loopMode);
                    audioService.player.setLoopMode(modes[(index + 1) % modes.length]);
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.lyrics),
                  color: Colors.grey.shade400,
                  iconSize: 28,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.grey.shade900,
                      builder: (context) => const LyricsView(),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.queue_music),
                  color: Colors.grey.shade400,
                  iconSize: 28,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.grey.shade900,
                      builder: (context) => const QueueList(),
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
