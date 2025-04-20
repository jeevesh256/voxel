import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';  // Add this import
import 'package:just_audio_background/just_audio_background.dart';
import '../services/playlist_handler.dart';
import '../models/song.dart';
import '../services/audio_service.dart';

class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistHandler>(
      builder: (context, playlistHandler, _) {
        final songs = playlistHandler.queue;
        final audioService = context.watch<AudioPlayerService>();

        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<MediaItem?>(
            stream: audioService.currentMediaStream,
            builder: (context, snapshot) {
              final currentSong = snapshot.data;
              final currentIndex = currentSong != null 
                ? songs.indexWhere((song) => song.id == currentSong.id) 
                : -1;
              
              // Show remaining songs + all songs if in repeat mode
              final queueSongs = currentIndex != -1
                ? (audioService.loopMode != LoopMode.off && currentIndex == songs.length - 1)
                    ? songs  // Show all songs when repeating and on last song
                    : songs.sublist(currentIndex + 1)
                : [];
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Up Next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (queueSongs.isNotEmpty)
                        Text(
                          '${queueSongs.length} tracks',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (queueSongs.isEmpty)
                    const Center(
                      child: Text(
                        'No songs in queue',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: queueSongs.length,
                        onReorderStart: (index) => HapticFeedback.mediumImpact(),
                        onReorder: (oldIndex, newIndex) {
                          // Convert display indices to actual playlist indices
                          final actualOldIndex = currentIndex == songs.length - 1
                              ? oldIndex  // Use direct indices when showing full playlist
                              : currentIndex + 1 + oldIndex;
                          final actualNewIndex = currentIndex == songs.length - 1
                              ? newIndex
                              : currentIndex + 1 + (newIndex > oldIndex ? newIndex - 1 : newIndex);
                          playlistHandler.reorderQueue(actualOldIndex, actualNewIndex);
                        },
                        itemBuilder: (context, index) {
                          final song = queueSongs[index];
                          return Dismissible(
                            key: ValueKey('dismissible_${song.id}'),
                            background: Container(
                              color: Colors.red.shade400,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            direction: snapshot.data?.id == song.id ? DismissDirection.none : DismissDirection.endToStart,
                            onDismissed: (_) {
                              playlistHandler.removeFromQueue(index);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed ${song.title}'),
                                  backgroundColor: Colors.grey.shade900,
                                  behavior: SnackBarBehavior.floating,
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      playlistHandler.addToQueue(song);
                                    },
                                  ),
                                ),
                              );
                            },
                            child: ListTile(
                              leading: StreamBuilder<MediaItem?>(
                                stream: audioService.currentMediaStream,
                                builder: (context, snapshot) {
                                  final isPlaying = snapshot.data?.id == song.id;
                                  return Container(
                                    height: 40,
                                    width: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Colors.deepPurple.shade200,
                                    ),
                                    child: isPlaying
                                      ? const Icon(Icons.play_circle, color: Colors.white)
                                      : const Icon(Icons.music_note),
                                  );
                                },
                              ),
                              title: Text(
                                song.title,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                song.artist,
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                              trailing: snapshot.data?.id == song.id ? null : ReorderableDragStartListener(
                                index: index,
                                child: const Icon(
                                  Icons.drag_handle,
                                  color: Colors.grey,
                                ),
                              ),
                              onTap: () {
                                final actualIndex = currentIndex == songs.length - 1
                                    ? index  // Use direct index when showing full playlist
                                    : currentIndex + 1 + index;
                                audioService.playQueueItem(actualIndex);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  int _getActualIndex(int displayIndex, int currentSongIndex) {
    if (currentSongIndex == -1) return displayIndex;
    return displayIndex >= currentSongIndex ? displayIndex + 1 : displayIndex;
  }
}
