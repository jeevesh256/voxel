import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/audio_service.dart';
import 'bottom_chrome_metrics.dart';
import 'player.dart';

class PersistentOverlay extends StatefulWidget {
  final Widget child;
  final int currentIndex;
  final Function(int) onTabChanged;
  final bool hideOfflineIndicator;

  const PersistentOverlay({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onTabChanged,
    this.hideOfflineIndicator = false,
  });

  @override
  State<PersistentOverlay> createState() => _PersistentOverlayState();
}

class _PersistentOverlayState extends State<PersistentOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playerController;
  bool _hasNetwork = true;

  @override
  void initState() {
    super.initState();
    _playerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen(
          (_) => _checkConnectivity(),
          onError: (_) {},
        );
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (mounted && _hasNetwork != hasNetwork) {
        setState(() {
          _hasNetwork = hasNetwork;
        });
      }
    } catch (_) {
      if (mounted && _hasNetwork != false) {
        setState(() {
          _hasNetwork = false;
        });
      }
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final metrics = BottomChromeMetrics.of(context);
    final isOffline = !_hasNetwork;
    final topInset = MediaQuery.of(context).padding.top;
    final audioService = context.watch<AudioPlayerService>();
    final isPlayerVisible = audioService.isMiniPlayerVisible;

    return WillPopScope(
      onWillPop: () async {
        if (_playerController.value > 0.0) {
          _playerController.animateTo(0.0, curve: Curves.easeOutCubic);
          return false;
        }
        return true;
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: MediaQuery.of(context).padding.copyWith(
                  bottom: MediaQuery.of(context).padding.bottom +
                      metrics.navBarHeight +
                      (isPlayerVisible ? metrics.miniPlayerHeight : 0.0),
                ),
              ),
              child: widget.child,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPlayerVisible)
                    SizedBox(height: metrics.miniPlayerHeight),
                  Theme(
                    data: Theme.of(context).copyWith(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                    child: SizedBox(
                      height: metrics.navBarHeight,
                      child: BottomNavigationBar(
                        type: BottomNavigationBarType.fixed,
                        backgroundColor: Colors.black,
                        selectedItemColor: Theme.of(context).colorScheme.primary,
                        unselectedItemColor: Colors.grey,
                        selectedFontSize: metrics.navLabelFontSize,
                        unselectedFontSize: metrics.navLabelFontSize,
                        iconSize: metrics.navIconSize,
                        currentIndex: widget.currentIndex,
                        elevation: 0,
                        enableFeedback: false,
                        onTap: widget.onTabChanged,
                        items: [
                          BottomNavigationBarItem(
                            icon: Icon(
                              widget.currentIndex == 0
                                  ? Icons.home_rounded
                                  : Icons.home_outlined,
                            ),
                            label: 'Home',
                          ),
                          BottomNavigationBarItem(
                            icon: const Icon(
                              Icons.search_rounded,
                            ),
                            label: 'Search',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(
                              widget.currentIndex == 2
                                  ? Icons.library_music_rounded
                                  : Icons.library_music_outlined,
                            ),
                            label: 'Library',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(
                              widget.currentIndex == 3
                                  ? Icons.settings_rounded
                                  : Icons.settings_outlined,
                            ),
                            label: 'Settings',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (isOffline && !widget.hideOfflineIndicator)
              Positioned(
                top: topInset + 8,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.32),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24, width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.wifi_off_rounded,
                            size: 12, color: Colors.white70),
                        SizedBox(width: 6),
                        Text(
                          'Offline',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Sliding player sheet
            if (isPlayerVisible)
              AnimatedBuilder(
                animation: _playerController,
                builder: (context, child) {
                  final t = _playerController.value;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final bottomPos = _lerp(metrics.navBarHeight, 0.0, t);
                  final playerHeight = _lerp(metrics.miniPlayerHeight, screenHeight, t);

                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomPos,
                    height: playerHeight,
                    child: SlidingPlayer(
                      controller: _playerController,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
