import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import 'dart:io';
import 'playlist_page.dart';
import 'favourite_radios_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final StorageService _storageService = StorageService();
  List<FileSystemEntity> _audioFiles = [];

  @override
  void initState() {
    super.initState();
    _loadAudioFiles();
  }

  Future<void> _loadAudioFiles() async {
    try {
      final entities = await _storageService.getAudioFiles();
      final files = entities.whereType<File>().toList();

      if (mounted) {
        setState(() {
          _audioFiles = files;
        });
        // Load files into offline playlist
        context.read<AudioPlayerService>().loadOfflineFiles(files);
      }
    } catch (e) {
      if (mounted) {
        // Error handling - could show a snackbar or error message
        debugPrint('Error loading audio files: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Favourite Radios'),
            ],
            indicatorColor: Colors.deepPurple.shade400,
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlaylistsView(),
            _buildArtistsView(),
            _buildFavouriteRadiosView(),
          ],
        ),
      ),
    );
  // ...existing code...
  }

  Widget _buildFavouriteRadiosView() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Consumer<AudioPlayerService>(
        builder: (context, audioService, child) {
          final radios = audioService.getPlaylistRadios('favourite_radios');
          
          if (radios.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.radio,
                    size: 64,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No favourite radios yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add stations to your favourites by tapping the heart icon',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header with view all button (only if needed)
              if (radios.length > 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${radios.length} stations',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const FavouriteRadiosPage(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.arrow_forward,
                          color: Colors.deepPurple.shade400,
                          size: 16,
                        ),
                        label: Text(
                          'View All',
                          style: TextStyle(
                            color: Colors.deepPurple.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Show first 3-5 radios or all if less than 6
              Expanded(
                child: ListView.builder(
                  itemCount: radios.length > 5 ? 5 : radios.length,
                  itemBuilder: (context, index) {
                    final radio = radios[index];
                    final hasArt = radio.artworkUrl.isNotEmpty;
                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: hasArt
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  radio.artworkUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 48,
                                    height: 48,
                                    color: Colors.deepPurple.shade200,
                                    child: const Icon(Icons.radio, color: Colors.white, size: 24),
                                  ),
                                ),
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.radio, color: Colors.white, size: 24),
                              ),
                        title: Text(
                          radio.name,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Flexible(
                              child: Text(
                                radio.genre,
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (radio.country.isNotEmpty) ...[
                              Text(
                                ' • ',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                              Flexible(
                                child: Text(
                                  radio.country,
                                  style: TextStyle(color: Colors.grey[400]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.favorite,
                            color: Colors.deepPurple.shade400,
                            size: 20,
                          ),
                          tooltip: 'Remove from favourites',
                          onPressed: () {
                            // Show confirmation dialog for better UX
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  backgroundColor: Colors.grey[900],
                                  title: Text(
                                    'Remove from favourites?',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Remove "${radio.name}" from your favourite radios?',
                                    style: TextStyle(color: Colors.grey[300]),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.grey[400]),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        audioService.removeRadioFromPlaylist('favourite_radios', radio);
                                        Navigator.of(context).pop();
                                      },
                                      child: Text(
                                        'Remove',
                                        style: TextStyle(color: Colors.deepPurple.shade400),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        onTap: () => audioService.playRadioStation(radio),
                      ),
                    );
                  },
                ),
              ),
              // Add spacing for mini player
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsView() {
    final audioService = context.watch<AudioPlayerService>();
    final playlists = audioService.allPlaylists;
    // Show liked songs in stack order (newest first)
    final likedSongs = List<File>.from(playlists.firstWhere(
      (e) => e.key == 'liked',
      orElse: () => const MapEntry('liked', []),
    ).value.reversed);
    return ListView(
      children: [
        _buildPlaylistTile(
          title: 'Liked Songs',
          icon: Icons.favorite,
          playlistId: 'liked',
          songs: likedSongs,
        ),
        _buildPlaylistTile(
          title: 'Offline',
          icon: Icons.offline_pin,
          playlistId: 'offline',
          songs: playlists.firstWhere(
            (e) => e.key == 'offline',
            orElse: () => const MapEntry('offline', []),
          ).value,
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildPlaylistTile({
    required String title,
    required IconData icon,
    required String playlistId,
    required List<File> songs,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Colors.deepPurple.shade400,
      ),
      title: Text(title),
      subtitle: Text('${songs.length} songs'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistPage(
              playlistId: playlistId,
              title: title,
              icon: icon,
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsView() {
    final artistMap = <String, List<File>>{};
    
    for (var file in _audioFiles.whereType<File>()) {
      final name = file.path.split('/').last;
      final artist = name.split(' - ').first;
      artistMap.putIfAbsent(artist, () => []).add(file);
    }

    final sortedArtists = artistMap.keys.toList()..sort();

    return ListView.builder(
      itemCount: sortedArtists.length,
      itemBuilder: (context, index) {
        final artist = sortedArtists[index];
        final songs = artistMap[artist]!;
        
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(artist),
          subtitle: Text('${songs.length} songs'),
          onTap: () => context.read<AudioPlayerService>().playFiles(songs),
        );
      },
    );
  }
}
