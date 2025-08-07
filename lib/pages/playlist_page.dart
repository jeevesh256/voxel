import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:io';

enum SortOption { name, dateAdded, artist }

class PlaylistPage extends StatefulWidget {
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
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  String _searchQuery = '';
  SortOption _sortOption = SortOption.dateAdded;
  bool _isAscending = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<File> _getFilteredAndSortedSongs(List<File> songs) {
    // Filter by search query
    List<File> filteredSongs = songs.where((file) {
      final name = file.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort songs
    switch (_sortOption) {
      case SortOption.name:
        filteredSongs.sort((a, b) {
          final nameA = a.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
          final nameB = b.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
      case SortOption.dateAdded:
        // For liked songs, maintain stack order (newest first) unless ascending is selected
        if (widget.playlistId == 'liked') {
          if (_isAscending) {
            filteredSongs = filteredSongs.reversed.toList();
          }
        } else {
          filteredSongs.sort((a, b) {
            final statA = a.statSync();
            final statB = b.statSync();
            return _isAscending 
                ? statA.modified.compareTo(statB.modified)
                : statB.modified.compareTo(statA.modified);
          });
        }
        break;
      case SortOption.artist:
        // Since we don't have artist metadata, sort by filename
        filteredSongs.sort((a, b) {
          final nameA = a.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
          final nameB = b.path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
          return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        });
        break;
    }

    return filteredSongs;
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final allSongs = audioService.getPlaylistSongs(widget.playlistId);
    final songs = _getFilteredAndSortedSongs(allSongs);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.title),
              background: Container(
                color: Colors.deepPurple.shade400,
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            actions: [
              if (!_isSearching)
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                    });
                  },
                ),
              if (_isSearching)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                ),
            ],
          ),
          // Search Bar (only when searching)
          if (_isSearching)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search songs...',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    Container(
                      height: 48,
                      width: 1,
                      color: Colors.grey[700],
                      margin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    PopupMenuButton<SortOption>(
                      color: Colors.grey[900],
                      icon: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.sort,
                          color: Colors.deepPurple.shade400,
                          size: 20,
                        ),
                      ),
                      tooltip: 'Sort options',
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: SortOption.name,
                          child: Row(
                            children: [
                              Icon(
                                Icons.sort_by_alpha,
                                color: _sortOption == SortOption.name ? Colors.deepPurple.shade400 : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Name',
                                  style: TextStyle(
                                    color: _sortOption == SortOption.name ? Colors.deepPurple.shade400 : Colors.white,
                                    fontWeight: _sortOption == SortOption.name ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_sortOption == SortOption.name)
                                Icon(
                                  _isAscending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: Colors.deepPurple.shade400,
                                ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: SortOption.dateAdded,
                          child: Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                color: _sortOption == SortOption.dateAdded ? Colors.deepPurple.shade400 : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Date Added',
                                  style: TextStyle(
                                    color: _sortOption == SortOption.dateAdded ? Colors.deepPurple.shade400 : Colors.white,
                                    fontWeight: _sortOption == SortOption.dateAdded ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_sortOption == SortOption.dateAdded)
                                Icon(
                                  _isAscending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: Colors.deepPurple.shade400,
                                ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: SortOption.artist,
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                color: _sortOption == SortOption.artist ? Colors.deepPurple.shade400 : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Artist',
                                  style: TextStyle(
                                    color: _sortOption == SortOption.artist ? Colors.deepPurple.shade400 : Colors.white,
                                    fontWeight: _sortOption == SortOption.artist ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_sortOption == SortOption.artist)
                                Icon(
                                  _isAscending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: Colors.deepPurple.shade400,
                                ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        setState(() {
                          if (_sortOption == value) {
                            _isAscending = !_isAscending;
                          } else {
                            _sortOption = value;
                            _isAscending = false;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          // Play All Button
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, _isSearching ? 0 : 16, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: songs.isEmpty ? null : () {
                    audioService.playPlaylist(widget.playlistId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text('Play All (${songs.length} songs)'),
                ),
              ),
            ),
          ),
          // Songs List
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
                      trailing: PopupMenuButton(
                        color: Colors.grey[900],
                        icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Text('Remove from playlist', style: TextStyle(color: Colors.white)),
                            onTap: () {
                              // Remove from playlist logic could go here
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        audioService.playFileInContext(file, allSongs);
                      },
                    );
                  },
                );
              },
              childCount: songs.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + // Device bottom padding
                        kBottomNavigationBarHeight + // Navigation bar height (usually 56)
                        60.0, // Mini player height
              ),
            ),
          ),
        ],
      ),
    );
  }
}
