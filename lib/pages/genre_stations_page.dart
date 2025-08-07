import 'package:flutter/material.dart';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import 'package:provider/provider.dart';

class GenreStationsPage extends StatelessWidget {
  final String genre;
  final List<RadioStation> stations;
  
  const GenreStationsPage({
    super.key, 
    required this.genre,
    required this.stations,
  });

  // Get genre-specific artwork
  String _getGenreArtwork(String genre) {
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
    return genreArtwork[genre] ?? 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&h=400&fit=crop';
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context, listen: false);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header section with genre info and back button
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(_getGenreArtwork(genre)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.6),
                  BlendMode.darken,
                ),
              ),
            ),
            child: Stack(
              children: [
                // Back button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Genre info
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        genre,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: Offset(1, 1),
                              blurRadius: 3,
                              color: Colors.black54,
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${stations.length} stations',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Stations grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 136), // Add bottom padding for mini player
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final station = stations[index];
                final hasArt = station.artworkUrl.isNotEmpty;
                
                return GestureDetector(
                  onTap: () => audioService.playRadioStation(station),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: hasArt
                                    ? Image.network(
                                        station.artworkUrl,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.high,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.deepPurple.shade200,
                                          child: const Icon(Icons.radio, color: Colors.white, size: 60),
                                        ),
                                      )
                                    : Container(
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
                        ),
                        const SizedBox(height: 10),
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
                          station.country.isNotEmpty ? station.country : 'Unknown Country',
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
      ),
    );
  }
}
