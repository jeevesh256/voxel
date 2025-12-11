import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:io';
import 'dart:async';
import '../services/playlist_handler.dart';
import '../services/audio_service.dart';
import '../models/song.dart';

class DraggableQueueSheet extends StatefulWidget {
  const DraggableQueueSheet({super.key});

  @override
  State<DraggableQueueSheet> createState() => _DraggableQueueSheetState();
}

class _DraggableQueueSheetState extends State<DraggableQueueSheet> {
  final Set<String> _dismissingItems = <String>{};
  bool _dismissed = false;
  OverlayEntry? _undoOverlay;
  Timer? _undoTimer;
  Song? _pendingUndoSong;
  int? _pendingUndoIndex;

  void _maybeDismiss(BuildContext context) {
    if (_dismissed) return;
    _dismissed = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _removeUndoOverlay() {
    _undoTimer?.cancel();
    _undoTimer = null;
    _undoOverlay?.remove();
    _undoOverlay = null;
  }

  Future<void> _finalizePendingRemoval(PlaylistHandler playlistHandler) async {
    final pendingSong = _pendingUndoSong;
    if (pendingSong != null) {
      try {
        await playlistHandler.removeSongFromSession(pendingSong.id);
      } catch (e) {
        debugPrint('Error finalizing removal ${pendingSong.id}: $e');
      }
      if (mounted) {
        setState(() {
          _dismissingItems.remove(pendingSong.id);
        });
      }
    }
    _pendingUndoSong = null;
    _pendingUndoIndex = null;
  }

  void _showUndoOverlay({
    required Song song,
    required int index,
    required PlaylistHandler playlistHandler,
  }) {
    _removeUndoOverlay();
    _pendingUndoSong = song;
    _pendingUndoIndex = index;

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    _undoOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: 12,
        right: 12,
        bottom: 16 + bottomPadding,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF323232),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Removed "${song.title}"',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _undoTimer?.cancel();
                      _undoTimer = null;

                      if (mounted) {
                        setState(() {
                          _dismissingItems.remove(song.id);
                        });
                      }

                      _pendingUndoSong = null;
                      _pendingUndoIndex = null;
                      _removeUndoOverlay();
                    },
                    child: const Text(
                      'UNDO',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_undoOverlay!);

