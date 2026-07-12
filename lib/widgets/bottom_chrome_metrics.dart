import 'package:flutter/material.dart';

class BottomChromeMetrics {
  const BottomChromeMetrics({
    required this.miniPlayerHeight,
    required this.miniPlayerArtworkSize,
    required this.miniPlayerTitleHeight,
    required this.miniPlayerArtistHeight,
    required this.navBarHeight,
    required this.navIconSize,
    required this.navLabelFontSize,
    required this.fullScreenTitleHeight,
    required this.fullScreenArtistHeight,
  });

  final double miniPlayerHeight;
  final double miniPlayerArtworkSize;
  final double miniPlayerTitleHeight;
  final double miniPlayerArtistHeight;
  final double navBarHeight;
  final double navIconSize;
  final double navLabelFontSize;
  final double fullScreenTitleHeight;
  final double fullScreenArtistHeight;

  static BottomChromeMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final deviceScale = (size.shortestSide / 400.0).clamp(1.0, 1.35);

    return BottomChromeMetrics(
      miniPlayerHeight: 72.0 * deviceScale,
      miniPlayerArtworkSize: 50.0 * deviceScale,
      miniPlayerTitleHeight: (22.0 * deviceScale).clamp(20.0, 28.0),
      miniPlayerArtistHeight: (18.0 * deviceScale).clamp(16.0, 24.0),
      navBarHeight: 90.0 * deviceScale,
      navIconSize: 25.0 * deviceScale,
      navLabelFontSize: 11.5 * deviceScale,
      fullScreenTitleHeight: (38.0 * deviceScale).clamp(34.0, 50.0),
      fullScreenArtistHeight: (28.0 * deviceScale).clamp(24.0, 36.0),
    );
  }
}
