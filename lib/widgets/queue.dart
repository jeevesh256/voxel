import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import '../services/playlist_handler.dart';
import '../services/audio_service.dart';
import '../models/song.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

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
                    onPressed: () async {
                      _undoTimer?.cancel();
                      _undoTimer = null;
 
                      // Instantly re-insert the song back at the exact index
                      await playlistHandler.insertAtQueue(song, index);
 
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
 
    _undoTimer = Timer(const Duration(seconds: 5), () {
      _removeUndoOverlay();
      _pendingUndoSong = null;
      _pendingUndoIndex = null;
    });
  }
 
  @override
  void dispose() {
    _removeUndoOverlay();
    super.dispose();
  }

  Widget _buildDragHandle() {
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      width: double.infinity,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required int trackCount,
    required bool isShuffling,
    required LoopMode loopMode,
    bool showClearButton = false,
    VoidCallback? onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Row(
        children: [
          const Text(
            'Queue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (trackCount > 0) ...[
            if (isShuffling)
              Icon(
                Icons.shuffle,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              ),
            if (loopMode == LoopMode.all)
              Icon(
                Icons.repeat,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              )
            else if (loopMode == LoopMode.one)
              Icon(
                Icons.repeat_one,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              ),
            if (loopMode != LoopMode.off || isShuffling)
              const SizedBox(width: 6),
            Text(
              '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
          if (showClearButton && onClear != null) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Clear',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = scheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.65, 0.95],
      expand: false,
      builder: (context, scrollController) {
        return Consumer<PlaylistHandler>(
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

                    // Handle empty queue case
                    if (sequenceState == null || sequenceState.effectiveSequence.isEmpty) {
                       return Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                primaryColor.withOpacity(0.45),
                                const Color(0xFF161616),
                              ),
                              Color.alphaBlend(
                                primaryColor.withOpacity(0.12),
                                const Color(0xFF0F0F0F),
                              ),
                              const Color(0xFF0C0C0C),
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: CustomScrollView(
                            controller: scrollController,
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    _buildDragHandle(),
                                    _buildHeader(trackCount: 0, isShuffling: false, loopMode: LoopMode.off),
                                  ],
                                ),
                              ),
                              SliverFillRemaining(
                                child: Center(
                                  child: Text(
                                    'No songs in queue',
                                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

                    nextUpSongs = nextUpSongs.where((song) => !_dismissingItems.contains(song.id)).toList();
                    laterSongs = laterSongs.where((song) => !_dismissingItems.contains(song.id)).toList();
                    var queueSongs = [...nextUpSongs, ...laterSongs];

                    final activeSong = currentSong != null
                        ? Song(
                            id: currentSong.id,
                            title: currentSong.title,
                            artist: currentSong.artist ?? 'Unknown Artist',
                            filePath: currentSong.id,
                            albumArt: currentSong.artUri?.scheme == 'file'
                                ? currentSong.artUri!.toFilePath()
                                : '',
                          )
                        : null;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.alphaBlend(
                              primaryColor.withOpacity(0.45),
                              const Color(0xFF161616),
                            ),
                            Color.alphaBlend(
                              primaryColor.withOpacity(0.12),
                              const Color(0xFF0F0F0F),
                            ),
                            const Color(0xFF0C0C0C),
                          ],
                        ),
                      ),
                      child: SafeArea(
                        top: true, // Safeguard status bar space when expanded
                        child: CustomScrollView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                children: [
                                  _buildDragHandle(),
                                  _buildHeader(
                                    trackCount: queueSongs.length,
                                    isShuffling: audioService.isShuffling,
                                    loopMode: audioService.loopMode,
                                    showClearButton: nextUpSongs.isNotEmpty,
                                    onClear: () {
                                      playlistHandler.clearQueue();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (currentSong != null && activeSong != null) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Now Playing',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        height: 1,
                                        width: 20,
                                        color: Colors.white.withOpacity(0.15),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: _buildQueueItem(
                                  song: activeSong,
                                  index: 0,
                                  actualIndex: currentIndex,
                                  songs: songs,
                                  currentSong: currentSong,
                                  audioService: audioService,
                                  playlistHandler: playlistHandler,
                                  isNextUp: false,
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 16)),
                            ],
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
                                              color: Colors.white.withOpacity(0.4),
                                              size: 48,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              audioService.loopMode == LoopMode.one
                                                ? 'Current song on repeat'
                                                : 'No more songs in queue',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else ...[
                                    if (nextUpSongs.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Next Up',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                height: 1,
                                                width: 20,
                                                color: Colors.white.withOpacity(0.15),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SliverPadding(
                                        padding: EdgeInsets.zero,
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

                                    if (laterSongs.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Later',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                height: 1,
                                                width: 20,
                                                color: Colors.white.withOpacity(0.15),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SliverPadding(
                                        padding: EdgeInsets.zero,
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
                              ),
                            ),
                          );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildQueueHeader({
    required int trackCount,
    required bool isShuffling,
    required LoopMode loopMode,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      width: double.infinity,
      child: Row(
        children: [
          const Text(
            'Queue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (trackCount > 0) ...[
            if (isShuffling)
              Icon(
                Icons.shuffle,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              ),
            if (loopMode == LoopMode.all)
              Icon(
                Icons.repeat,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              )
            else if (loopMode == LoopMode.one)
              Icon(
                Icons.repeat_one,
                color: Colors.white.withOpacity(0.5),
                size: 14,
              ),
            if (loopMode != LoopMode.off || isShuffling)
              const SizedBox(width: 6),
            Text(
              '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
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
    final isCurrent = actualIndex == (audioService.player.currentIndex ?? -1);
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
      direction: isCurrent 
          ? DismissDirection.none
          : DismissDirection.endToStart,
      movementDuration: const Duration(milliseconds: 160),
      resizeDuration: const Duration(milliseconds: 160),
      confirmDismiss: (direction) async {
        if (isCurrent) {
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        if (isCurrent) return;
        final removedSong = song;
        final removedIndex = actualIndex;

        // Instantly remove from audio player queue
        await playlistHandler.removeFromSession(removedIndex);

        if (!mounted) return;
        _showUndoOverlay(
          song: removedSong,
          index: removedIndex,
          playlistHandler: playlistHandler,
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isCurrent ? 6 : 3,
        ),
        child: Builder(
          builder: (context) {
            final primaryColor = Theme.of(context).colorScheme.primary;
            final hsl = HSLColor.fromColor(primaryColor);
            // Derive a soft, playful pastel color dynamically
            final pastelColor = hsl.withSaturation(0.48).withLightness(0.82).toColor();

            return Material(
              color: isCurrent
                  ? pastelColor
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(isCurrent ? 16 : 12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('listile_${song.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                horizontalTitleGap: 12,
                onTap: () {
                  if (isCurrent) return; // Do nothing for currently active song
                  if (actualIndex >= 0 && actualIndex < songs.length) {
                    audioService.playQueueItem(actualIndex);
                  }
                },
                leading: Builder(
                  builder: (context) {
                    final isPlaying = isCurrent;
                    final artPath = song.albumArt ?? '';

                    Widget placeholder(Color color) => Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: color,
                          ),
                          child: isPlaying
                              ? Icon(Icons.music_note, color: isCurrent ? const Color(0xFF1D1B18) : Colors.white)
                              : Icon(
                                  isNextUp ? Icons.queue_music : Icons.music_note,
                                  color: (isCurrent ? const Color(0xFF1D1B18) : Colors.white).withOpacity(0.5),
                                ),
                        );

                    if (artPath.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(artPath),
                          height: 44,
                          width: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder(
                            isNextUp
                                ? Colors.white.withOpacity(0.12)
                                : Colors.white.withOpacity(0.06),
                          ),
                        ),
                      );
                    }

                    return placeholder(isCurrent
                        ? Colors.black.withOpacity(0.1)
                        : (isNextUp
                            ? Colors.white.withOpacity(0.12)
                            : Colors.white.withOpacity(0.06)));
                  },
                ),
                title: Text(
                  song.title,
                  style: TextStyle(
                    color: isCurrent ? const Color(0xFF1D1B18) : Colors.white.withOpacity(0.9),
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song.artist,
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF1D1B18).withOpacity(0.65)
                        : Colors.white.withOpacity(0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isCurrent
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ExpressiveProgressWrapper(
                          audioService: audioService,
                        ),
                      )
                    : audioService.isShuffling && !isNextUp
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.shuffle,
                              color: Colors.white.withOpacity(0.3),
                              size: 16,
                            ),
                          )
                        : ReorderableDragStartListener(
                            index: index,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Icon(
                                Icons.drag_handle,
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ),
              ),
            );
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

class AnimatedPlayPauseIcon extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  const AnimatedPlayPauseIcon({super.key, required this.isPlaying, required this.color});

  @override
  State<AnimatedPlayPauseIcon> createState() => _AnimatedPlayPauseIconState();
}

class _AnimatedPlayPauseIconState extends State<AnimatedPlayPauseIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    if (widget.isPlaying) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: _controller,
      color: widget.color,
      size: 20,
    );
  }
}

class ExpressiveProgressWrapper extends StatelessWidget {
  final AudioPlayerService audioService;
  const ExpressiveProgressWrapper({super.key, required this.audioService});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: EqualizerVisualizer(
        isPlaying: audioService.isPlaying,
        color: const Color(0xFF1D1B18),
      ),
    );
  }
}

class EqualizerVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const EqualizerVisualizer({
    super.key,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<EqualizerVisualizer> createState() => _EqualizerVisualizerState();
}

class _EqualizerVisualizerState extends State<EqualizerVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant EqualizerVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (index) {
              final double animatedValue;
              if (widget.isPlaying) {
                // Unique phase offset for each bar to look natural
                final double phase = (_controller.value * 2 * pi) + (index * pi / 1.5);
                animatedValue = 0.2 + (0.8 * (sin(phase).abs()));
              } else {
                // Resting state when paused
                animatedValue = 0.3;
              }

              return Container(
                width: 2.8,
                height: 14 * animatedValue,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}


