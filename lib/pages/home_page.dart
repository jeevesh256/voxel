import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/radio_station.dart';
import 'all_stations_page.dart';
import 'genre_stations_page.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../services/radio_browser_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Removed direct getter for audioService. Use context.watch or context.read everywhere.

  // List all radios in the top section, with a "See All" button
  Widget _buildRadioStationRow() {
    final validStations = _stations.where((station) {
      final streamUrl = station.streamUrl;
      return streamUrl.startsWith('https://') || streamUrl.startsWith('http://');
    }).toList();
    final topStations = validStations.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 270,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: topStations.length,
            itemBuilder: (context, index) {
              final station = topStations[index];
              final hasArt = station.artworkUrl.isNotEmpty;
              return GestureDetector(
                onTap: () => context.read<AudioPlayerService>().playRadioStation(station),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: hasArt
                                ? Image.network(
                                    station.artworkUrl,
                                    height: 200,
                                    width: 200,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 200,
                                      width: 200,
                                      color: Colors.deepPurple.shade200,
                                      child: const Icon(Icons.radio, color: Colors.white, size: 60),
                                    ),
                                  )
                                : Container(
                                    height: 200,
                                    width: 200,
                                    color: Colors.deepPurple.shade200,
                                    child: const Icon(Icons.radio, color: Colors.white, size: 60),
                                  ),
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.15),
                                    Colors.deepPurple.withOpacity(0.25),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AllStationsPage(stations: validStations),
                ),
              );
            },
            child: const Text('See All'),
          ),
        ),
      ],
    );
  }

  // Genre radios with only music genres, filterable by settings
  // Removed _showNonMusicGenres, now using Provider

  Widget _buildGenreRadioRow() {
    final validStations = _stations.where((station) {
      final streamUrl = station.streamUrl;
      return streamUrl.startsWith('https://') || streamUrl.startsWith('http://');
    }).toList();
    final settings = context.watch<SettingsModel>();
    
    // Simplified generic genres with artwork
    final Map<String, String> genreArtwork = {
      'Pop': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop',
      'Rock': 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=400&h=400&fit=crop',
      'Jazz': 'https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=400&h=400&fit=crop',
      'Classical': 'https://images.unsplash.com/photo-1507838153414-b4b713384a76?w=400&h=400&fit=crop',
      'Electronic': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400&h=400&fit=crop',
      'Hip-Hop': 'https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=400&h=400&fit=crop',
      'Country': 'https://images.unsplash.com/photo-1586348943529-beaae6c28db9?w=400&h=400&fit=crop',
      'Blues': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop',
      'Reggae': 'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=400&h=400&fit=crop',
      'Latin': 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=400&h=400&fit=crop',
      'News': 'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=400&h=400&fit=crop',
      'Talk': 'https://images.unsplash.com/photo-1589903308904-1010c2294adc?w=400&h=400&fit=crop',
      'Sports': 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=400&h=400&fit=crop',
    };
    
    final musicGenres = ['Jazz', 'Electronic', 'Classical', 'Pop', 'Country', 'Rock', 'Latin', 'Hip-Hop'];
    final nonMusicGenres = ['News', 'Talk', 'Sports'];
    final allGenres = settings.showNonMusicGenres ? [...musicGenres, ...nonMusicGenres] : musicGenres;
    
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
    final displayedGenres = allGenres.where((genre) => genreMap.containsKey(genre)).toList();
    return SizedBox(
      height: 270,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: displayedGenres.length,
        itemBuilder: (context, index) {
          final genre = displayedGenres[index];
          final stations = genreMap[genre]!;
          final artworkUrl = genreArtwork[genre] ?? 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop';
          
          return GestureDetector(
            onTap: () {
              // Navigate to genre stations page instead of playing first station
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GenreStationsPage(
                    genre: genre,
                    stations: stations,
                  ),
                ),
              );
            },
            child: Container(
              width: 200,
              margin: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          artworkUrl,
                          height: 200,
                          width: 200,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            width: 200,
                            color: Colors.deepPurple.shade200,
                            child: const Icon(Icons.radio, color: Colors.white, size: 60),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Colors.deepPurple.withOpacity(0.25),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

    setState(() {
      _stations = stations;
    });
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
          backgroundColor: Colors.black,
          title: Row(
            children: [
              Text(
                'Listen Now',
                style: TextStyle(
                  color: Colors.deepPurple.shade200,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection('Radio Stations'),
              _buildRadioStationRow(),
              _buildSection('Genre Radios'),
              _buildGenreRadioRow(),
              _buildSection('Top Picks'),
              _buildMusicRow(),
              _buildSection('Recently Played'),
              _buildMusicRow(),
              const SizedBox(height: 120), // Add padding for mini player
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Removed old _buildRadioStationRow (language filter)

  Widget _buildMusicRow() {
    return SizedBox(
      height: 270,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.deepPurple.shade400,
                        Colors.deepPurple.shade800,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Album Title ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Artist Name',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper method to match genres with common variations
  bool _isGenreMatch(String stationGenre, String targetGenre) {
    switch (targetGenre) {
      case 'pop':
        return stationGenre.contains('pop') || stationGenre.contains('top 40') || stationGenre.contains('hits');
      case 'rock':
        return stationGenre.contains('rock') || stationGenre.contains('metal') || stationGenre.contains('alternative');
      case 'electronic':
        return stationGenre.contains('electronic') || stationGenre.contains('dance') || stationGenre.contains('edm') || stationGenre.contains('techno') || stationGenre.contains('house');
      case 'hip-hop':
        return stationGenre.contains('hip') || stationGenre.contains('rap') || stationGenre.contains('r&b') || stationGenre.contains('rnb');
      case 'jazz':
        return stationGenre.contains('jazz') || stationGenre.contains('smooth') || stationGenre.contains('soul');
      case 'classical':
        return stationGenre.contains('classical') || stationGenre.contains('symphony') || stationGenre.contains('opera');
      case 'country':
        return stationGenre.contains('country') || stationGenre.contains('folk') || stationGenre.contains('americana');
      case 'blues':
        return stationGenre.contains('blues') || stationGenre.contains('rhythm');
      case 'reggae':
        return stationGenre.contains('reggae') || stationGenre.contains('ska') || stationGenre.contains('caribbean');
      case 'latin':
        return stationGenre.contains('latin') || stationGenre.contains('spanish') || stationGenre.contains('salsa') || stationGenre.contains('bachata');
      case 'news':
        return stationGenre.contains('news') || stationGenre.contains('current');
      case 'talk':
        return stationGenre.contains('talk') || stationGenre.contains('discussion') || stationGenre.contains('interview');
      case 'sports':
        return stationGenre.contains('sports') || stationGenre.contains('football') || stationGenre.contains('basketball');
      default:
        return false;
    }
  }
}
