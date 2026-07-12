import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/radio_station.dart';
import 'all_stations_page.dart';
import 'genre_stations_page.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../services/radio_browser_service.dart';
import '../services/radio_playback_guard.dart';
import '../widgets/voxel_toast.dart';
import 'playlist_page.dart'; // <-- Missing import added here
import 'package:voxel/models/custom_playlist.dart';

void pushMaterialPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          RepaintBoundary(child: page),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        ));
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _HomeTileMetrics _homeTileMetrics(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tileWidth = ((screenWidth - 32.0) * 0.42).clamp(136.0, 168.0);
    final textScale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.3);
    final rowHeight = tileWidth + 70.0 + ((textScale - 1.0) * 10.0);

    return _HomeTileMetrics(
      tileWidth: tileWidth,
      tileImageSize: tileWidth,
      rowHeight: rowHeight,
    );
  }
  // Removed direct getter for audioService. Use context.watch or context.read everywhere.

  // List all radios in the top section, with a "See All" button
  Widget _buildRadioStationRow() {
    final metrics = _homeTileMetrics(context);
    final validStations = _stations.where((station) {
      final streamUrl = station.streamUrl;
      return streamUrl.startsWith('https://') ||
          streamUrl.startsWith('http://');
    }).toList();
    final topStations = validStations.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Radio Stations',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    pushMaterialPage(context, AllStationsPage(stations: validStations)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'See all',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: metrics.rowHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: topStations.length,
            itemBuilder: (context, index) {
              final station = topStations[index];
              final hasArt = _isValidArtwork(station.artworkUrl);
              return GestureDetector(
                onTap: () async {
                  final blockReason =
                      await RadioPlaybackGuard.blockingMessage();
                  if (blockReason != null) {
                    final bottomPad = MediaQuery.of(context).padding.bottom + 8.0;
                    VoxelToast.show(
                      context,
                      blockReason,
                      bottomPadding: bottomPad,
                    );
                    return;
                  }
                  context.read<AudioPlayerService>().playRadioStation(station);
                },
                child: Container(
                  width: metrics.tileWidth,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: hasArt
                            ? CachedNetworkImage(
                                imageUrl: station.artworkUrl,
                                height: metrics.tileImageSize,
                                width: metrics.tileImageSize,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                errorWidget: (_, __, ___) => Container(
                                  height: metrics.tileImageSize,
                                  width: metrics.tileImageSize,
                                  color: const Color(0xFF6A5B8E),
                                  child: const Icon(Icons.radio,
                                      color: Colors.white, size: 60),
                                ),
                                placeholder: (_, __) => Container(
                                  height: metrics.tileImageSize,
                                  width: metrics.tileImageSize,
                                  color: const Color(0xFF2A1A3A),
                                ),
                              )
                            : Container(
                                height: metrics.tileImageSize,
                                width: metrics.tileImageSize,
                                color: const Color(0xFF6A5B8E),
                                child: const Icon(Icons.radio,
                                    color: Colors.white, size: 60),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        station.genre,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Genre radios with only music genres, filterable by settings
  // Removed _showNonMusicGenres, now using Provider

  Widget _buildGenreRadioRow() {
    final metrics = _homeTileMetrics(context);
    final validStations = _stations.where((station) {
      final streamUrl = station.streamUrl;
      return streamUrl.startsWith('https://') ||
          streamUrl.startsWith('http://');
    }).toList();
    // Simplified generic genres with artwork
    final Map<String, String> genreArtwork = {
      'Pop':
          'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop',
      'Rock':
          'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=400&h=400&fit=crop',
      'Jazz':
          'https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=400&h=400&fit=crop',
      'Classical':
          'https://images.unsplash.com/photo-1507838153414-b4b713384a76?w=400&h=400&fit=crop',
      'Electronic':
          'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400&h=400&fit=crop',
      'Hip-Hop':
          'https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=400&h=400&fit=crop',
      'Country':
          'https://images.unsplash.com/photo-1586348943529-beaae6c28db9?w=400&h=400&fit=crop',
      'Blues':
          'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop',
      'Reggae':
          'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=400&h=400&fit=crop',
      'Latin':
          'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=400&h=400&fit=crop',
      'News':
          'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=400&h=400&fit=crop',
      'Talk':
          'https://images.unsplash.com/photo-1589903308904-1010c2294adc?w=400&h=400&fit=crop',
      'Sports':
          'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=400&h=400&fit=crop',
    };

    final musicGenres = [
      'Jazz',
      'Electronic',
      'Classical',
      'Pop',
      'Country',
      'Rock',
      'Latin',
      'Hip-Hop'
    ];
    final allGenres = musicGenres;

    final genreMap = <String, List<RadioStation>>{};

    // Map stations to simplified genres
    for (var station in validStations) {
      final stationGenre = station.genre.toLowerCase();
      for (var genre in allGenres) {
        if (stationGenre.contains(genre.toLowerCase()) ||
            _isGenreMatch(stationGenre, genre.toLowerCase())) {
          genreMap.putIfAbsent(genre, () => []).add(station);
          break; // Only add to first matching genre to avoid duplicates
        }
      }
    }

    // Use the defined order from allGenres, only including genres that have stations
    final displayedGenres =
        allGenres.where((genre) => genreMap.containsKey(genre)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('Genre Radios'),
        SizedBox(
          height: metrics.rowHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: displayedGenres.length,
            itemBuilder: (context, index) {
              final genre = displayedGenres[index];
              final stations = genreMap[genre]!;
              final artworkUrl = genreArtwork[genre] ??
                  'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop';

              return GestureDetector(
                onTap: () {
                  // Navigate to genre stations page with Cupertino transition
                  pushMaterialPage(
                    context,
                    GenreStationsPage(
                      genre: genre,
                      stations: stations,
                    ),
                  );
                },
                child: Container(
                  width: metrics.tileWidth,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: artworkUrl,
                          height: metrics.tileImageSize,
                          width: metrics.tileImageSize,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorWidget: (_, __, ___) => Container(
                            height: metrics.tileImageSize,
                            width: metrics.tileImageSize,
                            color: const Color(0xFF6A5B8E),
                            child: const Icon(Icons.radio,
                                color: Colors.white, size: 60),
                          ),
                          placeholder: (_, __) => Container(
                            height: metrics.tileImageSize,
                            width: metrics.tileImageSize,
                            color: const Color(0xFF2A1A3A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        genre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stations.length} stations',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Removed unused _selectedGenre
  List<RadioStation> _stations = [];
  // Removed unused _genres, _loadingGenres, and _loadingStations
  final RadioBrowserService _radioService = RadioBrowserService();

  @override
  void initState() {
    super.initState();
    _initGenresAndStations();
  }

  Future<void> _initGenresAndStations() async {
    // Fetch genres and top stations in parallel
    final genresFuture = _radioService.fetchGenres();
    final stationsFuture = _radioService.fetchTopStations(limit: 200);

    await genresFuture;
    final stations = await stationsFuture;

    if (mounted) {
      setState(() {
        _stations = stations;
      });
    }
  }

  // Removed unused _fetchStations

  // List<RadioStation> get _filteredStations => _stations;

  @override
  Widget build(BuildContext context) {
    // Use context.watch everywhere for consistency
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          toolbarHeight: 68,
          title: const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 0, 0),
            child: Text(
              'Listen Now',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRecentlyPlayedRow(),
              _buildRadioStationRow(),
              _buildGenreRadioRow(),
              _buildForYouRow(),
              SizedBox(height: MediaQuery.of(context).padding.bottom), // Add padding for mini player
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  // --- For You Row (Liked Songs Playlist) ---
  Widget _buildForYouRow() {
    final metrics = _homeTileMetrics(context);
    final audioService = context.watch<AudioPlayerService>();
    final likedFiles = audioService.getPlaylistSongs('liked').reversed.toList();
    final customPlaylists = audioService.customPlaylists;

    final items = <_RecentlyPlayedItem>[];

    if (likedFiles.isNotEmpty) {
      items.add(
        _RecentlyPlayedItem(
          title: 'Liked Songs',
          subtitle: '${likedFiles.length} song${likedFiles.length == 1 ? '' : 's'}',
          icon: Icons.favorite,
          color: Colors.deepPurple.shade200,
          onTap: () {
            pushMaterialPage(
              context,
              PlaylistPage(
                playlistId: 'liked',
                title: 'Liked Songs',
                icon: Icons.favorite,
                allowReorder: true,
              ),
            );
          },
        ),
      );
    }

    for (final playlist in customPlaylists) {
      final songs = audioService.getPlaylistSongs(playlist.id);
      if (songs.isEmpty) continue;

      items.add(
        _RecentlyPlayedItem(
          title: playlist.name,
          subtitle: '${songs.length} song${songs.length == 1 ? '' : 's'}',
          icon: Icons.queue_music,
          color: playlist.artworkColor != null
              ? Color(playlist.artworkColor!)
              : const Color(0xFF80CBC4),
          imagePath: playlist.artworkPath,
          onTap: () {
            pushMaterialPage(
              context,
              PlaylistPage(
                playlistId: playlist.id,
                title: playlist.name,
                icon: Icons.queue_music,
                allowReorder: true,
              ),
            );
          },
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('For You'),
        SizedBox(
          height: metrics.rowHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length > 10 ? 10 : items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: item.onTap,
                child: Container(
                  width: metrics.tileWidth,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      item.imagePath != null && item.imagePath!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(item.imagePath!),
                                height: metrics.tileImageSize,
                                width: metrics.tileImageSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: metrics.tileImageSize,
                                  width: metrics.tileImageSize,
                                  color: item.color,
                                  child: Icon(item.icon,
                                      color: Colors.white, size: 60),
                                ),
                              ),
                            )
                          : Container(
                              height: metrics.tileImageSize,
                              width: metrics.tileImageSize,
                              decoration: BoxDecoration(
                                color: item.color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(item.icon,
                                  color: Colors.white, size: 60),
                            ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Recently Played Row ---
  Widget _buildRecentlyPlayedRow() {
    final metrics = _homeTileMetrics(context);
    final audioService = context.watch<AudioPlayerService>();
    final List<_RecentlyPlayedItem> items = [];
    // Use the new recently played playlist IDs for ordering
    for (final playlistId in audioService.recentlyPlayedPlaylistIds) {
      if (playlistId == 'liked') {
        final likedFiles = audioService.getPlaylistSongs('liked');
        if (likedFiles.isNotEmpty) {
          items.add(_RecentlyPlayedItem(
            title: 'Liked Songs',
            subtitle:
                '${likedFiles.length} song${likedFiles.length == 1 ? '' : 's'}',
            icon: Icons.favorite,
            color: Colors.deepPurple.shade200,
            onTap: () {
              pushMaterialPage(
                context,
                PlaylistPage(
                  playlistId: 'liked',
                  title: 'Liked Songs',
                  icon: Icons.favorite,
                  allowReorder: true,
                ),
              );
            },
          ));
        }
      } else {
        final playlist = audioService.customPlaylists.firstWhere(
          (p) => p.id == playlistId,
          orElse: () => CustomPlaylist(
            id: '',
            name: '',
            songPaths: const [],
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        if (playlist.id.isNotEmpty) {
          final songs = audioService.getPlaylistSongs(playlist.id);
          if (songs.isNotEmpty) {
            items.add(_RecentlyPlayedItem(
              title: playlist.name,
              subtitle: '${songs.length} song${songs.length == 1 ? '' : 's'}',
              icon: Icons.queue_music,
              color: playlist.artworkColor != null
                  ? Color(playlist.artworkColor!)
                  : const Color(0xFF80CBC4),
              imagePath: playlist.artworkPath,
              onTap: () {
                pushMaterialPage(
                  context,
                  PlaylistPage(
                    playlistId: playlist.id,
                    title: playlist.name,
                    icon: Icons.queue_music,
                    allowReorder: true,
                  ),
                );
              },
            ));
          }
        }
      }
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('Recently Played'),
        SizedBox(
          height: metrics.rowHeight,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length > 10 ? 10 : items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: item.onTap,
                child: Container(
                  width: metrics.tileWidth,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      item.imagePath != null && item.imagePath!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(item.imagePath!),
                                height: metrics.tileImageSize,
                                width: metrics.tileImageSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: metrics.tileImageSize,
                                  width: metrics.tileImageSize,
                                  color: item.color,
                                  child: Icon(item.icon,
                                      color: Colors.white, size: 60),
                                ),
                              ),
                            )
                          : Container(
                              height: metrics.tileImageSize,
                              width: metrics.tileImageSize,
                              decoration: BoxDecoration(
                                color: item.color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(item.icon,
                                  color: Colors.white, size: 60),
                            ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// Helper class for recently played items
class _RecentlyPlayedItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? imagePath;
  final VoidCallback onTap;
  _RecentlyPlayedItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.imagePath,
    required this.onTap,
  });
}

class _HomeTileMetrics {
  const _HomeTileMetrics({
    required this.tileWidth,
    required this.tileImageSize,
    required this.rowHeight,
  });

  final double tileWidth;
  final double tileImageSize;
  final double rowHeight;
}

bool _isValidArtwork(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final thumbParam = uri.queryParameters['t']?.toLowerCase() ?? '';

  // These Google thumbnail URLs are often short-lived and return 404s.
  if (host.startsWith('encrypted-tbn') && host.endsWith('gstatic.com')) {
    return false;
  }

  // Known station-logo CDN entries that frequently fail DNS resolution.
  if (host == 'de8as167a043l.cloudfront.net' ||
      path.contains('/styles/images/logosplus/')) {
    return false;
  }

  // Some laut.fm thumbnail variants are unstable and frequently return 404.
  if (host == 'assets.laut.fm' && thumbParam.startsWith('_')) {
    return false;
  }

  // Reject generic /icon.png and favicon-like paths that often return HTTP errors
  if (path.endsWith('/icon.png') ||
      path.endsWith('/icon.ico') ||
      path.endsWith('/favicon.ico')) {
    return false;
  }

  if (path.contains('favicon')) {
    return false;
  }

  return host.isNotEmpty &&
      !path.endsWith('.ico') &&
      !path.endsWith('.svg') &&
      !path.endsWith('.bmp');
}

bool _isGenreMatch(String stationGenre, String targetGenre) {
  switch (targetGenre) {
    case 'pop':
      return stationGenre.contains('pop') ||
          stationGenre.contains('top 40') ||
          stationGenre.contains('hits');
    case 'rock':
      return stationGenre.contains('rock') ||
          stationGenre.contains('metal') ||
          stationGenre.contains('alternative');
    case 'electronic':
      return stationGenre.contains('electronic') ||
          stationGenre.contains('dance') ||
          stationGenre.contains('edm') ||
          stationGenre.contains('techno') ||
          stationGenre.contains('house');
    case 'hip-hop':
      return stationGenre.contains('hip') ||
          stationGenre.contains('rap') ||
          stationGenre.contains('r&b') ||
          stationGenre.contains('rnb');
    case 'jazz':
      return stationGenre.contains('jazz') ||
          stationGenre.contains('smooth') ||
          stationGenre.contains('soul');
    case 'classical':
      return stationGenre.contains('classical') ||
          stationGenre.contains('symphony') ||
          stationGenre.contains('opera');
    case 'country':
      return stationGenre.contains('country') ||
          stationGenre.contains('folk') ||
          stationGenre.contains('americana');
    case 'blues':
      return stationGenre.contains('blues') || stationGenre.contains('rhythm');
    case 'reggae':
      return stationGenre.contains('reggae') ||
          stationGenre.contains('ska') ||
          stationGenre.contains('caribbean');
    case 'latin':
      return stationGenre.contains('latin') ||
          stationGenre.contains('spanish') ||
          stationGenre.contains('salsa') ||
          stationGenre.contains('bachata');
    case 'news':
      return stationGenre.contains('news') || stationGenre.contains('current');
    case 'talk':
      return stationGenre.contains('talk') ||
          stationGenre.contains('discussion') ||
          stationGenre.contains('interview');
    case 'sports':
      return stationGenre.contains('sports') ||
          stationGenre.contains('football') ||
          stationGenre.contains('basketball');
    default:
      return false;
  }
}