    _undoTimer = Timer(const Duration(seconds: 5), () async {
      _removeUndoOverlay();
      await _finalizePendingRemoval(playlistHandler);
    });
  }

  @override
  void dispose() {
    _removeUndoOverlay();
    _pendingUndoSong = null;
    _pendingUndoIndex = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => _maybeDismiss(context),
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! > 6) {
                _maybeDismiss(context);
              }
            },
            onVerticalDragEnd: (details) {
              if (details.velocity.pixelsPerSecond.dy > 400) {
                _maybeDismiss(context);
              }
            },
          ),
        ),
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            // Track extent if needed in the future
            return false;
          },
          child: DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.5, 0.95],
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: NotificationListener<OverscrollNotification>(
                  onNotification: (notification) {
                    // When scrolling past the edge, let the sheet handle it
                    return false;
                  },
                  child: Consumer<PlaylistHandler>(
                    builder: (context, playlistHandler, _) {
                      final audioService = context.watch<AudioPlayerService>();
                      
                      return StreamBuilder<MediaItem?>(
                        stream: audioService.currentMediaStream,
                        builder: (context, snapshot) {
                          final currentSong = snapshot.data;
                          
                          return StreamBuilder<SequenceState?>(
                            stream: audioService.player.sequenceStateStream,
                            builder: (context, sequenceSnapshot) {
                              final sequenceState = sequenceSnapshot.data;
                              
                              if (sequenceState == null || sequenceState.effectiveSequence.isEmpty) {
                                return CustomScrollView(
                                  controller: scrollController,
                                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: Column(
                                        children: [
                                          _buildDragHandle(),
                                          _buildQueueHeader(),
                                          const SizedBox(height: 20),
                                        ],
                                      ),
                                    ),
                                    SliverFillRemaining(
                                      child: Center(
                                        child: Text(
                                          'No songs in queue',
                                          style: TextStyle(color: Colors.grey.shade400),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                              
                              // Parse queue data
                              final songs = sequenceState.effectiveSequence.map((source) {
                                final mediaItem = source.tag as MediaItem?;
                                if (mediaItem != null) {
                                  final artUri = mediaItem.artUri;
                                  final artPath = artUri != null && artUri.scheme == 'file'
                                      ? artUri.toFilePath()
                                      : '';

                                  return Song(
                                    id: mediaItem.id,
                                    title: mediaItem.title,
                                    artist: mediaItem.artist ?? 'Unknown Artist',
                                    filePath: mediaItem.id,
                                    albumArt: artPath,
                                  );
                                }
                                return null;
                              }).where((song) => song != null).cast<Song>().toList();

                              final currentIndex = currentSong != null 
                                ? songs.indexWhere((song) => song.id == currentSong.id) 
                                : -1;
                              
                              // Split queue into Next Up and Later
                              List<Song> nextUpSongs = [];
                              List<Song> laterSongs = [];
                              
                              if (currentIndex != -1) {
                                final remainingSongs = songs.sublist(currentIndex + 1);
                                
                                for (final song in remainingSongs) {
                                  final songIndex = songs.indexOf(song);
                                  if (songIndex < sequenceState.effectiveSequence.length) {
                                    final source = sequenceState.effectiveSequence[songIndex];
                                    final mediaItem = source.tag as MediaItem?;
                                    
                                    if (mediaItem?.album == 'Next Up') {
                                      nextUpSongs.add(song);
                                    } else {
                                      laterSongs.add(song);
                                    }
                                  }
                                }
                                
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
                              
                              var queueSongs = [...nextUpSongs, ...laterSongs];
                              queueSongs = queueSongs.where((song) => !_dismissingItems.contains(song.id)).toList();
                              
                              return CustomScrollView(
                                controller: scrollController,
                                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                slivers: [
                                  // Drag handle and Queue title
                                  SliverToBoxAdapter(
                                    child: Column(
                                      children: [
                                        _buildDragHandle(),
                                        _buildQueueHeader(),
                                      ],
                                    ),
                                  ),
                                  
                                  // Queue stats header
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      child: Row(
                                        children: [
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
                                    ),
                                  ),
                                  
                                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                                  
                                  // Empty state or queue content
                                  if (queueSongs.isEmpty)
                                    SliverFillRemaining(
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
                                  else ...[
                                    // Next Up section
                                    if (nextUpSongs.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                      SliverPadding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        sliver: SliverReorderableList(
                                          itemCount: nextUpSongs.length,
                                          onReorderStart: (index) => HapticFeedback.mediumImpact(),
                                          onReorder: (oldIndex, newIndex) {
                                            if (nextUpSongs.length <= 1) return;
                                            
                                            final actualOldIndex = currentIndex + 1 + oldIndex;
                                            final actualNewIndex = currentIndex + 1 + newIndex;
                                            
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
                                              currentSong: currentSong,
                                              audioService: audioService,
                                              playlistHandler: playlistHandler,
                                              isNextUp: true,
                                            );
                                          },
                                        ),
                                      ),
                                      if (laterSongs.isNotEmpty)
                                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                                    ],
                                    
                                    // Later section
                                    if (laterSongs.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                      SliverPadding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        sliver: SliverReorderableList(
                                          itemCount: laterSongs.length,
                                          onReorderStart: (index) => HapticFeedback.mediumImpact(),
                                          onReorder: (oldIndex, newIndex) {
                                            if (audioService.isShuffling || laterSongs.length <= 1) return;
                                            
                                            final laterStartIndex = currentIndex + 1 + nextUpSongs.length;
                                            final actualOldIndex = laterStartIndex + oldIndex;
                                            final actualNewIndex = laterStartIndex + newIndex;
                                            
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
                                              currentSong: currentSong,
                                              audioService: audioService,
                                              playlistHandler: playlistHandler,
                                              isNextUp: false,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDragHandle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      width: double.infinity,
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      width: double.infinity,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Queue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItem({
    required Song song,
    required int index,
    required int actualIndex,
    required List<Song> songs,
    required MediaItem? currentSong,
    required AudioPlayerService audioService,
    required PlaylistHandler playlistHandler,
    required bool isNextUp,
  }) {
    final isHidden = _dismissingItems.contains(song.id);
    final dismissibleKey = ValueKey('queue_${isNextUp ? 'nextup' : 'later'}_${song.id}');

    if (isHidden) {
      return KeyedSubtree(
        key: dismissibleKey,
        child: const SizedBox.shrink(),
      );
    }
    
    return Dismissible(
      key: dismissibleKey,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
        direction: currentSong?.id == song.id 
          ? DismissDirection.none
          : DismissDirection.endToStart,
      movementDuration: const Duration(milliseconds: 160),
      resizeDuration: const Duration(milliseconds: 160),
      confirmDismiss: (direction) async {
        if (currentSong?.id == song.id) {
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        if (currentSong?.id == song.id) return;
        final removedSong = song;
        final removedIndex = actualIndex;

        if (mounted) {
          setState(() {
            _dismissingItems.add(removedSong.id);
          });
        }

        // If another undo is pending, finalize it before scheduling new one
        if (_pendingUndoSong != null) {
          await _finalizePendingRemoval(playlistHandler);
        }

        if (!mounted) return;
        _showUndoOverlay(
          song: removedSong,
          index: removedIndex,
          playlistHandler: playlistHandler,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          key: ValueKey('listile_${song.id}'),
          leading: Builder(
            builder: (context) {
              final isPlaying = currentSong?.id == song.id;
              final artPath = song.albumArt ?? '';

              Widget placeholder(Color color) => Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: color,
                    ),
                    child: isPlaying
                        ? const Icon(Icons.play_circle, color: Colors.white)
                        : Icon(
                            isNextUp ? Icons.queue_music : Icons.music_note,
                            color: Colors.white,
                          ),
                  );

              if (artPath.isNotEmpty) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(artPath),
                    height: 44,
                    width: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder(
                      isNextUp ? Colors.blue.shade200 : Colors.deepPurple.shade200,
                    ),
                  ),
                );
              }

              return placeholder(isNextUp ? Colors.blue.shade200 : Colors.deepPurple.shade200);
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
          trailing: currentSong?.id == song.id 
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
                : GestureDetector(
                    onTap: () {}, // Absorb taps to prevent ListTile onTap
                    child: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle,
                        color: isNextUp ? Colors.blue.shade400 : Colors.grey,
                      ),
                    ),
                  ),
          onTap: () {
            if (actualIndex >= 0 && actualIndex < songs.length) {
              audioService.playQueueItem(actualIndex);
            }
          },
        ),
      ),
    );
  }
}

// QueueList widget is no longer needed - all logic moved to DraggableQueueSheet
/*
class QueueList extends StatefulWidget {
  final ScrollController? scrollController;
  final bool isExpanded;
  
  const QueueList({
    super.key,
    this.scrollController,
    this.isExpanded = false,
  });

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
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
*/
