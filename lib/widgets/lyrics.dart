import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/audio_service.dart';
import 'package:provider/provider.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lyrics',
            style: TextStyle(
              color: Colors.white,
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
                  color: Colors.grey.shade400,
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
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        onVerticalDragEnd: (details) {
          // Swipe down to dismiss
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
                Colors.deepPurple.shade400,
                Colors.grey.shade900,
                Colors.black,
              ],
            ),
          ),
          child: SafeArea(
            child: GestureDetector(
              onTap: () {}, // Prevent tap from propagating to parent
              child: Column(
                children: [
                  _buildAppStyledHeader(context),
                  const SizedBox(height: 24),
                  _buildSongInfo(context, audioService),
                  const SizedBox(height: 32),
                  Expanded(
                    child: _buildLyricsContent(),
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

  Widget _buildAppStyledHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            iconSize: 28,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lyrics,
                  color: Colors.deepPurple.shade300,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Lyrics',
                  style: TextStyle(
                    color: Colors.white,
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
              color: Colors.grey.shade400,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: StreamBuilder<MediaItem?>(
        stream: audioService.currentMediaStream,
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          return Column(
            children: [
              // Album art similar to main player
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.music_note,
                  color: Colors.grey.shade400,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              // Song title
              Text(
                (metadata?.title ?? 'Unknown Track').replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), ''),
                style: const TextStyle(
                  color: Colors.white,
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
                  color: Colors.grey.shade400,
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

  Widget _buildLyricsContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with app styling
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade400.withOpacity(0.2),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.deepPurple.shade400.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.lyrics_outlined,
              size: 50,
              color: Colors.deepPurple.shade300,
            ),
          ),
          const SizedBox(height: 32),
          // Main message
          const Text(
            'No lyrics available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Subtitle
          Text(
            'Lyrics will appear here when they\'re\navailable for this track',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Hint with app styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade400.withOpacity(0.2),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: Colors.deepPurple.shade400.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swipe_down_alt,
                  size: 18,
                  color: Colors.deepPurple.shade300,
                ),
                const SizedBox(width: 10),
                Text(
                  'Swipe down or tap to close',
                  style: TextStyle(
                    color: Colors.grey.shade300,
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
