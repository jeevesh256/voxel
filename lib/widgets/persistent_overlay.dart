import 'package:flutter/cupertino.dart';
import 'package:material_symbols_icons/symbols.dart';
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
  State<PersistentOverlay> createState() => PersistentOverlayState();
}

class PersistentOverlayState extends State<PersistentOverlay>
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
    _checkInitialConnection();
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (mounted) {
        setState(() {
          _hasNetwork = results.any((r) => r != ConnectivityResult.none);
        });
      }
    });
  }

  Future<void> _checkInitialConnection() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _hasNetwork = results.any((r) => r != ConnectivityResult.none);
      });
    }
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  bool handleBack() {
    debugPrint('PersistentOverlay: handleBack called. PlayerController.value: ${_playerController.value}');
    if (_playerController.value > 0.0) {
      _playerController.animateTo(0.0, curve: Curves.easeOutCubic);
      return true;
    }
    return false;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final metrics = BottomChromeMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isOffline = !_hasNetwork;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final audioService = context.watch<AudioPlayerService>();
    final isPlayerVisible = audioService.isMiniPlayerVisible;

    // Custom Bottom Navigation Bar to avoid standard M3 NavigationBar height stretching
    final destinations = [
      (icon: Symbols.home_rounded, selectedIcon: Symbols.home_rounded, label: 'Home', usesFill: true),
      (icon: Icons.search_rounded, selectedIcon: Icons.search_rounded, label: 'Search', usesFill: false),
      (icon: Icons.library_music_outlined, selectedIcon: Icons.library_music_rounded, label: 'Library', usesFill: false),
      (icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings', usesFill: false),
    ];

    final customNavBar = Container(
      height: metrics.navBarHeight + bottomInset,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withOpacity(0.3),
            width: 0.8,
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(destinations.length, (index) {
          final isSelected = widget.currentIndex == index;
          final item = destinations[index];
          final color = isSelected ? scheme.primary : scheme.onSurfaceVariant.withOpacity(0.7);
          
          return Expanded(
            child: InkWell(
              onTap: () => widget.onTabChanged(index),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? item.selectedIcon : item.icon,
                    color: color,
                    size: metrics.navIconSize,
                    fill: (isSelected && item.usesFill) ? 1.0 : 0.0,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: color,
                      fontSize: metrics.navLabelFontSize,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          // Body Content Area
            Positioned.fill(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: MediaQuery.of(context).padding.copyWith(
                    bottom: bottomInset +
                        metrics.navBarHeight +
                        (isPlayerVisible ? metrics.miniPlayerHeight + 4.0 : 0.0),
                  ),
                ),
                child: widget.child,
              ),
            ),

            // Offline Indicator
            if (isOffline && !widget.hideOfflineIndicator)
              Positioned(
                top: topInset + 8,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: scheme.outlineVariant, width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Offline',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
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

            // Bottom Navigation Bar Layer
            AnimatedBuilder(
              animation: _playerController,
              builder: (context, child) {
                final t = _playerController.value;
                // Move nav bar fully out of screen boundary on player expand
                final offset = _lerp(0.0, metrics.navBarHeight + bottomInset, t);
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: -offset,
                  child: customNavBar,
                );
              },
            ),

            // Mini Player / Full Screen Sliding Player Sheet overlay
            if (isPlayerVisible)
              AnimatedBuilder(
                animation: _playerController,
                builder: (context, child) {
                  final t = _playerController.value;
                  final screenHeight = MediaQuery.of(context).size.height;
                  
                  // Position mini player directly above active navBar (metrics.navBarHeight + bottomInset)
                  final currentNavBarHeight = _lerp(metrics.navBarHeight + bottomInset, 0.0, t);
                  
                  final playerHeight = _lerp(metrics.miniPlayerHeight, screenHeight, t);

                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: currentNavBarHeight,
                    height: playerHeight,
                    child: SlidingPlayer(
                      controller: _playerController,
                    ),
                  );
                },
              ),
          ],
        ),
    );
  }
}
