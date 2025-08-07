import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../models/radio_station.dart';

enum RadioSortOption { name, genre, country, dateAdded }

class FavouriteRadiosPage extends StatefulWidget {
  const FavouriteRadiosPage({super.key});

  @override
  State<FavouriteRadiosPage> createState() => _FavouriteRadiosPageState();
}

class _FavouriteRadiosPageState extends State<FavouriteRadiosPage> {
  String _searchQuery = '';
  RadioSortOption _sortOption = RadioSortOption.dateAdded;
  bool _isAscending = false;

  List<RadioStation> _getFilteredAndSortedRadios(List<RadioStation> radios) {
    // Filter by search query
    List<RadioStation> filteredRadios = radios.where((radio) {
      return radio.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             radio.genre.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             radio.country.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort radios
    switch (_sortOption) {
      case RadioSortOption.name:
        filteredRadios.sort((a, b) {
          return _isAscending ? a.name.compareTo(b.name) : b.name.compareTo(a.name);
        });
        break;
      case RadioSortOption.genre:
        filteredRadios.sort((a, b) {
          return _isAscending ? a.genre.compareTo(b.genre) : b.genre.compareTo(a.genre);
        });
        break;
      case RadioSortOption.country:
        filteredRadios.sort((a, b) {
          return _isAscending ? a.country.compareTo(b.country) : b.country.compareTo(a.country);
        });
        break;
      case RadioSortOption.dateAdded:
        // For favourite radios, maintain stack order (newest first) unless ascending is selected
        if (_isAscending) {
          filteredRadios = filteredRadios.reversed.toList();
        }
        break;
    }

    return filteredRadios;
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final allRadios = audioService.getPlaylistRadios('favourite_radios');
    final radios = _getFilteredAndSortedRadios(allRadios);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourite Radios'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Search Bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              decoration: const InputDecoration(
                hintText: 'Search radios by name, genre, or country...',
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
          // Sort Options
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Icon(Icons.sort, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Text('Sort by:', style: TextStyle(color: Colors.grey[400])),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<RadioSortOption>(
                    value: _sortOption,
                    dropdownColor: Colors.grey[900],
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(
                        value: RadioSortOption.name,
                        child: Text('Name'),
                      ),
                      DropdownMenuItem(
                        value: RadioSortOption.genre,
                        child: Text('Genre'),
                      ),
                      DropdownMenuItem(
                        value: RadioSortOption.country,
                        child: Text('Country'),
                      ),
                      DropdownMenuItem(
                        value: RadioSortOption.dateAdded,
                        child: Text('Date Added'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _sortOption = value;
                        });
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.deepPurple.shade400,
                  ),
                  onPressed: () {
                    setState(() {
                      _isAscending = !_isAscending;
                    });
                  },
                ),
              ],
            ),
          ),
          // Results count
          if (radios.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${radios.length} stations',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Radios List
          Expanded(
            child: radios.isEmpty && allRadios.isNotEmpty
                ? Center(
                    child: Text(
                      'No stations match your search',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                  )
                : radios.isEmpty
                    ? Center(
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
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 120), // Add bottom padding for mini player
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
                            title: Text(
                              radio.name,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  radio.genre,
                                  style: TextStyle(color: Colors.grey[400]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (radio.country.isNotEmpty)
                                  Text(
                                    radio.country,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              color: Colors.grey[900],
                              icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: Row(
                                    children: [
                                      Icon(Icons.favorite_border, color: Colors.red.shade400),
                                      const SizedBox(width: 8),
                                      const Text('Remove from favourites', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                  onTap: () {
                                    audioService.removeRadioFromPlaylist('favourite_radios', radio);
                                  },
                                ),
                              ],
                            ),
                            onTap: () => audioService.playRadioStation(radio),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
