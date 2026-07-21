import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'photo_slideshow_page.dart';
import '../models/song.dart';
import '../models/settings_model.dart';
import '../services/song_metadata_cache.dart';
import '../services/audio_service.dart';
import '../services/upnp_service.dart';
import '../services/webdav_service.dart';
import '../services/jellyfin_service.dart';
import '../widgets/voxel_toast.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/edit_metadata_sheet.dart';
import '../widgets/player_theme_wrapper.dart';
import '../widgets/create_playlist_dialog.dart';

Future<T?> pushMaterialPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(builder: (context) => page),
  );
}

class NetworkBrowserPage extends StatefulWidget {
  final UpnpDevice? upnpDevice;
  final WebdavServerConfig? webdavConfig;
  final JellyfinServerConfig? jellyfinConfig;

  // Custom initial subfolder loading (for pinned folders)
  final String? initialObjectId;
  final String? initialUrl;
  final String? initialFolderName;

  // Pinned folder metadata for playlist-style display
  final PinnedNetworkFolder? pinnedFolder;

  const NetworkBrowserPage({
    super.key,
    this.upnpDevice,
    this.webdavConfig,
    this.jellyfinConfig,
    this.initialObjectId,
    this.initialUrl,
    this.initialFolderName,
    this.pinnedFolder,
  }) : assert(upnpDevice != null || webdavConfig != null || jellyfinConfig != null);

  @override
  State<NetworkBrowserPage> createState() => _NetworkBrowserPageState();
}

class _NetworkBrowserPageState extends State<NetworkBrowserPage> {
  bool _isLoading = true;
  String? _error;

  // Navigation stacks
  final List<String> _upnpIdStack = ['0'];
  final List<String> _upnpNameStack = ['Root'];

  final List<String> _webdavUrlStack = [];
  final List<String> _webdavNameStack = ['Root'];

  final List<String> _jellyfinIdStack = [];
  final List<String> _jellyfinNameStack = ['Root'];

  // Current view content
  List<BrowserItem> _items = [];

  // Items hidden by the user in this session
  final Set<String> _hiddenItemIds = {};

  // Scroll tracking for fade-in app bar
  final ScrollController _scrollController = ScrollController();
  bool _isConnectionError = false;

