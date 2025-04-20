import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import 'package:just_audio_background/just_audio_background.dart';
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
                final name = file.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
                
                return StreamBuilder<MediaItem?>(
                  stream: audioService.currentMediaStream,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data?.id == file.path;
                    
                    return ListTile(
                      leading: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: Colors.deepPurple.shade200,
                        ),
                        child: isPlaying
                          ? const Icon(Icons.play_circle, color: Colors.white)
                          : const Icon(Icons.music_note),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Unknown Artist',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      onTap: () {
                        audioService.playFile(file);
                      },
                    );
                  },
                );
              },
              childCount: songs.length,
            ),
          ),
        ],
      ),
    );
  }
}
