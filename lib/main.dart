import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'services/audio_service.dart';
import 'models/settings_model.dart';
import 'models/favourite_radios_model.dart';
import 'services/playlist_handler.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';
import 'widgets/persistent_overlay.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Create initializer widget to handle setup
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
  AudioPlayerService? _audioService;
  PlaylistHandler? _playlistHandler;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('Starting initialization...');

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

      // Initialize services
      final playlistHandler = PlaylistHandler();
      final audioService = AudioPlayerService(playlistHandler);

      if (mounted) {
        setState(() {
          _playlistHandler = playlistHandler;
          _audioService = audioService;
          _isLoading = false;
        });
      }

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
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
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
            ),
          ),
        ),
      );
    }

    if (_isLoading || _audioService == null || _playlistHandler == null) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _playlistHandler!),
        ChangeNotifierProvider.value(value: _audioService!),
        ChangeNotifierProvider(create: (_) => SettingsModel()),
        ChangeNotifierProvider(create: (_) => FavouriteRadiosModel()),
      ],
      child: const MyApp(),
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
  final int initialIndex;
  
  const MusicApp({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  late int _selectedIndex;
  
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  final List<Widget> _pages = [
    const HomePage(),
    const SearchPage(),
    const LibraryPage(),
    SettingsPage(),
  ];

  Future<bool> _onWillPop() async {
    final currentNavigator = _navigatorKeys[_selectedIndex].currentState;
    
    // If we can pop the current navigator, do that first
    if (currentNavigator?.canPop() ?? false) {
      currentNavigator?.pop();
      return false;
    }
    
    // If we're already on the home tab, allow the app to close
    // Otherwise, switch to home tab
    if (_selectedIndex == 0) {
      return true; // Exit app when on home tab
    } else {
      setState(() => _selectedIndex = 0);
      return false; // Don't exit app, just switched tabs
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: PersistentOverlay(
          currentIndex: _selectedIndex,
          onTabChanged: (index) => setState(() => _selectedIndex = index),
          child: Navigator(
            key: _navigatorKeys[_selectedIndex],
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) => _pages[_selectedIndex],
            ),
          ),
        ),
      ),
    );
  }
}
