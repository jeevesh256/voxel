import 'package:flutter/material.dart';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import 'package:provider/provider.dart';

class AllStationsPage extends StatelessWidget {
  final List<RadioStation> stations;
  const AllStationsPage({super.key, required this.stations});

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Radio Stations'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
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
    );
  }
}
