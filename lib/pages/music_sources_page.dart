import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings_model.dart';
import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../services/upnp_service.dart';
import '../services/webdav_service.dart';
import '../services/jellyfin_service.dart';
import '../widgets/voxel_toast.dart';
import 'network_browser_page.dart';

class MusicSourcesPage extends StatefulWidget {
  const MusicSourcesPage({super.key});

  @override
  State<MusicSourcesPage> createState() => _MusicSourcesPageState();
}

class _MusicSourcesPageState extends State<MusicSourcesPage> {
  // Local folders state
  bool _isScanning = false;
  bool _showManualEntry = false;
  final TextEditingController _manualController = TextEditingController();

  // Network servers state
  bool _isSearchingDevices = false;
  List<UpnpDevice> _discoveredDevices = [];

  static const List<_SuggestedPath> _suggestions = [
    _SuggestedPath('/storage/emulated/0/Music', 'Music', Icons.music_note_rounded),
    _SuggestedPath('/storage/emulated/0/Download', 'Downloads', Icons.download_rounded),
    _SuggestedPath('/storage/emulated/0/Documents', 'Documents', Icons.folder_rounded),
    _SuggestedPath('/storage/emulated/0/DCIM', 'DCIM', Icons.camera_alt_rounded),
    _SuggestedPath('/storage/emulated/0/Ringtones', 'Ringtones', Icons.notifications_rounded),
    _SuggestedPath('/storage/emulated/0/Podcasts', 'Podcasts', Icons.podcasts_rounded),
    _SuggestedPath('/storage/emulated/0/Audiobooks', 'Audiobooks', Icons.menu_book_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _searchDevices();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  // ─── Local Folder Scans ────────────────────────────────────────────────────

  Future<void> _pickDirectory() async {
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose a music folder',
      );
      if (result == null || !mounted) return;
      final settings = context.read<SettingsModel>();
      if (settings.sourcePaths.contains(result)) {
        VoxelToast.show(context, 'Folder already added',
            bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
        return;
      }
      await settings.addSourcePath(result);
      if (!mounted) return;
      VoxelToast.show(context, 'Added: ${_basename(result)}',
          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
    } catch (e) {
      if (!mounted) return;
      VoxelToast.show(context, 'Could not open folder picker: $e',
          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
    }
  }

  Future<void> _rescanLibrary() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      final settings = context.read<SettingsModel>();
      final entities = await StorageService().getAudioFiles(
        paths: settings.sourcePaths.toList(),
      );
      final files = entities.whereType<File>().toList();
      if (!mounted) return;
      context.read<AudioPlayerService>().loadOfflineFiles(files);
      VoxelToast.show(context,
          'Found ${files.length} audio file${files.length == 1 ? '' : 's'}',
          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
    } catch (e) {
      if (!mounted) return;
      VoxelToast.show(context, 'Scan failed: $e',
          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<bool> _confirmRemove(SettingsModel settings, String path) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Remove Folder?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
              const SizedBox(height: 10),
              Text(path,
                  style: TextStyle(fontSize: 13, fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Voxel will no longer scan this folder for music.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Remove',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    return confirmed ?? false;
  }

  // ─── UPnP & Network Search ─────────────────────────────────────────────────

  Future<void> _searchDevices() async {
    if (_isSearchingDevices) return;
    setState(() {
      _isSearchingDevices = true;
      _discoveredDevices = [];
    });
    try {
      final list = await UpnpService.discover();
      if (mounted) {
        setState(() {
          _discoveredDevices = list;
          _isSearchingDevices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingDevices = false);
        VoxelToast.show(context, 'Discovery error: $e',
            bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
      }
    }
  }

  Future<void> _addWebdavServerDialog() async {
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _WebdavServerDialog(scheme: scheme);
      },
    );
  }

  Future<void> _addJellyfinServerDialog() async {
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _JellyfinServerDialog(scheme: scheme);
      },
    );
  }

  Future<void> _confirmRemoveServer(String name, String id, {bool isJellyfin = false}) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Remove Server?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface)),
              const SizedBox(height: 10),
              Text(name, style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    child: const Text('Remove'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      if (isJellyfin) {
        await context.read<SettingsModel>().removeJellyfinServer(id);
      } else {
        await context.read<SettingsModel>().removeWebdavServer(id);
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _basename(String path) {
    final parts = path.split('/');
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 68,
          title: const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Music Sources',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          actions: [
            Consumer<SettingsModel>(
              builder: (context, settings, _) {
                final isDefault = _listsEqual(
                  settings.sourcePaths.toList(),
                  SettingsModel.defaultSourcePaths,
                );
                if (isDefault) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: TextButton(
                    onPressed: () async {
                      await settings.resetSourcePaths();
                      if (!context.mounted) return;
                      VoxelToast.show(context, 'Reset to defaults',
                          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0);
                    },
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  tabs: const [
                    Tab(text: 'Local Folders'),
                    Tab(text: 'Network Servers'),
                  ],
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: scheme.primaryContainer,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: scheme.onPrimaryContainer,
                  unselectedLabelColor: scheme.onSurfaceVariant.withOpacity(0.7),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Local Folders
            Consumer<SettingsModel>(
              builder: (context, settings, _) {
                final paths = settings.sourcePaths;
                final availableSuggestions =
                    _suggestions.where((s) => !paths.contains(s.path)).toList();

                final audioService = context.watch<AudioPlayerService>();
                final hasPlayer = audioService.isMiniPlayerVisible;
                final bottomPad = MediaQuery.of(context).padding.bottom +
                    kBottomNavigationBarHeight +
                    (hasPlayer ? 80.0 : 16.0);

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Voxel scans these folders to find your audio files. Changes take effect after rescanning.',
                          style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant, height: 1.45),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Browse & Add Folder'),
                          onPressed: _pickDirectory,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ),
                    if (availableSuggestions.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'QUICK ADD',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: availableSuggestions
                                    .map((s) => ActionChip(
                                          avatar: Icon(s.icon, size: 16, color: scheme.primary),
                                          label: Text(s.label),
                                          onPressed: () async {
                                            await settings.addSourcePath(s.path);
                                          },
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              'CONFIGURED FOLDERS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${paths.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer,
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
                          final path = paths[index];
                          final dirExists = Directory(path).existsSync();
                          final suggestion = _suggestions.firstWhere(
                            (s) => s.path == path,
                            orElse: () => _SuggestedPath(path, _basename(path), Icons.folder_rounded),
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: scheme.outlineVariant.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: dirExists ? scheme.primaryContainer : scheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(suggestion.icon,
                                        color: dirExists ? scheme.onPrimaryContainer : scheme.onErrorContainer, size: 22),
                                  ),
                                  title: Text(suggestion.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      dirExists ? path : '$path\n(folder not found)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: dirExists ? scheme.onSurfaceVariant : scheme.error,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.remove_circle_outline_rounded, color: scheme.error.withValues(alpha: 0.8)),
                                    tooltip: 'Remove',
                                    onPressed: () async {
                                      final confirmed = await _confirmRemove(settings, path);
                                      if (confirmed && mounted) {
                                        await settings.removeSourcePath(path);
                                        if (!mounted) return;
                                        VoxelToast.show(
                                          context,
                                          'Removed: ${suggestion.label}',
                                          bottomPadding: MediaQuery.of(context).padding.bottom + 85.0,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: paths.length,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: FilledButton.tonalIcon(
                          icon: _isScanning
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onSecondaryContainer,
                                  ))
                              : const Icon(Icons.refresh_rounded),
                          label: Text(_isScanning ? 'Scanning…' : 'Rescan Library'),
                          onPressed: _isScanning ? null : _rescanLibrary,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
                  ],
                );
              },
            ),

            // Tab 2: Network Servers
            Consumer<SettingsModel>(
              builder: (context, settings, _) {
                final webdavServers = settings.webdavServers;
                final jellyfinServers = settings.jellyfinServers;

                final audioService = context.watch<AudioPlayerService>();
                final hasPlayer = audioService.isMiniPlayerVisible;
                final bottomPad = MediaQuery.of(context).padding.bottom +
                    kBottomNavigationBarHeight +
                    (hasPlayer ? 80.0 : 16.0);

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // UPnP/DLNA Discovery Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DLNA / UPNP MEDIA SERVERS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            if (_isSearchingDevices)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: _searchDevices,
                              ),
                          ],
                        ),
                      ),
                    ),

                    // UPnP Discovered Devices List
                    if (_discoveredDevices.isEmpty && !_isSearchingDevices)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text(
                            'No media servers found on Wi-Fi. Pull down or tap refresh to scan.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _discoveredDevices.length) return null;
                            final device = _discoveredDevices[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.dns_rounded, color: scheme.onPrimaryContainer, size: 22),
                                    ),
                                    title: Text(device.friendlyName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        Uri.parse(device.location).host,
                                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                    trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => NetworkBrowserPage(upnpDevice: device),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: _discoveredDevices.length,
                        ),
                      ),

                    // File Servers Section Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'REMOTE FILE SERVERS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Server', style: TextStyle(fontSize: 12)),
                              onPressed: _addWebdavServerDialog,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Configured WebDAV Servers List
                    if (webdavServers.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text(
                            'No custom file servers configured yet. Add a WebDAV endpoint to stream files.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final server = webdavServers[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.cloud_rounded, color: scheme.onPrimaryContainer, size: 22),
                                    ),
                                    title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        server.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                      color: scheme.error.withValues(alpha: 0.8),
                                      onPressed: () => _confirmRemoveServer(server.name, server.id),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => NetworkBrowserPage(webdavConfig: server),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: webdavServers.length,
                        ),
                      ),

                    // Jellyfin Servers Section Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'JELLYFIN SERVERS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Jellyfin', style: TextStyle(fontSize: 12)),
                              onPressed: _addJellyfinServerDialog,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Configured Jellyfin Servers List
                    if (jellyfinServers.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text(
                            'No Jellyfin servers configured yet. Add a Jellyfin connection to stream music library.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final server = jellyfinServers[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.music_video_rounded, color: scheme.onPrimaryContainer, size: 22),
                                    ),
                                    title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${server.url} (${server.username})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                      color: scheme.error.withValues(alpha: 0.8),
                                      onPressed: () => _confirmRemoveServer(server.name, server.id, isJellyfin: true),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => NetworkBrowserPage(jellyfinConfig: server),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: jellyfinServers.length,
                        ),
                      ),

                    SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedPath {
  final String path;
  final String label;
  final IconData icon;
  const _SuggestedPath(this.path, this.label, this.icon);
}

class _WebdavServerDialog extends StatefulWidget {
  final ColorScheme scheme;

  const _WebdavServerDialog({required this.scheme});

  @override
  State<_WebdavServerDialog> createState() => _WebdavServerDialogState();
}

class _WebdavServerDialogState extends State<_WebdavServerDialog> {
  late final TextEditingController nameController;
  late final TextEditingController urlController;
  late final TextEditingController userController;
  late final TextEditingController passController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    urlController = TextEditingController(text: 'http://');
    userController = TextEditingController();
    passController = TextEditingController();
  }

  @override
  void dispose() {
    nameController.dispose();
    urlController.dispose();
    userController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: widget.scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: widget.scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Add WebDAV Server',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.scheme.onSurface)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Server Name (e.g. My NAS)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.100/dav/music/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userController,
                  decoration: const InputDecoration(
                    labelText: 'Username (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final url = urlController.text.trim();
                      if (name.isEmpty || url.isEmpty) {
                        VoxelToast.show(context, 'Please fill in name and URL',
                            bottomPadding: 16);
                        return;
                      }
                      
                      // Ensure trailing slash
                      final formattedUrl = url.endsWith('/') ? url : '$url/';

                      final config = WebdavServerConfig(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        url: formattedUrl,
                        username: userController.text.isNotEmpty ? userController.text : null,
                        password: passController.text.isNotEmpty ? passController.text : null,
                      );

                      await context.read<SettingsModel>().addWebdavServer(config);
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Server', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JellyfinServerDialog extends StatefulWidget {
  final ColorScheme scheme;

  const _JellyfinServerDialog({required this.scheme});

  @override
  State<_JellyfinServerDialog> createState() => _JellyfinServerDialogState();
}

class _JellyfinServerDialogState extends State<_JellyfinServerDialog> {
  late final TextEditingController urlController;
  late final TextEditingController userController;
  late final TextEditingController passController;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: 'http://');
    userController = TextEditingController();
    passController = TextEditingController();
  }

  @override
  void dispose() {
    urlController.dispose();
    userController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: widget.scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: widget.scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Add Jellyfin Server',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.scheme.onSurface)),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.100:8096',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isConnecting
                        ? null
                        : () async {
                            final url = urlController.text.trim();
                            final username = userController.text.trim();
                            final password = passController.text;

                            if (url.isEmpty || username.isEmpty) {
                              VoxelToast.show(context, 'Please fill in URL and Username',
                                  bottomPadding: 16);
                              return;
                            }

                            setState(() => _isConnecting = true);

                            try {
                              final config = await JellyfinService.authenticate(
                                url: url,
                                username: username,
                                password: password,
                              );

                              if (!mounted) return;
                              await context.read<SettingsModel>().addJellyfinServer(config);
                              if (mounted) {
                                VoxelToast.show(context, 'Jellyfin connected successfully!',
                                    bottomPadding: 16);
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (mounted) {
                                VoxelToast.show(context, 'Authentication failed: $e',
                                    bottomPadding: 16);
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isConnecting = false);
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Connect Jellyfin', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
