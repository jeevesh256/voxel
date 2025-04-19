import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:provider/provider.dart';
import 'services/audio_service.dart';
import 'widgets/player.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(const MyInitializer());
}

class MyInitializer extends StatefulWidget {
  const MyInitializer({super.key});

  @override
  State<MyInitializer> createState() => _MyInitializerState();
}

class _MyInitializerState extends State<MyInitializer> {
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('Starting initialization...');
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize background playback
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.example.voxel.channel.audio',
        androidNotificationChannelName: 'Voxel Music Player',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        notificationColor: const Color(0xFF2196f3),
      );

      // Test basic audio functionality first
      final testPlayer = AudioPlayer();
      await testPlayer.dispose();
      debugPrint('Basic audio test passed');

      final audioService = AudioPlayerService();
      await audioService.initialize();
      debugPrint('AudioService initialized');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      runApp(
        ChangeNotifierProvider.value(
          value: audioService,
          child: const MyApp(),
        ),
      );
    } catch (e, stack) {
      debugPrint('Initialization error: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Failed to initialize audio services',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Ensure audio service is initialized
    context.read<AudioPlayerService>();
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voxel Music Player',
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
