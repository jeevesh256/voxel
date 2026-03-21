import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_service.dart';
import '../services/radio_browser_service.dart';
import '../services/itunes_service.dart';
import '../services/song_metadata_cache.dart';
import '../models/radio_station.dart';
import 'artist_page.dart';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/voxel_toast.dart';

bool _isValidArtwork(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();

  // These Google thumbnail URLs are often short-lived and return 404s.
  if (host.startsWith('encrypted-tbn') && host.endsWith('gstatic.com')) {
    return false;
  }

  // Known station-logo CDN entries that frequently fail DNS resolution.
  if (host == 'de8as167a043l.cloudfront.net' ||
      path.contains('/styles/images/logosplus/')) {
    return false;
  }

  // Reject generic /icon.png and favicon-like paths that often return HTTP errors
  if (path.endsWith('/icon.png') || 
      path.endsWith('/icon.ico') ||
      path.endsWith('/favicon.ico')) {
    return false;
  }

  return host.isNotEmpty &&
      !path.endsWith('.ico') &&
      !path.endsWith('.svg') &&
      !path.endsWith('.bmp');
}

// Helper for Cupertino-style page transitions
void pushMaterialPage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => RepaintBoundary(child: page),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        ));
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
    ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  // Pre-computed colors to avoid withOpacity allocations on every build
  static const Color _splashColor = Color(0x0AFFFFFF);    // white @ 0.04
  static const Color _highlightColor = Color(0x08FFFFFF); // white @ 0.03
  static const Color _searchBorderFocused = Color(0xCCA855F7); // deepPurple400 @ 0.8
  static const Color _searchBorderIdle = Color(0x12FFFFFF);    // white @ 0.07
  static const Color _searchShadow = Color(0x664C1D95);        // deepPurple900 @ 0.4
  static const Color _glowShadow = Color(0x66A855F7);          // deepPurple400 @ 0.4
  static const Color _categoryIconColor = Color(0x24FFFFFF);   // white @ 0.14
  String _query = '';
  late TabController _tabController;
  late PageController _pageController;
  List<RadioStation> _stations = [];
  List<ITunesTrack> _tracks = [];
  List<ITunesArtist> _itunesArtists = [];
  bool _loading = false;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ITunesService _itunesService = ITunesService();
  final RadioBrowserService _radioService = RadioBrowserService();
  final SongMetadataCache _metadataCache = SongMetadataCache();
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 4,
        vsync: this,
        animationDuration: const Duration(milliseconds: 300));
    _pageController = PageController();
    _metadataCache.initialize();
    _searchFocus.addListener(_onFocusChanged);
    _loadRecentSearches();
  }

  bool _wasFocused = false;

  void _onFocusChanged() {
    final isFocused = _searchFocus.hasFocus;
    if (isFocused != _wasFocused) {
      _wasFocused = isFocused;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _saveRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final updated = [q, ..._recentSearches.where((s) => s != q)].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', updated);
    if (!mounted) return;
    setState(() => _recentSearches = updated);
  }

  Future<void> _removeRecentSearch(String query) async {
    final updated = _recentSearches.where((s) => s != query).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', updated);
    if (!mounted) return;
    setState(() => _recentSearches = updated);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    _searchFocus.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || !mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _itunesService.searchTracks(term: q, limit: 8),
        _itunesService.searchArtists(term: q, limit: 5),
        _radioService.fetchStations(genre: q, limit: 15),
      ]);
      if (!mounted) return;
      setState(() {
        _tracks = results[0] as List<ITunesTrack>;
        _itunesArtists = results[1] as List<ITunesArtist>;
        _stations = results[2] as List<RadioStation>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isNotEmpty) {
      setState(() => _query = value);
      _debounceTimer = Timer(
          const Duration(milliseconds: 450), () => _runSearch(value));
    } else {
      setState(() {
        _query = value;
        _tracks = [];
        _itunesArtists = [];
        _stations = [];
        _loading = false;
      });
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic);
      _tabController.animateTo(0);
    }
  }

  void _searchCategory(String genre) {
    _searchController.value = TextEditingValue(
      text: genre,
      selection: TextSelection.collapsed(offset: genre.length),
    );
    setState(() => _query = genre);
    _debounceTimer?.cancel();
    _runSearch(genre);
    _searchFocus.unfocus();
  }

  // Normalize: lowercase, strip punctuation, collapse spaces
  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // Fuzzy match: exact normalized contains OR every word in [query] found in [target]
  bool _fuzzyMatch(String query, String target) {
    final q = _normalize(query);
    final t = _normalize(target);
    if (q.isEmpty || t.isEmpty) return false;
    if (t.contains(q) || q.contains(t)) return true;
    final words = q.split(' ').where((w) => w.length > 1).toList();
    return words.isNotEmpty && words.every((w) => t.contains(w));
  }

  void _playLocalMatch(ITunesTrack track, AudioPlayerService audioService) {
    final offlineSongs = audioService.getPlaylistSongs('offline');
    File? exactMatch;
    File? fuzzyMatch;
    for (final file in offlineSongs) {
      final song = _metadataCache.createSongFromFile(file);
      if (_normalize(song.title) == _normalize(track.trackName)) {
        exactMatch = file;
        break;
      }
      if (fuzzyMatch == null && _fuzzyMatch(track.trackName, song.title)) {
        fuzzyMatch = file;
      }
    }
    final match = exactMatch ?? fuzzyMatch;
    if (match != null) {
      _saveRecentSearch(track.trackName);
      audioService.playFileInContext(match, offlineSongs);
    } else {
      _showSnackBar('Not in your library');
    }
  }

  void _navigateToArtist(ITunesArtist artist, AudioPlayerService audioService) {
    final offlineSongs = audioService.getPlaylistSongs('offline');
    final artistFiles = <File>[];
    String? artwork;
    for (final file in offlineSongs) {
      final song = _metadataCache.createSongFromFile(file);
      if (_fuzzyMatch(artist.artistName, song.artist)) {
        artistFiles.add(file);
        if (artwork == null && song.albumArt.isNotEmpty) artwork = song.albumArt;
      }
    }
    _saveRecentSearch(artist.artistName);
    // Always navigate — ArtistPage handles empty library gracefully
    pushMaterialPage(context, ArtistPage(
      artistName: artist.artistName,
      songs: artistFiles,
      artistArtwork: artwork,
    ));
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final audioService = context.read<AudioPlayerService>();
    final seqState = audioService.player.sequenceState;
    final miniPlayerActive = seqState?.sequence.isNotEmpty ?? false;
    final bottomPad = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight +
        (miniPlayerActive ? 70.0 : 0.0);
    VoxelToast.show(context, message, bottomPadding: bottomPad);
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final miniPlayerActive = context.select<AudioPlayerService, bool>(
      (s) => s.player.sequenceState?.sequence.isNotEmpty ?? false,
    );
    final bottomPad = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight +
        (miniPlayerActive ? 70.0 : 0.0);

    return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          toolbarHeight: (_searchFocus.hasFocus || _query.isNotEmpty) ? 0.0 : 68.0,
          title: (_searchFocus.hasFocus || _query.isNotEmpty)
              ? null
              : const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 0, 8),
                  child: Text(
                    'Search',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
                (_searchFocus.hasFocus || _query.isNotEmpty) ? 132 : 120),
            child: Container(
              color: Colors.black,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    height:
                        (_searchFocus.hasFocus || _query.isNotEmpty) ? 12.0 : 0.0,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRect(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          width: (_searchFocus.hasFocus || _query.isNotEmpty)
                              ? 44.0
                              : 0.0,
                          child: GestureDetector(
                            onTap: handleBack,
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox(
                              width: 44,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: _buildSearchBar(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildTabBar(),
                ],
              ),
            ),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final vx = details.primaryVelocity ?? 0;
            final current = _tabController.index;
            final int next;
            if (vx < -300 && current < 3) {
              next = current + 1;
            } else if (vx > 300 && current > 0) {
              next = current - 1;
            } else {
              return;
            }
            _pageController.animateToPage(
              next,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
            );
            _tabController.animateTo(next);
          },
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildAllTab(audioService, bottomPad),
              _buildArtistsTab(audioService, bottomPad),
              _buildSongsTab(audioService, bottomPad),
              _buildRadioTab(audioService, bottomPad),
            ],
          ),
        ),
      );
  }

  /// Called by [_MusicAppState] when the hardware/gesture back is pressed.
  /// Returns true if the back was handled (search cleared), false otherwise.
  bool handleBack() {
    if (_query.isNotEmpty) {
      FocusScope.of(context).unfocus();
      _searchController.clear();
      _onSearchChanged('');
      return true;
    }
    if (_searchFocus.hasFocus) {
      FocusScope.of(context).unfocus();
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic);
      _tabController.animateTo(0);
      return true;
    }
    return false;
  }

  // ── Recent searches ───────────────────────────────────────────────────────

  List<Widget> _buildRecentSearches() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Searches',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('recent_searches');
                  if (!mounted) return;
                  setState(() => _recentSearches = []);
                },
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.deepPurple.shade300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final term = _recentSearches[index];
            return InkWell(
              onTap: () {
                _searchController.value = TextEditingValue(
                  text: term,
                  selection: TextSelection.collapsed(offset: term.length),
                );
                setState(() => _query = term);
                _debounceTimer?.cancel();
                _runSearch(term);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        term,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _removeRecentSearch(term),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 16, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: _recentSearches.length,
        ),
      ),
    ];
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TabBar(
        controller: _tabController,
        onTap: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
          );
        },
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Artists'),
          Tab(text: 'Songs'),
          Tab(text: 'Radio'),
        ],
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.deepPurple.shade500,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[500],
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────

  Widget _buildAllTab(AudioPlayerService audioService, double bottomPad) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        if (_searchFocus.hasFocus) _searchFocus.unfocus();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          if (_query.isEmpty && _searchFocus.hasFocus) ...[
            if (_recentSearches.isNotEmpty)
              ..._buildRecentSearches()
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Search for artists, songs or radio',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ),
              ),
          ],
          if (_query.isEmpty && !_searchFocus.hasFocus) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Browse',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildCategoryCard(index),
                  childCount: _categories.length,
                ),
              ),
            ),
          ],
          if (_loading) _buildLoadingSliver(),
          if (_query.isNotEmpty && !_loading) ...[
            if (_itunesArtists.isNotEmpty) ...[
              _sectionHeader('Artists'),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildArtistRow(_itunesArtists[index], audioService),
                  childCount: _itunesArtists.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
            if (_tracks.isNotEmpty) ...[
              _sectionHeader('Songs'),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildSongRow(_tracks[index], audioService),
                  childCount: _tracks.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
            if (_stations.isNotEmpty) ...[
              _sectionHeader('Radio Stations'),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildStationRow(_stations[index], audioService),
                  childCount: _stations.length,
                ),
              ),
            ],
            if (_itunesArtists.isEmpty &&
                _tracks.isEmpty &&
                _stations.isEmpty)
              _buildTabEmptySliver(),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
        ],
      ),
    );
  }

  Widget _buildArtistsTab(
      AudioPlayerService audioService, double bottomPad) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        if (_searchFocus.hasFocus) _searchFocus.unfocus();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          if (_query.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded,
                          size: 34, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Search for artists',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Search by artist name',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading) _buildLoadingSliver(),
          if (_query.isNotEmpty && !_loading) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_itunesArtists.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) =>
                      _buildArtistRow(_itunesArtists[i], audioService),
                  childCount: _itunesArtists.length,
                ),
              ),
            if (_itunesArtists.isEmpty) _buildTabEmptySliver(),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
        ],
      ),
    );
  }

  Widget _buildSongsTab(AudioPlayerService audioService, double bottomPad) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        if (_searchFocus.hasFocus) _searchFocus.unfocus();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          if (_query.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.music_note_rounded,
                          size: 34, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Search for songs',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Search by song or artist',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading) _buildLoadingSliver(),
          if (_query.isNotEmpty && !_loading) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_tracks.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildSongRow(_tracks[i], audioService),
                  childCount: _tracks.length,
                ),
              ),
            if (_tracks.isEmpty) _buildTabEmptySliver(),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
        ],
      ),
    );
  }

  Widget _buildRadioTab(AudioPlayerService audioService, double bottomPad) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        if (_searchFocus.hasFocus) _searchFocus.unfocus();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          if (_query.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.radio_rounded,
                          size: 34, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Search for radio stations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Discover live radio worldwide',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading) _buildLoadingSliver(),
          if (_query.isNotEmpty && !_loading) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_stations.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildStationRow(_stations[i], audioService),
                  childCount: _stations.length,
                ),
              ),
            if (_stations.isEmpty) _buildTabEmptySliver(),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildLoadingSliver() {
    return const SliverToBoxAdapter(child: _SkeletonLoader());
  }

  SliverToBoxAdapter _buildTabEmptySliver() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 280,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded,
                  size: 34, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            Text(
              'No results for',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '"$_query"',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Try a different spelling or keyword',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistRow(
      ITunesArtist artist, AudioPlayerService audioService) {
    final hash = artist.artistName.codeUnits.fold(0, (a, b) => a + b);
    final hue = (hash % 360).toDouble();
    final avatarColor = HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor();
    final initial = artist.artistName.isNotEmpty
        ? artist.artistName[0].toUpperCase()
        : '?';
    final artUrl = _tracks
        .where((t) =>
            t.artistName.toLowerCase() ==
            artist.artistName.toLowerCase())
        .map((t) => t.artworkUrl)
        .where((url) => url.isNotEmpty)
        .firstOrNull;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToArtist(artist, audioService),
        splashColor: _splashColor,
        highlightColor: _highlightColor,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ClipOval(
                  child: artUrl != null
                      ? CachedNetworkImage(
                          imageUrl: artUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 112,
                          memCacheHeight: 112,
                          placeholder: (_, __) =>
                              _initialsAvatar(initial, avatarColor),
                          errorWidget: (_, __, ___) =>
                              _initialsAvatar(initial, avatarColor),
                        )
                      : _initialsAvatar(initial, avatarColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.artistName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (artist.primaryGenre.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        artist.primaryGenre,
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final focused = _searchFocus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused
              ? _searchBorderFocused
              : _searchBorderIdle,
          width: 1.5,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: _searchShadow,
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            color: focused ? Colors.deepPurple.shade300 : Colors.grey[500],
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.1,
              ),
              decoration: InputDecoration(
                hintText: 'Artists, songs, radio...',
                hintStyle: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _searchFocus.unfocus();
                if (v.trim().isNotEmpty) {
                  _debounceTimer?.cancel();
                  _runSearch(v);
                }
              },
            ),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ] else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  SliverToBoxAdapter _sectionHeader(String label) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  Widget _initialsAvatar(String initial, Color color) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
    );
  }

  // ── Song row ──────────────────────────────────────────────────────────────

  Widget _buildSongRow(ITunesTrack track, AudioPlayerService audioService) {
    final hasArt = track.artworkUrl.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playLocalMatch(track, audioService),
        splashColor: _splashColor,
        highlightColor: _highlightColor,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 16, top: 9, bottom: 9),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: hasArt
                      ? CachedNetworkImage(
                          imageUrl: track.artworkUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 100,
                          memCacheHeight: 100,
                          placeholder: (_, __) =>
                              _artPlaceholder(isRadio: false),
                          errorWidget: (_, __, ___) =>
                              _artPlaceholder(isRadio: false),
                        )
                      : _artPlaceholder(isRadio: false),
                ),
              ),
              const SizedBox(width: 14),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.trackName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.collectionName.isNotEmpty
                          ? '${track.artistName} · ${track.collectionName}'
                          : track.artistName,
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // More options
              IconButton(
                onPressed: () => _showSongOptions(track, audioService),
                icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 22),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSongOptions(
      ITunesTrack track, AudioPlayerService audioService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Song info header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: track.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: track.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _artPlaceholder(isRadio: false),
                              )
                            : _artPlaceholder(isRadio: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.trackName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artistName,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              ListTile(
                leading: Icon(Icons.play_arrow_rounded,
                    color: Colors.grey[300], size: 22),
                title: Text('Play from library',
                    style: TextStyle(color: Colors.grey[200])),
                onTap: () {
                  Navigator.pop(ctx);
                  _playLocalMatch(track, audioService);
                },
              ),
              ListTile(
                leading: Icon(Icons.person_outline_rounded,
                    color: Colors.grey[300], size: 22),
                title: Text('Go to artist',
                    style: TextStyle(color: Colors.grey[200])),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToArtist(
                    ITunesArtist(
                      artistName: track.artistName,
                      primaryGenre: '',
                      artistLinkUrl: '',
                      artistId: 0,
                    ),
                    audioService,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Station row ───────────────────────────────────────────────────────────

  Widget _buildStationRow(
      RadioStation station, AudioPlayerService audioService) {
    final isPlaying =
        audioService.currentRadioStation?.id == station.id;
    final isLiked = audioService.isRadioLiked(station);
    final hasArt = _isValidArtwork(station.artworkUrl);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _saveRecentSearch(station.name);
          audioService.playRadioStation(station);
        },
        splashColor: _splashColor,
        highlightColor: _highlightColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              // Artwork with playing glow
              Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 52,
                    height: 52,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: isPlaying
                          ? Border.all(
                              color: Colors.deepPurple.shade400,
                              width: 2)
                          : null,
                      boxShadow: isPlaying
                          ? [
                              BoxShadow(
                                color: _glowShadow,
                                blurRadius: 10,
                                spreadRadius: 0,
                              )
                            ]
                          : null,
                    ),
                    child: hasArt
                        ? CachedNetworkImage(
                            imageUrl: station.artworkUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 104,
                            memCacheHeight: 104,
                            placeholder: (_, __) =>
                                _artPlaceholder(isRadio: true),
                            errorWidget: (_, __, ___) =>
                                _artPlaceholder(isRadio: true),
                          )
                        : _artPlaceholder(isRadio: true),
                  ),
                  if (isPlaying)
                    Positioned(
                      bottom: 1,
                      right: 1,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.black, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: TextStyle(
                        color: isPlaying
                            ? Colors.deepPurple.shade300
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (station.genre.isNotEmpty ||
                        station.country.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          [
                            if (station.genre.isNotEmpty)
                              station.genre,
                            if (station.country.isNotEmpty)
                              station.country,
                          ].join(' · '),
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              // Heart
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (isLiked) {
                    audioService.removeRadioFromPlaylist(
                        'favourite_radios', station);
                  } else {
                    audioService.addRadioToPlaylist(
                        'favourite_radios', station);
                  }
                },
                icon: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isLiked
                      ? Colors.deepPurple.shade400
                      : Colors.grey[700],
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artPlaceholder({required bool isRadio}) {
    return Container(
      color: isRadio ? const Color(0xFF1A0A2E) : Colors.grey[900],
      child: Icon(
        isRadio ? Icons.radio_rounded : Icons.music_note_rounded,
        color: isRadio ? Colors.deepPurple.shade800 : Colors.grey[700],
        size: isRadio ? 24 : 20,
      ),
    );
  }

  // ── Category card ─────────────────────────────────────────────────────────

  static const _categories = [
    (icon: Icons.music_note_rounded,  label: 'Jazz',    colors: [Color(0xFF2D1B69), Color(0xFF6D28D9)]),
    (icon: Icons.headset_rounded,     label: 'Dance',   colors: [Color(0xFF1E3A5F), Color(0xFF1D4ED8)]),
    (icon: Icons.mic_rounded,         label: 'Hip-Hop', colors: [Color(0xFF4A044E), Color(0xFFBE185D)]),
    (icon: Icons.bolt_rounded,        label: 'Rock',    colors: [Color(0xFF7C2D12), Color(0xFFEA580C)]),
    (icon: Icons.spa_rounded,         label: 'Chill',   colors: [Color(0xFF064E3B), Color(0xFF059669)]),
    (icon: Icons.star_rounded,        label: 'Pop',     colors: [Color(0xFF3B1278), Color(0xFF9333EA)]),
    (icon: Icons.public_rounded,      label: 'World',   colors: [Color(0xFF14532D), Color(0xFF16A34A)]),
    (icon: Icons.nights_stay_rounded, label: 'Ambient', colors: [Color(0xFF1C1917), Color(0xFF57534E)]),
  ];

  Widget _buildCategoryCard(int index) {
    final cat = _categories[index];
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cat.colors,
          ),
        ),
        child: InkWell(
          onTap: () => _searchCategory(cat.label),
          splashColor: const Color(0x1EFFFFFF),
          highlightColor: const Color(0x0AFFFFFF),
          child: Stack(
          children: [
            // Large watermark icon at bottom-right
            Positioned(
              bottom: -14,
              right: -14,
              child: Icon(
                cat.icon,
                size: 84,
                color: _categoryIconColor,
              ),
            ),
            // Genre label
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Text(
                cat.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                  shadows: [
                    Shadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _SkeletonLoader extends StatefulWidget {
  const _SkeletonLoader();
  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box({double? width, required double height, double radius = 5}) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xFF1E1E1E),
            const Color(0xFF2E2E2E),
            _anim.value,
          )!,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: List.generate(6, (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _box(width: 52, height: 52, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _box(height: 14, radius: 4)),
                    ]),
                    const SizedBox(height: 7),
                    _box(width: 130, height: 11, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }
}
