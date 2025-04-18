import 'package:flutter/material.dart';
import 'queue.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
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
              ),
              child: const Icon(Icons.music_note),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currently Playing Song',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Artist Name',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_border),
              color: Colors.white,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              color: Colors.white,
              onPressed: () {},
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
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
            const Spacer(flex: 2), // Use flex for proportional spacing
            _buildAlbumArt(),
            const Spacer(flex: 3), // More space below album art
            _buildControls(context),
            const SizedBox(height: 40), // Fixed bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8), // Increased top padding
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            iconSize: 36, // Increased icon size
            color: Colors.white.withOpacity(0.9),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert),
            iconSize: 32, // Increased icon size
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
              _buildSongInfo(),
              const SizedBox(height: 20),
              _buildProgressBar(),
              const SizedBox(height: 20),
              _buildPlaybackControls(),
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

  Widget _buildSongInfo() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Currently Playing Song',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Artist Name',
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.favorite_border),
          color: Colors.white,
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
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
            value: 0.5,
            onChanged: (value) {},
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('2:30', style: TextStyle(color: Colors.grey.shade400)),
              Text('4:30', style: TextStyle(color: Colors.grey.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.shuffle),
          color: Colors.grey.shade400,
          iconSize: 24,
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous),
          color: Colors.white,
          iconSize: 40,
          onPressed: () {},
        ),
        Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: IconButton(
            icon: const Icon(Icons.play_arrow),
            color: Colors.black,
            iconSize: 40,
            onPressed: () {},
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next),
          color: Colors.white,
          iconSize: 40,
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.repeat),
          color: Colors.grey.shade400,
          iconSize: 24,
          onPressed: () {},
        ),
      ],
    );
  }
}
