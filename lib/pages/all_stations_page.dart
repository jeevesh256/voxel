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
import '../services/radio_browser_service.dart';

// _isValidArtwork has been replaced by global isValidArtwork from services/artwork_validator.dart

class AllStationsPage extends StatefulWidget {
  final List<RadioStation> stations;
  const AllStationsPage({super.key, required this.stations});

  @override
  State<AllStationsPage> createState() => _AllStationsPageState();
}

class _AllStationsPageState extends State<AllStationsPage> {
  final ScrollController _scrollController = ScrollController();
  List<RadioStation> _stations = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _stations = widget.stations;
    if (_stations.isEmpty) {
      _loadStations();
    }
  }

  Future<void> _loadStations() async {
    setState(() => _isLoading = true);
    try {
      final stations = await RadioBrowserService().fetchTopStations(limit: 200);
      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildHeroHeader(int stationCount) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Subtle accent color background glow
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accentColor.withOpacity(0.25),
                Colors.black,
              ],
            ),
          ),
        ),
        Center(
          child: Icon(
            Icons.radio,
            size: 120,
            color: accentColor.withOpacity(0.15),
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

  Widget _buildFallbackArt(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.radio_rounded,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final activeStations = _stations.where((s) => !audioService.isRadioHidden(s.id)).toList();

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
              child: _buildHeroHeader(activeStations.length),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.only(
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
                           Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              child: hasArt
                                  ? CachedNetworkImage(
                                      imageUrl: station.artworkUrl,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.medium,
                                      errorWidget: (_, __, ___) => _buildFallbackArt(context),
                                      placeholder: (_, __) => _buildFallbackArt(context),
                                    )
                                  : _buildFallbackArt(context),
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
                                    color: isRadioActive 
                                        ? Theme.of(context).colorScheme.primary 
                                        : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  station.genre,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: Colors.white70),
                            onPressed: () {
                              _showRadioOptions(context, station, audioService);
                            },
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
