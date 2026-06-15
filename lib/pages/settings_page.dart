import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../widgets/voxel_toast.dart';
import '../services/services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final miniPlayerActive = audioService.isMiniPlayerVisible;
    final bottomInset = MediaQuery.of(context).padding.bottom +
        (miniPlayerActive ? 140.0 : 72.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomInset),
        children: [
          _buildSection(
            'Playback',
            [
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Gapless Playback'),
                    subtitle: const Text('Eliminate silence between tracks'),
                    value: settings.gaplessPlayback,
                    onChanged: (value) {
                      settings.setGaplessPlayback(value);
                    },
                  );
                },
              ),
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Normalize Volume'),
                    subtitle: const Text('Adjust volume across tracks'),
                    value: settings.normalizeVolume,
                    onChanged: (value) {
                      settings.setNormalizeVolume(value);
                    },
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            'Network',
            [
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Use Cellular Data'),
                    subtitle: const Text('Allow streaming on mobile networks'),
                    value: settings.useCellularData,
                    onChanged: (value) {
                      settings.setUseCellularData(value);
                    },
                  );
                },
              ),
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Offline Mode'),
                    subtitle:
                        const Text('Disable radio streaming over network'),
                    value: settings.offlineMode,
                    onChanged: (value) async {
                      settings.setOfflineMode(value);
                      if (value) {
                        await context.read<AudioPlayerService>().player.stop();
                      }
                    },
                  );
                },
              ),
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Data Saver Mode'),
                    subtitle: const Text('Prefer lower-bandwidth streams'),
                    value: settings.dataSaverMode,
                    onChanged: (value) {
                      settings.setDataSaverMode(value);
                    },
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            'Preferences',
            [
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Show Non-Music Genres'),
                    subtitle:
                        const Text('Display talk, news, and sports stations'),
                    value: settings.showNonMusicGenres,
                    onChanged: (value) {
                      settings.setShowNonMusicGenres(value);
                    },
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            'Maintenance',
            [
              ListTile(
                title: const Text('Clear App Cache'),
                subtitle: const Text(
                    'Clears all cached data: stations, genres, song metadata'),
                trailing: const Icon(Icons.cleaning_services_outlined),
                onTap: () async {
                  final bottomPad = MediaQuery.of(context).padding.bottom +
                      kBottomNavigationBarHeight +
                      (miniPlayerActive ? 70.0 : 0.0);
                  VoxelToast.show(
                    context,
                    'Clearing app cache...',
                    bottomPadding: bottomPad,
                  );
                  final settings = context.read<SettingsModel>();
                  final removed = await settings.clearAppCache();
                  if (!context.mounted) return;
                  VoxelToast.show(
                    context,
                    'Cleared $removed cached entries (stations/genres) and all song metadata',
                    bottomPadding: bottomPad,
                  );
                },
              ),
              ListTile(
                title: const Text('Update All Song Metadata'),
                subtitle: const Text(
                    'Fetches and updates metadata for all offline songs using iTunes'),
                trailing: const Icon(Icons.library_music_outlined),
                onTap: () async {
                  final bottomPad = MediaQuery.of(context).padding.bottom +
                      kBottomNavigationBarHeight +
                      (miniPlayerActive ? 70.0 : 0.0);
                  VoxelToast.show(
                    context,
                    'Updating all song metadata... (this may take a while)',
                    bottomPadding: bottomPad,
                  );
                  final audioService = context.read<AudioPlayerService>();
                  final metadataService = MetadataService();
                  final cache = SongMetadataCache();
                  await cache.initialize();
                  final files = audioService.getPlaylistSongs('offline');
                  int updated = 0;
                  for (final file in files) {
                    final oldSong = cache.createSongFromFile(file);
                    final newSong =
                        await metadataService.updateSongMetadata(oldSong);
                    await cache.saveMetadata(newSong);
                    updated++;
                  }
                  if (!context.mounted) return;
                  VoxelToast.show(
                    context,
                    'Updated metadata for $updated songs',
                    bottomPadding: bottomPad,
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            'About',
            [
              ListTile(
                title: const Text('App Version'),
                subtitle: const Text('1.0.0'),
              ),
              ListTile(
                title: const Text('Open Source Licenses'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'Voxel',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 24,
        thickness: 0.7,
        color: Colors.white24,
      ),
    );
  }
}
