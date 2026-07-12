import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import '../widgets/voxel_toast.dart';
import '../services/services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom + 16.0;

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
            'Preferences',
            [
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(
                          'Accent Color',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 52,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: SettingsModel.accentPresets.length,
                          itemBuilder: (context, index) {
                            final preset = SettingsModel.accentPresets[index];
                            final isSelected = settings.accentColor.value == preset.value;
                            return GestureDetector(
                              onTap: () => settings.setAccentColor(preset),
                              child: Container(
                                margin: const EdgeInsets.only(right: 16),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: preset,
                                  border: isSelected
                                      ? Border.all(color: Colors.white, width: 3)
                                      : null,
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: preset.withOpacity(0.5),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            'Haptics',
            [
              Builder(
                builder: (context) {
                  return ListTile(
                    title: const Text('Haptics Settings'),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HapticsSettingsPage(),
                        ),
                      );
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
                trailing: const Icon(Icons.cleaning_services_outlined),
                onTap: () async {
                  final confirm = await _showConfirmDialog(
                    context,
                    'Clear Cache',
                    'Are you sure you want to clear the app cache? This will reset all cached radio stations and song metadata.',
                  );
                  if (!confirm) return;

                  final bottomPad = MediaQuery.of(context).padding.bottom + 8.0;
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
                    'Cleared $removed cached entries and all song metadata',
                    bottomPadding: bottomPad,
                  );
                },
              ),
              ListTile(
                title: const Text('Update All Song Metadata'),
                trailing: const Icon(Icons.library_music_outlined),
                onTap: () async {
                  final confirm = await _showConfirmDialog(
                    context,
                    'Update Metadata',
                    'Are you sure you want to update metadata for all songs? This fetches details from iTunes and may take a moment.',
                  );
                  if (!confirm) return;

                  final bottomPad = MediaQuery.of(context).padding.bottom + 8.0;
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

  Future<bool> _showConfirmDialog(
      BuildContext context, String title, String content) async {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (context) => VoxelConfirmationSheet(
            title: title,
            content: content,
            accentColor: settings.accentColor,
          ),
        ) ??
        false;
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

class HapticsSettingsPage extends StatelessWidget {
  const HapticsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Haptics Settings'),
        backgroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          Builder(
            builder: (context) {
              final settings = Provider.of<SettingsModel>(context);
              return SwitchListTile(
                title: const Text('Haptic Feedback'),
                value: settings.hapticsEnabled,
                onChanged: (value) {
                  settings.setHapticsEnabled(value);
                },
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(color: Colors.white24, thickness: 0.7),
          ),
          Builder(
            builder: (context) {
              final settings = Provider.of<SettingsModel>(context);
              return SwitchListTile(
                title: const Text('Button Taps'),
                value: settings.hapticsOnButtonTaps,
                onChanged: settings.hapticsEnabled
                    ? (value) {
                        settings.setHapticsOnButtonTaps(value);
                      }
                    : null,
              );
            },
          ),
          Builder(
            builder: (context) {
              final settings = Provider.of<SettingsModel>(context);
              return SwitchListTile(
                title: const Text('Likes'),
                value: settings.hapticsOnLikes,
                onChanged: settings.hapticsEnabled
                    ? (value) {
                        settings.setHapticsOnLikes(value);
                      }
                    : null,
              );
            },
          ),
          Builder(
            builder: (context) {
              final settings = Provider.of<SettingsModel>(context);
              return SwitchListTile(
                title: const Text('Long Press'),
                value: settings.hapticsOnLongPress,
                onChanged: settings.hapticsEnabled
                    ? (value) {
                        settings.setHapticsOnLongPress(value);
                      }
                    : null,
              );
            },
          ),
          Builder(
            builder: (context) {
              final settings = Provider.of<SettingsModel>(context);
              return SwitchListTile(
                title: const Text('Slider Scrubbing'),
                value: settings.hapticsOnSliderScrubbing,
                onChanged: settings.hapticsEnabled
                    ? (value) {
                        settings.setHapticsOnSliderScrubbing(value);
                      }
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class VoxelConfirmationSheet extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final Color accentColor;

  const VoxelConfirmationSheet({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Confirm',
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1F).withOpacity(0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
