import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../models/playlist_model.dart';
import '../models/favourite_radios_model.dart';
import '../models/radio_station.dart';
import '../services/playlist_handler.dart';
import 'dart:io';
import 'playlist_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final StorageService _storageService = StorageService();
  List<FileSystemEntity> _audioFiles = [];
  bool _isLoading = true;
  String? _error;

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
          _isLoading = false;
        });
        // Load files into offline playlist
        context.read<AudioPlayerService>().loadOfflineFiles(files);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatFileName(String path) {
    final name = path.split('/').last;
    return name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$'), '');
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
    final audioService = Provider.of<AudioPlayerService>(context);
    final radios = audioService.getPlaylistRadios('favourite_radios');
    if (radios.isEmpty) {
      return Center(
        child: Text('No favourite radios yet', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
      );
    }
    return ListView.builder(
      itemCount: radios.length,
      itemBuilder: (context, index) {
        final radio = radios[index];
        final hasArt = radio.artworkUrl.isNotEmpty;
        return ListTile(
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
          title: Text(radio.name),
          subtitle: Text(radio.genre),
          trailing: IconButton(
            icon: Icon(Icons.favorite, color: Colors.deepPurple.shade400),
            onPressed: () => audioService.removeRadioFromPlaylist('favourite_radios', radio),
          ),
          onTap: () => audioService.playRadioStation(radio),
        );
      },
    );
  }

  Widget _buildPlaylistsView() {
    final audioService = context.watch<AudioPlayerService>();
    final playlists = audioService.allPlaylists;

    return ListView(
      children: [
        _buildPlaylistTile(
          title: 'Liked Songs',
          icon: Icons.favorite,
          playlistId: 'liked',
          songs: playlists.firstWhere(
            (e) => e.key == 'liked',
            orElse: () => const MapEntry('liked', []),
          ).value,
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