  @override
  void initState() {
    super.initState();
    _initializeStack();
    _loadCurrentDirectory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeStack() {
    if (widget.upnpDevice != null) {
      _upnpIdStack.clear();
      _upnpNameStack.clear();
      
      final startId = widget.initialObjectId ?? '0';
      _upnpIdStack.add(startId);
      _upnpNameStack.add(widget.initialFolderName ?? 'Root');
    } else if (widget.webdavConfig != null) {
      _webdavUrlStack.clear();
      _webdavNameStack.clear();
      
      final startUrl = widget.initialUrl ?? widget.webdavConfig!.url;
      _webdavUrlStack.add(startUrl);
      _webdavNameStack.add(widget.initialFolderName ?? 'Root');
    } else if (widget.jellyfinConfig != null) {
      _jellyfinIdStack.clear();
      _jellyfinNameStack.clear();

      final startId = widget.initialObjectId ?? 'root';
      _jellyfinIdStack.add(startId);
      _jellyfinNameStack.add(widget.initialFolderName ?? 'Root');
    }
  }


  Future<void> _loadCurrentDirectory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.upnpDevice != null) {
        final currentId = _upnpIdStack.last;
        final rawItems = await UpnpService.browse(widget.upnpDevice!.controlUrl, currentId);
        if (mounted) {
          setState(() {
            _items = rawItems
                .map((i) => BrowserItem(
                      id: i.id,
                      name: i.title,
                      isDirectory: i.isContainer,
                      streamUrl: i.streamUrl,
                      artist: i.artist,
                      album: i.album,
                      artworkUrl: i.artworkUrl,
                      type: i.type,
                    ))
                .toList();
            _isLoading = false;
          });
        }
      } else if (widget.webdavConfig != null) {
        final currentUrl = _webdavUrlStack.last;
        final rawItems = await WebdavService.list(widget.webdavConfig!, currentUrl);
        if (mounted) {
          setState(() {
            _items = rawItems
                .map((i) => BrowserItem(
                      id: i.path,
                      name: i.name,
                      isDirectory: i.isDirectory,
                      streamUrl: i.streamUrl,
                    ))
                .toList();
            _isLoading = false;
          });
        }
      } else if (widget.jellyfinConfig != null) {
        final currentId = _jellyfinIdStack.last;
        final List<JellyfinItem> rawItems;
        if (currentId == 'root') {
          rawItems = await JellyfinService.listLibraryViews(widget.jellyfinConfig!);
        } else {
          rawItems = await JellyfinService.listItems(widget.jellyfinConfig!, currentId);
        }

        if (mounted) {
          setState(() {
            _items = rawItems
                .map((i) => BrowserItem(
                      id: i.id,
                      name: i.name,
                      isDirectory: i.isDirectory,
                      streamUrl: i.streamUrl.isNotEmpty ? i.streamUrl : null,
                      artist: i.artist,
                      album: i.album,
                      artworkUrl: i.artworkUrl,
                      type: i.type,
                    ))
                .toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnectionError = e is UpnpConnectionException ||
              e is SocketException ||
              e is TimeoutException;
          _error = e is UpnpConnectionException
              ? e.message
              : e is SocketException
                  ? 'Cannot reach the server. Make sure it is on and connected to the same network.'
                  : e is TimeoutException
                      ? 'Connection timed out. The server may be busy or unreachable.'
                      : 'Failed to load folder. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateInto(BrowserItem item) {
    if (!item.isDirectory) return;
    if (widget.upnpDevice != null) {
      _upnpIdStack.add(item.id);
      _upnpNameStack.add(item.name);
    } else if (widget.webdavConfig != null) {
      _webdavUrlStack.add(item.id);
      _webdavNameStack.add(item.name);
    } else if (widget.jellyfinConfig != null) {
      _jellyfinIdStack.add(item.id);
      _jellyfinNameStack.add(item.name);
    }
    _loadCurrentDirectory();
  }

  bool _navigateBack() {
    if (widget.upnpDevice != null) {
      if (_upnpIdStack.length > 1) {
        _upnpIdStack.removeLast();
        _upnpNameStack.removeLast();
        if (mounted) _loadCurrentDirectory();
        return true;
      }
    } else if (widget.webdavConfig != null) {
      if (_webdavUrlStack.length > 1) {
        _webdavUrlStack.removeLast();
        _webdavNameStack.removeLast();
        if (mounted) _loadCurrentDirectory();
        return true;
      }
    } else if (widget.jellyfinConfig != null) {
      if (_jellyfinIdStack.length > 1) {
        _jellyfinIdStack.removeLast();
        _jellyfinNameStack.removeLast();
        if (mounted) _loadCurrentDirectory();
        return true;
      }
    }
    return false;
  }

  String get _currentFolderName {
    if (widget.upnpDevice != null) {
      return _upnpNameStack.last;
    } else if (widget.webdavConfig != null) {
      return _webdavNameStack.last;
    } else {
      return _jellyfinNameStack.last;
    }
  }

  Future<void> _playTrack(BrowserItem item) async {
    if (item.isDirectory || item.streamUrl == null) return;
    if (_isImageFile(item)) {
      VoxelToast.show(
        context,
        'Cannot open file',
      );
      return;
    }

    final audioService = context.read<AudioPlayerService>();

    // Include video files and audio files (ignoring only directories and images) in the playlist queue
    final tracks = _items.where((i) => !i.isDirectory && i.streamUrl != null && !_isImageFile(i)).toList();

    final List<File> playlistFiles = tracks
        .map((t) => File(t.streamUrl!))
        .toList();

    final metadataCache = SongMetadataCache();
    await metadataCache.initialize();

    for (final track in tracks) {
      if (track.streamUrl == null) continue;
      final virtualSong = Song(
        id: track.streamUrl!,
        filePath: track.streamUrl!,
        title: track.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac|mp4|mkv|avi|mov|webm)$', caseSensitive: false), ''),
        artist: track.artist ?? widget.upnpDevice?.friendlyName ?? widget.webdavConfig?.name ?? widget.jellyfinConfig?.name ?? 'Network Server',
        album: track.album ?? _currentFolderName,
        albumArt: track.artworkUrl ?? '',
      );
      await metadataCache.saveMetadata(virtualSong);
    }

    final selectedFile = File(item.streamUrl!);
    await audioService.playFileInContext(selectedFile, playlistFiles);
    
    if (mounted) {
      VoxelToast.show(
        context,
        'Streaming: ${item.name}',
      );
    }
  }

  static bool _isAudioFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg');
  }

  static bool _isImageFile(BrowserItem item) {
    if (item.type == 'Photo') return true;
    final lower = item.name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.svg');
  }

  static bool _isVideoFile(BrowserItem item) {
    if (item.type == 'Video') return true;
    final lower = item.name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  void _showTrackMenu(BrowserItem item) async {
    if (item.streamUrl == null) return;

    // Image files get a simplified menu (cannot be played)
    if (_isImageFile(item)) {
      _showNonAudioMenu(item);
      return;
    }

    final audioService = context.read<AudioPlayerService>();

    final virtualSong = Song(
      id: item.streamUrl!,
      filePath: item.streamUrl!,
      title: item.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|aac|flac)$', caseSensitive: false), ''),
      artist: item.artist ?? widget.upnpDevice?.friendlyName ?? widget.webdavConfig?.name ?? widget.jellyfinConfig?.name ?? 'Network Server',
      album: item.album ?? _currentFolderName,
      albumArt: item.artworkUrl ?? '',
    );

    // Save metadata immediately so liking and playlist displays show correct titles
    final metadataCache = SongMetadataCache();
    await metadataCache.initialize();
    await metadataCache.saveMetadata(virtualSong);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => SongMenuSheet(
        song: virtualSong,
        accentColor: Theme.of(context).colorScheme.primary,
        options: [
          SongMenuOption(
            icon: Icons.queue_music_rounded,
            title: 'Add to queue',
            onTap: () {
              audioService.addToQueue(virtualSong);
              VoxelToast.show(context, 'Added to queue');
            },
          ),
          SongMenuOption(
            icon: Icons.playlist_add_rounded,
            title: 'Add to custom playlist',
            onTap: () {
              _showAddToPlaylistSheet(virtualSong);
            },
          ),
          SongMenuOption(
            icon: Icons.edit_note_rounded,
            title: 'Edit metadata',
            onTap: () async {
              await EditMetadataSheet.show(
                context,
                virtualSong,
                File(virtualSong.filePath),
                Theme.of(context).colorScheme.primary,
              );
              if (mounted) {
                _loadCurrentDirectory();
              }
            },
          ),
        ],
      ),
    );
  }


