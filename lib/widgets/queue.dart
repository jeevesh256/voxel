import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';  // Add this import
import 'package:just_audio_background/just_audio_background.dart';
import '../services/playlist_handler.dart';
import '../services/audio_service.dart';
import '../models/song.dart';

class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistHandler>(
      builder: (context, playlistHandler, _) {
        final songs = playlistHandler.queue; // Current session queue
        final originalPlaylist = playlistHandler.originalPlaylist; // Original playlist for repeat
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
              
              // Get the queue (songs after current song) - Spotify style
              List<Song> queueSongs = [];
              
              if (currentIndex != -1) {
                if (audioService.loopMode == LoopMode.one) {
                  // Repeat song: no queue, just the same song repeating
                  queueSongs = [];
                } else if (audioService.loopMode == LoopMode.all) {
                  // Repeat playlist: show remaining + original playlist if on last song
                  if (currentIndex < songs.length - 1) {
                    // Still have songs after current in session
                    queueSongs = songs.sublist(currentIndex + 1);
                  } else {
                    // On last song, show original playlist starting from beginning
                    queueSongs = List.from(originalPlaylist);
                  }
                } else {
                  // Repeat off: only show remaining songs in current session
                  if (currentIndex < songs.length - 1) {
                    queueSongs = songs.sublist(currentIndex + 1);
                  }
                }
              }
              
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
                      if (queueSongs.isNotEmpty) ...[
                        if (audioService.loopMode == LoopMode.all)
                          Icon(
                            Icons.repeat,
                            color: Colors.deepPurple.shade400,
                            size: 16,
                          )
                        else if (audioService.loopMode == LoopMode.one)
                          Icon(
                            Icons.repeat_one,
                            color: Colors.deepPurple.shade400,
                            size: 16,
                          ),
                        if (audioService.loopMode != LoopMode.off)
                          const SizedBox(width: 4),
                        Text(
                          '${queueSongs.length} ${queueSongs.length == 1 ? 'track' : 'tracks'}',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (queueSongs.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              audioService.loopMode == LoopMode.one 
                                ? Icons.repeat_one 
                                : Icons.queue_music,
                              color: Colors.grey.shade600,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              audioService.loopMode == LoopMode.one
                                ? 'Current song on repeat'
                                : 'No more songs in queue',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: queueSongs.length,
                        onReorderStart: (index) => HapticFeedback.mediumImpact(),
                        onReorder: (oldIndex, newIndex) {
                          // Calculate actual indices based on queue state
                          int getActualIndex(int displayIndex) {
                            if (audioService.loopMode == LoopMode.all && currentIndex == songs.length - 1) {
                              // Showing original playlist from beginning - need to map to current session
                              final originalSong = originalPlaylist[displayIndex];
                              return songs.indexWhere((song) => song.id == originalSong.id);
                            } else {
                              // Showing remaining songs after current in session
                              return currentIndex + 1 + displayIndex;
                            }
                          }
                          
                          final actualOldIndex = getActualIndex(oldIndex);
                          final actualNewIndex = getActualIndex(newIndex > oldIndex ? newIndex - 1 : newIndex);
                          
                          if (actualOldIndex != -1 && actualNewIndex != -1) {
                            playlistHandler.reorderQueue(actualOldIndex, actualNewIndex);
                          }
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
                            direction: () {
                              // Check if this song can be dismissed
                              if (snapshot.data?.id == song.id) {
                                return DismissDirection.none; // Can't dismiss currently playing
                              }
                              
                              // If showing original playlist in repeat mode, check if song exists in current session
                              if (audioService.loopMode == LoopMode.all && currentIndex == songs.length - 1) {
                                final originalSong = originalPlaylist[index];
                                final existsInSession = songs.any((song) => song.id == originalSong.id);
                                return existsInSession ? DismissDirection.endToStart : DismissDirection.none;
                              }
                              
                              return DismissDirection.endToStart;
                            }(),
                            onDismissed: (_) {
                              // Calculate actual index in the current session
                              int actualIndex;
                              if (audioService.loopMode == LoopMode.all && currentIndex == songs.length - 1) {
                                // Showing original playlist - find song in current session
                                final originalSong = originalPlaylist[index];
                                actualIndex = songs.indexWhere((song) => song.id == originalSong.id);
                              } else {
                                // Showing remaining songs after current
                                actualIndex = currentIndex + 1 + index;
                              }
                              
                              // Remove from session only (keeps original playlist intact for repeat)
                              if (actualIndex != -1) {
                                playlistHandler.removeFromSession(actualIndex);
                              }
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
                              trailing: snapshot.data?.id == song.id 
                                ? Icon(
                                    Icons.play_circle,
                                    color: Colors.deepPurple.shade400,
                                  )
                                : ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(
                                      Icons.drag_handle,
                                      color: Colors.grey,
                                    ),
                                  ),
                              onTap: () {
                                // Calculate actual index in the current session
                                int actualIndex;
                                if (audioService.loopMode == LoopMode.all && currentIndex == songs.length - 1) {
                                  // Showing original playlist - find song in current session
                                  final originalSong = originalPlaylist[index];
                                  actualIndex = songs.indexWhere((song) => song.id == originalSong.id);
                                } else {
                                  // Showing remaining songs after current
                                  actualIndex = currentIndex + 1 + index;
                                }
                                
                                if (actualIndex != -1) {
                                  audioService.playQueueItem(actualIndex);
                                }
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
}
