import 'package:flutter/material.dart';
import 'bottom_chrome_metrics.dart';
import 'player.dart';

class PersistentBottomBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const PersistentBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = BottomChromeMetrics.of(context);
    return Column(
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
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              selectedFontSize: metrics.navLabelFontSize,
              unselectedFontSize: metrics.navLabelFontSize,
              iconSize: metrics.navIconSize,
              currentIndex: currentIndex,
              elevation: 0,
              enableFeedback: false,
              onTap: onTap,
              items: [
                BottomNavigationBarItem(
                  icon: Icon(
                    currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
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
                    currentIndex == 2
                        ? Icons.library_music_rounded
                        : Icons.library_music_outlined,
                  ),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    currentIndex == 3
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
    );
  }
}
