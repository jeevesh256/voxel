import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/radio_station.dart';
import '../services/audio_service.dart';
import 'package:provider/provider.dart';

bool _isValidArtwork(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();

  // These Google thumbnail URLs are often short-lived and return 404s.
  if (host.startsWith('encrypted-tbn') && host.endsWith('gstatic.com')) {
    return false;
  }

  // Known station-logo CDN entries that frequently fail DNS resolution.
  if (host == 'de8as167a043l.cloudfront.net' ||
      path.contains('/styles/images/logosplus/')) {
    return false;
  }

  // Reject generic /icon.png and favicon-like paths that often return HTTP errors
  if (path.endsWith('/icon.png') || 
      path.endsWith('/icon.ico') ||
      path.endsWith('/favicon.ico')) {
    return false;
  }

  return host.isNotEmpty &&
      !path.endsWith('.ico') &&
      !path.endsWith('.svg') &&
      !path.endsWith('.bmp');
}

class AllStationsPage extends StatefulWidget {
  final List<RadioStation> stations;
  const AllStationsPage({super.key, required this.stations});

  @override
  State<AllStationsPage> createState() => _AllStationsPageState();
}

class _AllStationsPageState extends State<AllStationsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildHeroHeader(int stationCount) {
    return Stack(
      fit: StackFit.expand,
        children: [
          const Center(
            child: Icon(
              Icons.radio,
              size: 120,
              color: Colors.white24,
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.55, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.black38,
                  Colors.black,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Radio Stations',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.0,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$stationCount ${stationCount == 1 ? 'station' : 'stations'}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.read<AudioPlayerService>();
    return Scaffold(
      backgroundColor: Colors.black,
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
              backgroundColor: Colors.black.withOpacity(opacity),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: kToolbarHeight + 12,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: opacity > 0.5
                  ? Text(
                      'Radio Stations',
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                            ((opacity - 0.5) * 2).clamp(0.0, 1.0)),
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
              child: _buildHeroHeader(widget.stations.length),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 100,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final station = widget.stations[index];
                  final hasArt = _isValidArtwork(station.artworkUrl);
                  return GestureDetector(
                    onTap: () => audioService.playRadioStation(station),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 0, top: 6, bottom: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: hasArt
                                  ? CachedNetworkImage(
                                      imageUrl: station.artworkUrl,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      placeholder: (_, __) => Container(
                                        color: const Color(0xFF2A1A3A),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF6A5B8E),
                                        child: const Icon(Icons.radio,
                                            color: Colors.white, size: 24),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF6A5B8E),
                                      child: const Icon(Icons.radio,
                                          color: Colors.white, size: 24),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  station.genre,
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
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: widget.stations.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
