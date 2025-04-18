import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple Music Clone',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.deepPurple.shade400,
          secondary: Colors.deepPurple.shade200,
          background: Colors.black,
          surface: Colors.grey.shade900,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      home: const MusicApp(),
    );
  }
}

class MusicApp extends StatefulWidget {
  const MusicApp({super.key});

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const SearchPage(),
    const LibraryPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _buildNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.deepPurple.shade400,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        elevation: 0,
        enableFeedback: false,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const FullScreenPlayer(),
        );
      },
      child: Container(
        height: 60,
        color: Colors.grey.shade900,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Colors.deepPurple.shade200,
              ),
              child: const Icon(Icons.music_note),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currently Playing Song',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Artist Name',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_border),
              color: Colors.white,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              color: Colors.white,
              onPressed: () {},
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.deepPurple.shade400,
            Colors.grey.shade900,
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header with down arrow and menu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    color: Colors.white,
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // Album Art
            const Spacer(),
            Container(
              width: MediaQuery.of(context).size.width * 0.7,
              height: MediaQuery.of(context).size.width * 0.7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.deepPurple.shade200,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.music_note, size: 80, color: Colors.white),
            ),
            const Spacer(),

            // Controls Section
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Song Info
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Currently Playing Song',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Artist Name',
                              style: TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite_border),
                        color: Colors.white,
                        onPressed: () {},
                      ),
                    ],
                  ),

                  // Progress Bar
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 8,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.grey.shade600,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withOpacity(0.2),
                        ),
                        child: Slider(
                          value: 0.5,
                          onChanged: (value) {},
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('2:30', style: TextStyle(color: Colors.grey.shade400)),
                            Text('4:30', style: TextStyle(color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Playback Controls
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        color: Colors.grey.shade400,
                        iconSize: 24,
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        color: Colors.white,
                        iconSize: 40,
                        onPressed: () {},
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          color: Colors.black,
                          iconSize: 40,
                          onPressed: () {},
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        color: Colors.white,
                        iconSize: 40,
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.repeat),
                        color: Colors.grey.shade400,
                        iconSize: 24,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Playing Next',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: Colors.deepPurple.shade200,
                    ),
                    child: const Icon(Icons.music_note),
                  ),
                  title: Text(
                    'Song ${index + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Artist ${index + 1}',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    color: Colors.white,
                    onPressed: () {},
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Placeholder pages
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Home', style: TextStyle(color: Colors.white)));
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Library', style: TextStyle(color: Colors.white)));
}

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Search', style: TextStyle(color: Colors.white)));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Settings', style: TextStyle(color: Colors.white)));
}
