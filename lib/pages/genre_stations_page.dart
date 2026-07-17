import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/radio_station.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../services/radio_playback_guard.dart';
import '../widgets/voxel_toast.dart';
import '../widgets/radio_menu_sheet.dart';
import 'package:provider/provider.dart';
import '../services/artwork_validator.dart';

// _isValidArtwork has been replaced by global isValidArtwork from services/artwork_validator.dart

class GenreStationsPage extends StatefulWidget {
  final String genre;
  final List<RadioStation> stations;

  const GenreStationsPage({
    super.key,
    required this.genre,
    required this.stations,
  });

  @override
  State<GenreStationsPage> createState() => _GenreStationsPageState();
}

class _GenreStationsPageState extends State<GenreStationsPage> {
  final ScrollController _scrollController = ScrollController();

  static const Map<String, String> _genreArtwork = {
    'Pop': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=800&h=800&fit=crop',
    'Rock': 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=800&h=800&fit=crop',
    'Jazz': 'https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=800&h=800&fit=crop',
    'Classical': 'https://images.unsplash.com/photo-1507838153414-b4b713384a76?w=800&h=800&fit=crop',
    'Electronic': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&h=800&fit=crop',
    'Hip-Hop': 'https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=800&h=800&fit=crop',
    'Country': 'https://images.unsplash.com/photo-1586348943529-beaae6c28db9?w=800&h=800&fit=crop',
    'Blues': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=800&h=800&fit=crop',
    'Reggae': 'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=800&h=800&fit=crop',
    'Latin': 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&h=800&fit=crop',
    'News': 'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=800&h=800&fit=crop',
    'Talk': 'https://images.unsplash.com/photo-1589903308904-1010c2294adc?w=800&h=800&fit=crop',
    'Sports': 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&h=800&fit=crop',
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final activeStations = widget.stations.where((s) => !audioService.isRadioHidden(s.id)).toList();
    final artworkUrl = _genreArtwork[widget.genre] ??
        'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=800&h=800&fit=crop';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 12),
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            final opacity = ((_scrollController.hasClients
                        ? _scrollController.offset
                        : 0.0) /
                    320.0)
                .clamp(0.0, 1.0);
            return AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(opacity),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: kToolbarHeight + 12,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: opacity > 0.5
                  ? Text(
                      widget.genre,
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(((opacity - 0.5) * 2).clamp(0.0, 1.0)),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          // Hero header
          SliverToBoxAdapter(
            child: SizedBox(
              height: 360,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: artworkUrl,
                    fit: BoxFit.cover,
                    errorListener: (_) {},
                    placeholder: (_, __) =>
                        Container(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
                    errorWidget: (_, __, ___) =>
                        Container(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
                  ),
                  // Gradient overlay
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.5, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black26,
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                  // Text at bottom
                  Positioned(
                    bottom: 24,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.genre,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${activeStations.length} stations',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // List
          SliverPadding(
            padding: EdgeInsets.only(
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16.0,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final station = activeStations[index];
                  final hasArt = isValidArtwork(station.artworkUrl);
                  final isRadioActive = audioService.isRadioPlaying &&
                      audioService.currentRadioStation?.id == station.id;
                  return GestureDetector(
                    onTap: () async {
                      final blockReason = await RadioPlaybackGuard.blockingMessage();
                      if (blockReason != null) {
                        final bottomPad = MediaQuery.of(context).padding.bottom + 8.0;
                        VoxelToast.show(
                          context,
                          blockReason,
                          bottomPadding: bottomPad,
                        );
                        return;
                      }
                      audioService.playRadioStation(station);
                    },
                    onLongPress: () {
                      final settings = Provider.of<SettingsModel>(context, listen: false);
                      if (settings.hapticsEnabled && settings.hapticsOnLongPress) {
                        HapticFeedback.mediumImpact();
                      }
                      _showRadioOptions(context, station, audioService);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 0, top: 6, bottom: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 48,
                              height: 48,
                               child: hasArt
                                   ? CachedNetworkImage(
                                       imageUrl: station.artworkUrl,
                                       fit: BoxFit.cover,
                                       filterQuality: FilterQuality.high,
                                       errorListener: (_) {},
                                       placeholder: (_, __) => Container(
                                         color: Theme.of(context).colorScheme.primaryContainer,
                                       ),
                                       errorWidget: (_, __, ___) => Container(
                                         color: Theme.of(context).colorScheme.primaryContainer,
                                         child: Icon(Icons.radio_rounded,
                                             color: Theme.of(context).colorScheme.onPrimaryContainer, size: 24),
                                       ),
                                     )
                                   : Container(
                                       color: Theme.of(context).colorScheme.primaryContainer,
                                       child: Icon(Icons.radio_rounded,
                                           color: Theme.of(context).colorScheme.onPrimaryContainer, size: 24),
                                     ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.name,
                                  style: TextStyle(
                                    fontWeight: isRadioActive ? FontWeight.w500 : FontWeight.w400,
                                    fontSize: 16,
                                    color: isRadioActive 
                                        ? Theme.of(context).colorScheme.primary 
                                        : Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  station.country.isNotEmpty
                                      ? station.country
                                      : station.genre,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.more_vert,
                              color: Colors.grey[400],
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 40, minHeight: 40),
                            onPressed: () => _showRadioOptions(context, station, audioService),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: activeStations.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRadioOptions(BuildContext context, RadioStation station, AudioPlayerService audioService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => RadioMenuSheet(
        radio: station,
        accentColor: Theme.of(context).colorScheme.primary,
        audioService: audioService,
      ),
    );
  }
}