  void _showNonAudioMenu(BrowserItem item) {
    final accentColor = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (ctx) {
        return PlayerThemeWrapper(
          artPath: null,
          fallbackColor: accentColor,
          parseArtwork: false,
          builder: (context, dynamicScheme, extractedColor) {
            return AnimatedTheme(
              data: Theme.of(context).copyWith(
                colorScheme: dynamicScheme,
                primaryColor: extractedColor,
              ),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: Builder(
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  final backgroundColor =
                      Color.lerp(extractedColor, scheme.surfaceContainerHigh, 0.85) ??
                          scheme.surfaceContainerHigh;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      20, 12, 20, MediaQuery.of(ctx).padding.bottom + 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag Handle
                        Container(
                          width: 38,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2.25),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // File name header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.image_not_supported_rounded,
                                    color: scheme.onSurfaceVariant, size: 26),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        color: scheme.onSurface,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cannot be played',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant.withOpacity(0.7),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Buttons row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: SizedBox(
                                  height: 54,
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Play',
                                        style: TextStyle(fontWeight: FontWeight.w600)),
                                    onPressed: null, // disabled for non-audio
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: SizedBox(
                                  height: 54,
                                  child: FilledButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      setState(() => _hiddenItemIds.add(item.id));
                                      VoxelToast.show(
                                        context,
                                        'File hidden',
                                      );
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: scheme.surfaceContainerHighest,
                                      foregroundColor: scheme.onSurface,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Icon(Icons.visibility_off_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }


  void _showAddToPlaylistSheet(Song song) {
    final audioService = context.read<AudioPlayerService>();
    final customPlaylists = audioService.customPlaylists;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4.5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Add to Playlist',
                style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.add, color: scheme.primary),
              title: const Text('Create New Playlist', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                _createNewPlaylistDialog(song);
              },
            ),
            if (customPlaylists.isNotEmpty) ...[
              const Divider(height: 20),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: customPlaylists.length,
                  itemBuilder: (c, idx) {
                    final playlist = customPlaylists[idx];
                    return ListTile(
                      leading: Icon(Icons.queue_music, color: scheme.primary),
                      title: Text(playlist.name),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await audioService.addSongToCustomPlaylist(playlist.id, File(song.filePath));
                        if (mounted) {
                          VoxelToast.show(context, 'Added to ${playlist.name}');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _createNewPlaylistDialog(Song song) async {
    final controller = TextEditingController();
    final scheme = Theme.of(context).colorScheme;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'My Playlist Name',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name != null && name.isNotEmpty) {
      final audioService = context.read<AudioPlayerService>();
      final newPlaylist = await audioService.createCustomPlaylist(name);
      await audioService.addSongToCustomPlaylist(newPlaylist.id, File(song.filePath));
      if (mounted) {
        VoxelToast.show(context, 'Created and added to $name');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverName = widget.upnpDevice?.friendlyName ?? widget.webdavConfig?.name ?? widget.jellyfinConfig?.name ?? 'Server';
    
    // Check if we are at the root level of navigation.
    final bool isAtRoot = widget.upnpDevice != null 
        ? _upnpIdStack.length == 1 
        : widget.webdavConfig != null
            ? _webdavUrlStack.length == 1
            : _jellyfinIdStack.length == 1;
    final folderName = (isAtRoot && widget.initialFolderName != null) 
        ? widget.initialFolderName! 
        : _currentFolderName;
    final pf = widget.pinnedFolder;

    final artworkPath = (isAtRoot && pf?.artworkPath?.isNotEmpty == true) ? pf!.artworkPath : null;
    final artworkColor = (isAtRoot && pf?.artworkColor != null) ? Color(pf!.artworkColor!) : null;

    return PopScope(
      canPop: isAtRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateBack();
      },
      child: PlayerThemeWrapper(
        artPath: artworkPath,
        fallbackColor: artworkColor,
        builder: (context, colorScheme, extractedColor) {
          final colorSubtle = extractedColor.withOpacity(0.7);
          final colorFaint = extractedColor.withOpacity(0.15);

          return Theme(
            data: Theme.of(context).copyWith(colorScheme: colorScheme),
            child: Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;

                return Scaffold(
                  backgroundColor: scheme.surface,
                  extendBodyBehindAppBar: true,
                  appBar: PreferredSize(
                    preferredSize: const Size.fromHeight(kToolbarHeight + 12),
                    child: AnimatedBuilder(
                      animation: _scrollController,
                      builder: (context, _) {
                        final hasValidClient = _scrollController.hasClients &&
                            _scrollController.positions.length == 1;
                        final offset = hasValidClient ? _scrollController.offset : 0.0;
                        final opacity = (offset / 340.0).clamp(0.0, 1.0);
                        return AppBar(
                          backgroundColor: scheme.surface.withOpacity(opacity),
                          elevation: 0,
                          surfaceTintColor: Colors.transparent,
                          toolbarHeight: kToolbarHeight + 12,
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () {
                              if (!_navigateBack()) Navigator.pop(context);
                            },
                          ),
                          actions: [
                            Consumer<SettingsModel>(
                              builder: (context, settings, _) {
                                final folderId = widget.upnpDevice != null
                                    ? '${widget.upnpDevice!.location}_${_upnpIdStack.isNotEmpty ? _upnpIdStack.last : "0"}'
                                    : widget.webdavConfig != null
                                        ? '${widget.webdavConfig!.id}_${_webdavUrlStack.isNotEmpty ? _webdavUrlStack.last : ""}'
                                        : '${widget.jellyfinConfig!.id}_${_jellyfinIdStack.isNotEmpty ? _jellyfinIdStack.last : ""}';
                                final isPinned = settings.pinnedFolders.any((f) => f.id == folderId);
                                  return IconButton(
                                    icon: Icon(
                                      isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                      color: Colors.white,
                                    ),
                                  tooltip: isPinned ? 'Unpin Folder' : 'Pin Folder',
                                  onPressed: () async {
                                    if (isPinned) {
                                      await settings.unpinNetworkFolder(folderId);
                                      if (mounted) {
                                        VoxelToast.show(context, 'Folder unpinned from Library');
                                      }
                                    } else {
                                      final randColor = kPlaylistColors[math.Random().nextInt(kPlaylistColors.length)];
                                      final folder = PinnedNetworkFolder(
                                        id: folderId,
                                        name: _currentFolderName,
                                        type: widget.upnpDevice != null
                                            ? 'upnp'
                                            : widget.webdavConfig != null
                                                ? 'webdav'
                                                : 'jellyfin',
                                        serverId: widget.upnpDevice?.location ??
                                            widget.webdavConfig?.id ??
                                            widget.jellyfinConfig!.id,
                                        serverName: widget.upnpDevice?.friendlyName ??
                                            widget.webdavConfig?.name ??
                                            widget.jellyfinConfig!.name,
                                        path: widget.upnpDevice != null
                                            ? _upnpIdStack.last
                                            : widget.webdavConfig != null
                                                ? _webdavUrlStack.last
                                                : _jellyfinIdStack.last,
                                        controlUrl: widget.upnpDevice?.controlUrl,
                                        artworkColor: randColor.value,
                                      );
                                      await settings.pinNetworkFolder(folder);
                                      if (mounted) {
                                        VoxelToast.show(context, 'Folder pinned to Library');
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  body: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(color: scheme.primary),
                          )
                        : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: _isConnectionError
                                              ? scheme.surfaceContainerHigh
                                              : scheme.errorContainer,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          _isConnectionError
                                              ? Icons.wifi_off_rounded
                                              : Icons.error_outline_rounded,
                                          size: 40,
                                          color: _isConnectionError
                                              ? scheme.onSurfaceVariant
                                              : scheme.onErrorContainer,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        _isConnectionError
                                            ? 'Server Unreachable'
                                            : 'Something Went Wrong',
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      FilledButton.icon(
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Try Again'),
                                        onPressed: _loadCurrentDirectory,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : CustomScrollView(
                                key: ValueKey(
                                  widget.upnpDevice != null
                                      ? (_upnpIdStack.isNotEmpty ? _upnpIdStack.last : '0')
                                      : widget.webdavConfig != null
                                          ? (_webdavUrlStack.isNotEmpty ? _webdavUrlStack.last : 'dav')
                                          : (_jellyfinIdStack.isNotEmpty ? _jellyfinIdStack.last : 'jelly'),
                                ),
                                controller: _scrollController,
                              slivers: [
                                // ── Hero Header ────────────────────────────────────────
                                SliverToBoxAdapter(
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 380,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              scheme.surfaceContainerLow,
                                              scheme.surface,
                                            ],
                                          ),
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // Artwork or gradient background
                                            if (artworkPath != null)
                                              Image.file(
                                                File(artworkPath),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => _buildHeroGradient(colorSubtle, colorFaint),
                                              )
                                            else
                                              _buildHeroGradient(colorSubtle, colorFaint),
                                            // Dark gradient overlay
                                            Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  stops: const [0.0, 0.6, 1.0],
                                                  colors: [
                                                    scheme.surface.withValues(alpha: 0.1),
                                                    scheme.surface.withValues(alpha: 0.6),
                                                    scheme.surface,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Folder name + server info pinned to bottom of hero
                                      Positioned(
                                        left: 24,
                                        right: 24,
                                        bottom: 24,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              folderName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 40,
                                                fontWeight: FontWeight.w900,
                                                height: 1.05,
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.cloud_rounded,
                                                  size: 14,
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    serverName,
                                                    style: TextStyle(
                                                      color: scheme.onSurfaceVariant,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Items List ───────────────────────────────────────

                                if (_items.isEmpty)
                                  SliverFillRemaining(
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.folder_open_rounded, size: 48, color: scheme.onSurfaceVariant),
                                          const SizedBox(height: 12),
                                          Text('Empty folder', style: TextStyle(color: scheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  SliverList.builder(
                                    itemCount: _items.where((i) => !_hiddenItemIds.contains(i.id)).length,
                                    itemBuilder: (context, idx) {
                                      final visibleItems = _items.where((i) => !_hiddenItemIds.contains(i.id)).toList();
                                      final item = visibleItems[idx];
                                      final isImage = !item.isDirectory && _isImageFile(item);
                                      final isVideo = !item.isDirectory && _isVideoFile(item);
                                      return _NetworkBrowserTile(
                                        item: item,
                                        isImage: isImage,
                                        isVideo: isVideo,
                                        accentColor: extractedColor,
                                        onTap: () {
                                          if (item.isDirectory) {
                                            _navigateInto(item);
                                          } else if (isImage) {
                                            final imagesOnly = visibleItems.where((i) => !i.isDirectory && _isImageFile(i)).toList();
                                            final initialImgIdx = imagesOnly.indexWhere((img) => img.id == item.id);
                                            pushMaterialPage(
                                              context,
                                              PhotoSlideshowPage(
                                                items: imagesOnly,
                                                initialIndex: initialImgIdx >= 0 ? initialImgIdx : 0,
                                              ),
                                            );
                                          } else {
                                            _playTrack(item);
                                          }
                                        },
                                        onMoreTap: () => _showTrackMenu(item),
                                      );
                                    },
                                  ),

                                // Bottom padding
                                SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: MediaQuery.of(context).padding.bottom + 100,
                                  ),
                                ),
                              ],
                            ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroGradient(Color colorSubtle, Color colorFaint) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorSubtle, colorFaint],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.cloud_queue_rounded,
          size: 110,
          color: Colors.white.withOpacity(0.12),
        ),
      ),
    );
  }
}

class BrowserItem {
  final String id;
  final String name;
  final bool isDirectory;
  final String? streamUrl;
  final String? artist;
  final String? album;
  final String? artworkUrl;
  final String? type;

  BrowserItem({
    required this.id,
    required this.name,
    required this.isDirectory,
    this.streamUrl,
    this.artist,
    this.album,
    this.artworkUrl,
    this.type,
  });
}

/// A playlist-style tile for items inside a NetworkBrowserPage.
class _NetworkBrowserTile extends StatelessWidget {
  final BrowserItem item;
  final bool isImage;
  final bool isVideo;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _NetworkBrowserTile({
    super.key,
    required this.item,
    required this.isImage,
    required this.isVideo,
    required this.accentColor,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Read active track to highlight the currently playing track
    final audioService = context.watch<AudioPlayerService>();
    final activeTrack = audioService.currentTrack;
    final isPlaying = !item.isDirectory && !isImage && activeTrack != null && activeTrack.id == item.streamUrl;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 0),
      horizontalTitleGap: 12,
      leading: _buildLeading(scheme, context, isPlaying),
      title: Text(
        item.isDirectory
            ? item.name
            : item.name.replaceAll(
                RegExp(r'\.(mp3|m4a|wav|aac|flac|ogg)$', caseSensitive: false), ''),
        style: TextStyle(
          color: isPlaying ? scheme.primary : Colors.white,
          fontWeight: (item.isDirectory || isPlaying) ? FontWeight.w500 : FontWeight.normal,
          fontSize: 14.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildSubtitle(scheme),
      trailing: item.isDirectory
          ? const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.chevron_right_rounded),
            )
          : IconButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[400]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: onMoreTap,
            ),
      onTap: onTap,
      onLongPress: () {
        final settings = Provider.of<SettingsModel>(context, listen: false);
        if (settings.hapticsEnabled) {
          HapticFeedback.mediumImpact();
        }
        if (!item.isDirectory) onMoreTap();
      },
    );
  }

  Widget _buildLeading(ColorScheme scheme, BuildContext context, bool isPlaying) {
    if (item.isDirectory) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: scheme.primaryContainer,
        ),
        child: Icon(
          Icons.folder_rounded,
          color: scheme.onPrimaryContainer,
          size: 24,
        ),
      );
    }

    if (isImage) {
      if (item.artworkUrl != null && item.artworkUrl!.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Image.network(
              item.artworkUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.image_rounded, color: scheme.onSurfaceVariant, size: 24),
              ),
            ),
          ),
        );
      }
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(Icons.image_rounded,
            color: scheme.onSurfaceVariant, size: 24),
      );
    }

    if (isVideo) {
      if (item.artworkUrl != null && item.artworkUrl!.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Image.network(
              item.artworkUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.movie_creation_outlined, color: scheme.onSurfaceVariant, size: 24),
              ),
            ),
          ),
        );
      }
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(Icons.movie_creation_outlined,
            color: scheme.onSurfaceVariant, size: 24),
      );
    }

    if (item.artworkUrl != null && item.artworkUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Image.network(
            item.artworkUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: scheme.primary.withOpacity(0.12),
              child: Icon(
                isPlaying ? Icons.play_arrow_rounded : Icons.music_note_rounded,
                color: scheme.primary,
                size: 24,
              ),
            ),
          ),
        ),
      );
    }

    // Audio file — show fallback playlist style tile
    return Container(
      height: 50,
      width: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: scheme.primary.withOpacity(0.12),
      ),
      child: Center(
        child: Icon(
          isPlaying ? Icons.play_arrow_rounded : Icons.music_note_rounded,
          color: scheme.primary,
          size: 24,
        ),
      ),
    );
  }


  Widget? _buildSubtitle(ColorScheme scheme) {
    if (item.isDirectory) return null;
    return Text(
      isImage
          ? 'Image file'
          : isVideo
              ? 'Video file'
              : item.artist ?? 'Streamable audio',
      style: TextStyle(
        fontSize: 12,
        color: isImage
            ? scheme.onSurfaceVariant.withOpacity(0.5)
            : Colors.grey.shade400,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
