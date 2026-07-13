import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
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

      if (Platform.isAndroid) {
        await Permission.notification.request();
      }

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

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
    final settings = context.watch<SettingsModel>();
    final accentColor = settings.accentColor;

    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
    ).copyWith(primary: accentColor);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voxel Music Player',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,

        // ── AppBar ──────────────────────────────────────────────
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: scheme.onSurface),
          titleTextStyle: TextStyle(
            color: scheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),

        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surfaceContainer,
          indicatorColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: scheme.primary, size: 24);
            }
            return IconThemeData(color: scheme.onSurfaceVariant.withOpacity(0.7), size: 24);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final base = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withOpacity(0.7));
            if (states.contains(WidgetState.selected)) {
              return base.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              );
            }
            return base;
          }),
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),

        // ── Bottom Sheet ───────────────────────────────────────
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surfaceContainerHigh,
          modalBackgroundColor: scheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          showDragHandle: false,
        ),

        // ── Dialog ────────────────────────────────────────────
        dialogTheme: DialogThemeData(
          backgroundColor: scheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: TextStyle(
            color: scheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        ),

        // ── Divider ────────────────────────────────────────────
        dividerTheme: DividerThemeData(
          color: scheme.outlineVariant,
          thickness: 0.7,
          space: 0,
        ),

        // ── Switch ────────────────────────────────────────────
        switchTheme: SwitchThemeData(
          thumbIcon: WidgetStateProperty.fromMap({
            WidgetState.selected: const Icon(Icons.check),
            WidgetState.any: null,
          }),
        ),

        // ── ListTile ──────────────────────────────────────────
        listTileTheme: ListTileThemeData(
          iconColor: scheme.onSurfaceVariant,
          textColor: scheme.onSurface,
          subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),

        // ── TabBar ────────────────────────────────────────────
        tabBarTheme: TabBarThemeData(
          labelColor: scheme.onSurface,
          unselectedLabelColor: scheme.onSurfaceVariant,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: scheme.primaryContainer,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),

        // ── Slider ────────────────────────────────────────────
        sliderTheme: SliderThemeData(
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.surfaceContainerHighest,
          thumbColor: scheme.primary,
          overlayColor: scheme.primary.withOpacity(0.2),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),

        // ── Chip ──────────────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: scheme.surfaceContainerHigh,
          selectedColor: scheme.primaryContainer,
          labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
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
  final _searchKey = GlobalKey<SearchPageState>();
  late final List<Widget> _pages;
  bool _stackRefreshScheduled = false;

  late final List<_OverlayNavigatorObserver> _navigatorObservers;

  bool get _isOnSubPage {
    final nav = _navigatorKeys[_selectedIndex].currentState;
    return nav?.canPop() ?? false;
  }

  void _onNavigatorStackChanged() {
    if (!mounted || _stackRefreshScheduled) return;

    void refresh() {
      _stackRefreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      refresh();
      return;
    }

    _stackRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _navigatorObservers = List.generate(
      _navigatorKeys.length,
      (_) => _OverlayNavigatorObserver(onStackChanged: _onNavigatorStackChanged),
    );
    _pages = [
      const HomePage(),
      SearchPage(key: _searchKey),
      const LibraryPage(),
      SettingsPage(),
    ];
  }

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  Future<bool> _onWillPop() async {
    final currentNavigator = _navigatorKeys[_selectedIndex].currentState;

    // Pop sub-routes first (e.g. ArtistPage pushed on top of SearchPage)
    if (currentNavigator?.canPop() ?? false) {
      currentNavigator?.pop();
      return false;
    }

    // Let the current page handle back softly (e.g. SearchPage clearing query)
    if (_searchKey.currentState?.handleBack() ?? false) {
      return false;
    }

    if (_selectedIndex == 0) {
      return true; // exit app
    } else {
      setState(() => _selectedIndex = 0);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    void handleTabTap(int index) {
      if (index == _selectedIndex) {
        final navigator = _navigatorKeys[index].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
        return;
      }
      setState(() => _selectedIndex = index);
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: PersistentOverlay(
          currentIndex: _selectedIndex,
          onTabChanged: handleTabTap,
          hideOfflineIndicator:
              _isOnSubPage || _selectedIndex == 1,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.fastOutSlowIn,
            switchOutCurve: Curves.fastOutSlowIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: RepaintBoundary(
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: Navigator(
                key: _navigatorKeys[_selectedIndex],
                observers: [_navigatorObservers[_selectedIndex]],
                onGenerateRoute: (settings) => PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      _pages[_selectedIndex],
                  transitionDuration: Duration.zero,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return child;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayNavigatorObserver extends NavigatorObserver {
  final VoidCallback onStackChanged;

  _OverlayNavigatorObserver({required this.onStackChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onStackChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onStackChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onStackChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onStackChanged();
  }
}
