import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/radio_browser_service.dart';
import '../models/radio_station.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';
  List<RadioStation> _stations = [];
  bool _loadingStations = false;

  @override
  void initState() {
    super.initState();
    _fetchStations();
  }

  Future<void> _fetchStations([String? query]) async {
    setState(() => _loadingStations = true);
    final radioService = RadioBrowserService();
    final stations = await radioService.fetchStations(
      genre: query,
      limit: 20,
    );
    setState(() {
      _stations = stations;
      _loadingStations = false;
    });
  }

  List<RadioStation> get _filteredStations => _query.isEmpty
      ? _stations
      : _stations.where((s) =>
          s.name.toLowerCase().contains(_query.toLowerCase()) ||
          s.genre.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.black,
          title: Text(
            'Search',
            style: TextStyle(
              color: Colors.deepPurple.shade200,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Artists, Songs, Radio Stations, and More',
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.grey,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _query = value);
                  _fetchStations(value);
                },
              ),
            ),
          ),
        ),
        if (_loadingStations)
          const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_query.isNotEmpty && !_loadingStations)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Radio Stations',
                style: TextStyle(
                  color: Colors.deepPurple.shade200,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (_query.isNotEmpty && !_loadingStations)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final station = _filteredStations[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: station.artworkUrl.isNotEmpty
                      ? Image.network(
                          station.artworkUrl,
                          height: 40,
                          width: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 40,
                            width: 40,
                            color: Colors.deepPurple.shade200,
                            child: const Icon(Icons.radio, color: Colors.white),
                          ),
                        )
                      : Container(
                          height: 40,
                          width: 40,
                          color: Colors.deepPurple.shade200,
                          child: const Icon(Icons.radio, color: Colors.white),
                        ),
                  ),
                  title: Text(
                    station.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    station.genre,
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  onTap: () => audioService.playRadioStation(station),
                );
              },
              childCount: _filteredStations.length,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildCategoryCard(index),
              childCount: 6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(int index) {
    final List<(MaterialColor, String)> categories = [
      (Colors.deepPurple, 'Charts'),
      (Colors.blue, 'Dance'),
      (Colors.pink, 'Hip-Hop'),
      (Colors.orange, 'Rock'),
      (Colors.teal, 'Chill'),
      (Colors.red, 'Pop'),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            categories[index].$1[300]!,
            categories[index].$1[700]!,
          ],
        ),
      ),
      child: Center(
        child: Text(
          categories[index].$2,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
