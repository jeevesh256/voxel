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
    final bottomInset = MediaQuery.of(context).padding.bottom + 16.0;

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomInset),
        children: [
          _buildSection(
            context,
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
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return SwitchListTile(
                    title: const Text('Expressive Play Button'),
                    subtitle: const Text('Morph and spin the button when active'),
                    value: settings.cookiePlayPauseEnabled,
                    onChanged: (value) {
                      settings.setCookiePlayPauseEnabled(value);
                    },
                  );
                },
              ),
            ],
          ),
          _buildSectionDivider(),
          _buildSection(
            context,
            'Preferences',
            [
              Builder(
                builder: (context) {
                  final settings = Provider.of<SettingsModel>(context);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(
                          'Accent Color',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 52,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: SettingsModel.accentPresets.length + 1,
                          itemBuilder: (context, index) {
                            if (index == SettingsModel.accentPresets.length) {
                              // Custom Color Picker Button
                              final isCustom = !SettingsModel.accentPresets.contains(settings.accentColor);
                              return GestureDetector(
                                onTap: () async {
                                  Color selectedColor = settings.accentColor;
                                  final newColor = await showDialog<Color>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Choose Accent Color'),
                                      content: Container(
                                        width: 280,
                                        child: GridView.count(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          crossAxisCount: 4,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          children: [
                                            Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                                            Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                                            Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                                            Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                                            Colors.brown, Colors.grey, Colors.blueGrey, const Color(0xFF7C5CBF),
                                          ].map((color) {
                                            return GestureDetector(
                                              onTap: () => Navigator.of(context).pop(color),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: settings.accentColor.value == color.value
                                                      ? Border.all(color: scheme.onSurface, width: 3)
                                                      : null,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: const Text('Cancel'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (newColor != null) {
                                    settings.setAccentColor(newColor);
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 16),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCustom ? settings.accentColor : scheme.surfaceContainerHigh,
                                    border: Border.all(
                                      color: isCustom ? scheme.onSurface : scheme.outline,
                                      width: isCustom ? 3 : 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.colorize_rounded,
                                    color: isCustom ? Colors.white : scheme.onSurfaceVariant,
                                    size: 18,
                                  ),
                                ),
                              );
                            }

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
                                      ? Border.all(color: scheme.onSurface, width: 3)
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
            context,
            'Haptics',
            [
              Builder(
                builder: (context) {
                  return ListTile(
                    title: const Text('Haptics Settings'),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
            context,
            'Maintenance',
            [
              ListTile(
                title: const Text('Clear App Cache'),
                trailing: Icon(Icons.cleaning_services_outlined, color: scheme.onSurfaceVariant),
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
                   if (context.mounted) {
                    final audio = context.read<AudioPlayerService>();
                    await audio.clearRecentlyPlayed();
                    await audio.clearHiddenRadiosAndTracks();
                  }
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
                trailing: Icon(Icons.library_music_outlined, color: scheme.onSurfaceVariant),
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
            context,
            'About',
            [
              const ListTile(
                title: Text('App Version'),
                subtitle: Text('1.0.0'),
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
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (context) => VoxelConfirmationSheet(
            title: title,
            content: content,
          ),
        ) ??
        false;
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSectionDivider() {
    return const Divider(height: 24, indent: 16, endIndent: 16);
  }
}

class HapticsSettingsPage extends StatelessWidget {
  const HapticsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Haptics Settings'),
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
          const Divider(height: 24, indent: 16, endIndent: 16),
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

  const VoxelConfirmationSheet({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Confirm',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // M3 drag handle
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14.5,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: scheme.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
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
    );
  }
}
