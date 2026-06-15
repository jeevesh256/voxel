import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/settings_model.dart';
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

class _PersistentOverlayState extends State<PersistentOverlay> {
  bool _hasNetwork = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen(
          (_) => _checkConnectivity(),
          onError: (_) {},
        );
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
      // If check fails, assume no network to be safe
      if (mounted && _hasNetwork != false) {
        setState(() {
          _hasNetwork = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = BottomChromeMetrics.of(context);
    final offlineMode = context.watch<SettingsModel>().offlineMode;
    final isOffline = offlineMode || !_hasNetwork;
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        widget.child,
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
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
                    selectedItemColor: Colors.deepPurple.shade400,
                    unselectedItemColor: Colors.grey,
                    selectedFontSize: metrics.navLabelFontSize,
                    unselectedFontSize: metrics.navLabelFontSize,
                    iconSize: metrics.navIconSize,
                    currentIndex: widget.currentIndex,
                    elevation: 0,
                    enableFeedback: false,
                    onTap: widget.onTabChanged,
                    items: const [
                      BottomNavigationBarItem(
                          icon: Icon(Icons.home), label: 'Home'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.search), label: 'Search'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.library_music), label: 'Library'),
                      BottomNavigationBarItem(
                          icon: Icon(Icons.settings), label: 'Settings'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
