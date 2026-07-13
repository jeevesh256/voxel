import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/audio_service.dart';
import 'package:provider/provider.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lyrics',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: Text(
                'No lyrics available',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullScreenLyricsView extends StatelessWidget {
  const FullScreenLyricsView({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.pop(context);
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primaryContainer.withOpacity(0.6),
                cs.surface,
                cs.surfaceContainerLow,
              ],
            ),
          ),
          child: SafeArea(
            child: GestureDetector(
              onTap: () {}, // Prevent tap from propagating to parent
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  _buildSongInfo(context, audioService),
                  const SizedBox(height: 32),
                  Expanded(
                    child: _buildLyricsContent(context),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: cs.onSurface),
            onPressed: () => Navigator.pop(context),
            iconSize: 28,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lyrics,
                  color: cs.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lyrics',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.share,
              color: cs.onSurfaceVariant,
              size: 24,
            ),
            onPressed: () {
              // TODO: Share functionality
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, AudioPlayerService audioService) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: StreamBuilder<MediaItem?>(
        stream: audioService.currentMediaStream,
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          return Column(
            children: [
              // Album art placeholder
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.music_note,
                  color: cs.onSurfaceVariant,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              // Song title
              Text(
                (metadata?.title ?? 'Unknown Track')
                    .replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), ''),
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Artist name
              Text(
                metadata?.artist ?? 'Unknown Artist',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLyricsContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with themed styling
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: cs.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.lyrics_outlined,
              size: 50,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No lyrics available',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Lyrics will appear here when they\'re\navailable for this track',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Swipe-to-close hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.25),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: cs.primary.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swipe_down_alt,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Swipe down or tap to close',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
