import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/radio_browser_service.dart';
import '../models/radio_station.dart';
import 'dart:async';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';
  List<RadioStation> _stations = [];
  bool _loadingStations = false;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Don't fetch stations on init - only when user searches
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStations([String? query]) async {
    if (!mounted) return; // Check if widget is still mounted
    
    // Only fetch if there's actually a query
    if (query == null || query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _stations = [];
          _loadingStations = false;
        });
      }
      return;
    }
    
    setState(() => _loadingStations = true);
    final radioService = RadioBrowserService();
    final stations = await radioService.fetchStations(
      genre: query,
      limit: 20,
    );
    
    if (!mounted) return; // Check again before calling setState
    
    setState(() {
      _stations = stations;
      _loadingStations = false;
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchController.text = value;
    
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    // Only search if there's text, with a 500ms debounce
    if (value.trim().isNotEmpty) {
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _fetchStations(value);
      });
    } else {
      // Clear results immediately if search is empty
      setState(() {
        _stations = [];
        _loadingStations = false;
      });
    }
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
                controller: _searchController,
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
                  _onSearchChanged(value);
                },
              ),
            ),
          ),
        ),
        if (_loadingStations)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.deepPurple.shade300,
                  ),
                ),
              ),
            ),
          ),
        if (_query.isNotEmpty && !_loadingStations && _stations.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
              child: Text(
                'Stations',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        if (_query.isNotEmpty && !_loadingStations && _stations.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.radio,
                      size: 40,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No stations found',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_query.isNotEmpty && !_loadingStations && _stations.isNotEmpty)
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
          padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
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
      (Colors.deepPurple, 'Jazz'),
      (Colors.blue, 'Dance'),
      (Colors.pink, 'Hip-Hop'),
      (Colors.orange, 'Rock'),
      (Colors.teal, 'Chill'),
      (Colors.red, 'Pop'),
    ];

    return GestureDetector(
      onTap: () {
        _onSearchChanged(categories[index].$2);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              categories[index].$1[400]!.withOpacity(0.8),
              categories[index].$1[600]!.withOpacity(0.9),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: categories[index].$1[700]!.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            categories[index].$2,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
