import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/playlist_handler.dart';
import '../services/audio_service.dart';
import '../models/song.dart';

class QueueList extends StatefulWidget {
  const QueueList({super.key});

  @override
  State<QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  final Set<String> _dismissingItems = <String>{};

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistHandler>(
      builder: (context, playlistHandler, _) {
        final audioService = context.watch<AudioPlayerService>();
        
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<MediaItem?>(
            stream: audioService.currentMediaStream,
            builder: (context, snapshot) {
              final currentSong = snapshot.data;
              
              // Get the actual playing sequence from the audio player
              return StreamBuilder<SequenceState?>(
                stream: audioService.player.sequenceStateStream,
                builder: (context, sequenceSnapshot) {
                  final sequenceState = sequenceSnapshot.data;
                  if (sequenceState == null || sequenceState.effectiveSequence.isEmpty) {
                    return const Center(
                      child: Text(
                        'No songs in queue',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  // Use effectiveSequence which shows the actual playing order (including shuffle)
                  final songs = sequenceState.effectiveSequence.map((source) {
                    final mediaItem = source.tag as MediaItem?;
                    if (mediaItem != null) {
                      return Song(
                        id: mediaItem.id,
                        title: mediaItem.title,
                        artist: mediaItem.artist ?? 'Unknown Artist',
                        filePath: mediaItem.id, // ID contains the file path
                      );
                    }
                    return null;
                  }).where((song) => song != null).cast<Song>().toList();

                  final currentIndex = currentSong != null 
                    ? songs.indexWhere((song) => song.id == currentSong.id) 
                    : -1;
                  
                  // Spotify-style dual queue system
                  List<Song> nextUpSongs = [];
                  List<Song> laterSongs = [];
                  
                  if (currentIndex != -1) {
                    // Split the queue into manually added (Next Up) and playlist context (Later)
                    final remainingSongs = songs.sublist(currentIndex + 1);
                    
                    for (final song in remainingSongs) {
                      // Find the corresponding audio source to check if it's manually added
                      final songIndex = songs.indexOf(song);
                      if (songIndex < sequenceState.effectiveSequence.length) {
                        final source = sequenceState.effectiveSequence[songIndex];
                        final mediaItem = source.tag as MediaItem?;
                        
                        // Check if this is a manually added song (album = "Next Up")
                        if (mediaItem?.album == 'Next Up') {
                          nextUpSongs.add(song);
                        } else {
                          laterSongs.add(song);
                        }
                      }
                    }
                    
                    // If we're in repeat all mode and on the last song, add the playlist from beginning to "Later"
                    if (audioService.loopMode == LoopMode.all && currentIndex == songs.length - 1) {
                      final playlistSongs = songs.where((song) {
                        final songIndex = songs.indexOf(song);
                        if (songIndex < sequenceState.effectiveSequence.length) {
                          final source = sequenceState.effectiveSequence[songIndex];
                          final mediaItem = source.tag as MediaItem?;
                          return mediaItem?.album != 'Next Up';
                        }
                        return true;
                      }).toList();
                      laterSongs.addAll(playlistSongs);
                    }
                  }
                  
                  // Combine for display (Next Up songs first, then Later songs)
                  var queueSongs = [...nextUpSongs, ...laterSongs];
                  
                  // Filter out dismissing items from the queue
                  queueSongs = queueSongs.where((song) => !_dismissingItems.contains(song.id)).toList();
                  
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
                            if (audioService.isShuffling)
                              Icon(
                                Icons.shuffle,
                                color: Colors.deepPurple.shade400,
                                size: 16,
                              ),
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
                            if (audioService.loopMode != LoopMode.off || audioService.isShuffling)
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
                          child: CustomScrollView(
                            slivers: [
                              // Next Up section (manually added songs)
                              if (nextUpSongs.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Next Up',
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          height: 1,
                                          width: 20,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SliverReorderableList(
                                  itemCount: nextUpSongs.length,
                                  onReorderStart: (index) => HapticFeedback.mediumImpact(),
                                  onReorder: (oldIndex, newIndex) {
                                    // Allow reordering within Next Up section
                                    if (nextUpSongs.length <= 1) return;
                                    
                                    final actualOldIndex = currentIndex + 1 + oldIndex;
                                    final actualNewIndex = currentIndex + 1 + (newIndex > oldIndex ? newIndex - 1 : newIndex);
                                    
                                    if (actualOldIndex >= 0 && actualNewIndex >= 0 && 
                                        actualOldIndex < songs.length && actualNewIndex < songs.length &&
                                        actualOldIndex != actualNewIndex) {
                                      playlistHandler.reorderQueue(actualOldIndex, actualNewIndex);
                                    }
                                  },
                                  itemBuilder: (context, index) {
                                    final song = nextUpSongs[index];
                                    return _buildQueueItem(
                                      song: song,
                                      index: index,
                                      actualIndex: currentIndex + 1 + index,
                                      songs: songs,
                                      snapshot: snapshot,
                                      audioService: audioService,
                                      playlistHandler: playlistHandler,
                                      isNextUp: true,
                                    );
                                  },
                                ),
                                if (laterSongs.isNotEmpty)
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 16),
                                  ),
                              ],
                              
                              // Later section (playlist context songs)
                              if (laterSongs.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Later',
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          height: 1,
                                          width: 20,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SliverReorderableList(
                                  itemCount: laterSongs.length,
                                  onReorderStart: (index) => HapticFeedback.mediumImpact(),
                                  onReorder: (oldIndex, newIndex) {
                                    // Prevent reordering if shuffle is enabled or queue is empty
                                    if (audioService.isShuffling || laterSongs.length <= 1) return;
                                    
                                    final laterStartIndex = currentIndex + 1 + nextUpSongs.length;
                                    final actualOldIndex = laterStartIndex + oldIndex;
                                    final actualNewIndex = laterStartIndex + (newIndex > oldIndex ? newIndex - 1 : newIndex);
                                    
                                    if (actualOldIndex >= 0 && actualNewIndex >= 0 && 
                                        actualOldIndex < songs.length && actualNewIndex < songs.length &&
                                        actualOldIndex != actualNewIndex) {
                                      playlistHandler.reorderQueue(actualOldIndex, actualNewIndex);
                                    }
                                  },
                                  itemBuilder: (context, index) {
                                    final song = laterSongs[index];
                                    final actualIndex = currentIndex + 1 + nextUpSongs.length + index;
                                    return _buildQueueItem(
                                      song: song,
                                      index: index,
                                      actualIndex: actualIndex,
                                      songs: songs,
                                      snapshot: snapshot,
                                      audioService: audioService,
                                      playlistHandler: playlistHandler,
                                      isNextUp: false,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Song song,
    required int index,
    required int actualIndex,
    required List<Song> songs,
    required AsyncSnapshot<MediaItem?> snapshot,
    required AudioPlayerService audioService,
    required PlaylistHandler playlistHandler,
    required bool isNextUp,
  }) {
    // Skip items that are being dismissed
    if (_dismissingItems.contains(song.id)) {
      return const SizedBox.shrink();
    }
    
    // Use a stable key based on song ID and section
    final dismissibleKey = ValueKey('queue_${isNextUp ? 'nextup' : 'later'}_${song.id}');
    
    return Dismissible(
      key: dismissibleKey,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: snapshot.data?.id == song.id 
          ? DismissDirection.none // Can't dismiss currently playing
          : DismissDirection.endToStart, // Allow dismissal for queue songs
      confirmDismiss: (direction) async {
        // Prevent dismissal if currently playing
        if (snapshot.data?.id == song.id) {
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        // Only proceed if the song is not currently playing
        if (snapshot.data?.id == song.id) return;
        
        // Mark as dismissing to prevent rebuilds
        if (mounted) {
          setState(() {
            _dismissingItems.add(song.id);
          });
        }

        try {
          // Remove using song ID to avoid index issues
          await playlistHandler.removeSongFromSession(song.id);
        } catch (e) {
          debugPrint('Error dismissing song ${song.id}: $e');
        } finally {
          // Clean up the dismissing state
          if (mounted) {
            setState(() {
              _dismissingItems.remove(song.id);
            });
          }
        }
      },
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          key: ValueKey('listile_${song.id}'),
          leading: Builder(
            builder: (context) {
              final isPlaying = snapshot.data?.id == song.id;
              return Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: isNextUp 
                      ? Colors.blue.shade200 // Different color for Next Up songs
                      : Colors.deepPurple.shade200,
                ),
                child: isPlaying
                    ? const Icon(Icons.play_circle, color: Colors.white)
                    : Icon(
                        isNextUp ? Icons.queue_music : Icons.music_note,
                        color: Colors.white,
                      ),
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
            : audioService.isShuffling && !isNextUp
                ? const Icon(
                    Icons.shuffle,
                    color: Colors.grey,
                    size: 16,
                  )
                : ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: isNextUp ? Colors.blue.shade400 : Colors.grey,
                    ),
                  ),
          onTap: () {
            // Use the already calculated actualIndex for consistency
            if (actualIndex >= 0 && actualIndex < songs.length) {
              audioService.playQueueItem(actualIndex);
            }
          },
        ),
      ),
    );
  }
}
