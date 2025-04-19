import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import 'queue.dart';

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
        );
      },
    );
  }
}

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            iconSize: 36,
            color: Colors.white.withOpacity(0.9),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert),
            iconSize: 32,
            color: Colors.white.withOpacity(0.9),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt() {
    return Container(
      width: 300,
      height: 300,
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
    );
  }

  Widget _buildControls(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              _buildSongInfo(context),
              const SizedBox(height: 20),
              _buildProgressBar(context),
              const SizedBox(height: 20),
              _buildPlaybackControls(context),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: IconButton(
                    icon: const Icon(Icons.queue_music),
                    color: Colors.grey.shade400,
                    iconSize: 24,
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.grey.shade900,
                        builder: (context) => const QueueList(),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
    
    return StreamBuilder<Duration>(
      stream: audioService.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = audioService.player.duration ?? Duration.zero;
        
        // Ensure value is within bounds and convert to double
        final maxValue = duration.inMilliseconds.toDouble();
        final safeValue = position.inMilliseconds.toDouble().clamp(0.0, maxValue > 0 ? maxValue : 1.0);
        
        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.grey.shade600,
                thumbColor: Colors.white,
                overlayColor: Colors.white.withOpacity(0.2),
              ),
              child: Slider(
                value: safeValue,
                min: 0.0,
                max: maxValue > 0 ? maxValue : 1.0,
                onChanged: (value) {
                  if (duration > Duration.zero) {
                    audioService.player.seek(Duration(milliseconds: value.round()));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
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
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Widget _buildPlaybackControls(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    
    return StreamBuilder<PlayerState>(
      stream: audioService.player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: audioService.player.shuffleModeEnabled
                    ? Colors.deepPurple.shade400
                    : Colors.grey.shade400,
              ),
              iconSize: 24,
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
              iconSize: 24,
              onPressed: () {
                final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
                final index = modes.indexOf(audioService.player.loopMode);
                audioService.player.setLoopMode(modes[(index + 1) % modes.length]);
              },
            ),
          ],
        );
      },
    );
  }
}
