import 'package:flutter/material.dart';
import 'player.dart';

class PersistentOverlay extends StatelessWidget {
  final Widget child;
  final int currentIndex;
  final Function(int) onTabChanged;

  const PersistentOverlay({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
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
                child: BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.black,
                  selectedItemColor: Colors.deepPurple.shade400,
                  unselectedItemColor: Colors.grey,
                  currentIndex: currentIndex,
                  elevation: 0,
                  enableFeedback: false,
                  onTap: onTabChanged,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                    BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
                    BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
