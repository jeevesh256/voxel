import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../widgets/player.dart';
import 'dart:io';

class PlaylistPage extends StatelessWidget {
  final String playlistId;
  final String title;
  final IconData icon;

  const PlaylistPage({
    super.key,
    required this.playlistId,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final songs = audioService.getPlaylistSongs(playlistId);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(title),
              background: Container(
                color: Colors.deepPurple.shade400,
                child: Center(
                  child: Icon(
                    icon,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: songs.isEmpty ? null : () {
                  audioService.playPlaylist(playlistId);
                },
                child: const Text('Play All'),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final file = songs[index];
                return ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(
                    file.path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    audioService.playFile(file);
                  },
                );
              },
              childCount: songs.length,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.black,
              selectedItemColor: Colors.deepPurple.shade400,
              unselectedItemColor: Colors.grey,
              currentIndex: 2, // Library tab
              elevation: 0,
              enableFeedback: false,
              onTap: (index) {
                if (index != 2) {
                  Navigator.pop(context);
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
