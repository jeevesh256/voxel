import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/radio_station.dart';
import 'all_stations_page.dart';
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
    final musicGenres = [
      'Pop', 'Rock', 'Jazz', 'Classical', 'Hip-Hop', 'Dance', 'Electronic', 'Country', 'Reggae', 'Blues',
      'Soul', 'Folk', 'Metal', 'Alternative', 'R&B', 'Latin', 'Oldies', 'Top 40'
    ];
    final nonMusicGenres = ['News', 'Talk', 'Sports'];
    final allGenres = settings.showNonMusicGenres ? [...musicGenres, ...nonMusicGenres] : musicGenres;
    final genreMap = <String, List<RadioStation>>{};
    for (var station in validStations) {
      final genres = station.genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty);
      for (var genre in genres) {
        if (allGenres.any((cg) => genre.toLowerCase().contains(cg.toLowerCase()))) {
          genreMap.putIfAbsent(genre, () => []).add(station);
        }
      }
    }
    final displayedGenres = genreMap.keys.toList();
    return SizedBox(
      height: 270,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: displayedGenres.length,
        itemBuilder: (context, index) {
          final genre = displayedGenres[index];
          final stations = genreMap[genre]!;
          final station = stations.first;
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
                    station.name,
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
}
// ...existing code...
