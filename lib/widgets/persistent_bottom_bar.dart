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
              selectedItemColor: Colors.deepPurple.shade400,
              unselectedItemColor: Colors.grey,
              selectedFontSize: metrics.navLabelFontSize,
              unselectedFontSize: metrics.navLabelFontSize,
              iconSize: metrics.navIconSize,
              currentIndex: currentIndex,
              elevation: 0,
              enableFeedback: false,
              onTap: onTap,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
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
    );
  }
}
