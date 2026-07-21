import 'dart:ui' show lerpDouble;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/settings_model.dart';
import '../services/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'voxel_toast.dart';
import 'squishy_action_button.dart';
import 'player_theme_wrapper.dart';

class SongMenuOption {
  final IconData icon;
  final String title;
  final Color? color;
  final FutureOr<dynamic> Function() onTap;

  const SongMenuOption({
    required this.icon,
    required this.title,
    this.color,
    required this.onTap,
  });
}

class SongMenuSheet extends StatefulWidget {
  final Song song;
  final Color accentColor;
  final List<SongMenuOption> options;
  final IconData? rightButtonIcon;
  final Color? rightButtonColor;
  final VoidCallback? onRightButtonTap;
  final VoidCallback? onPlayTap;

  const SongMenuSheet({
    super.key,
    required this.song,
    required this.accentColor,
    required this.options,
    this.rightButtonIcon,
    this.rightButtonColor,
    this.onRightButtonTap,
    this.onPlayTap,
  });

  @override
  State<SongMenuSheet> createState() => _SongMenuSheetState();
}

class _SongMenuSheetState extends State<SongMenuSheet> {
  int _activeTab = 0; // 0 = OPTIONS, 1 = INFO
  final PageController _pageController = PageController(initialPage: 0);
  late Song _song;

  @override
  void initState() {
    super.initState();
    _song = widget.song;
  }

  @override
  void didUpdateWidget(SongMenuSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song != widget.song) {
      setState(() {
        _song = widget.song;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getFileSizeAndFormat() {
    try {
      final file = File(widget.song.filePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        final mb = bytes / (1024 * 1024);
        final ext = widget.song.filePath.split('.').last.toUpperCase();
        return '${mb.toStringAsFixed(1)} MB • $ext';
      }
    } catch (_) {}
    return 'Unknown';
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showToast(String message) {
    VoxelToast.show(
      context,
      message,
    );
  }

  double _calculateOptionsHeight({
    required SongMenuOption? nextOpt,
    required SongMenuOption? playlistOpt,
    required SongMenuOption? editOpt,
    required SongMenuOption? soundOpt,
    required SongMenuOption? deleteOpt,
  }) {
    double height = 0.0;
    // Row 1: Play + Like (always visible)
    height += 54.0;
    // Margin
    height += 8.0;

    // Row 2: Add to queue [ + Next ] (always visible)
    height += 54.0;

    // Row 3: Playlist [ + Edit Info ] (conditional)
    if (playlistOpt != null || editOpt != null) {
      height += 8.0; // Margin from Row 2
      height += 54.0;
    }

    // Row 4: Set as sound (conditional)
    if (soundOpt != null) {
      height += 8.0; // Margin from Row 3
      height += 54.0;
    }

    // Row 5: Remove / Delete (conditional)
    if (deleteOpt != null) {
      height += 8.0; // Margin from Row 4
      height += 54.0;
    }

    return height;
  }

  double _getTabHeight() {
    if (_activeTab == 1) {
      return 280.0; // Fixed size for the 4 info cards
    }

    // Helper to find options by keyword
    SongMenuOption? findOpt(String keyword) {
      for (final opt in widget.options) {
        final title = opt.title.toLowerCase();
        if (title.contains(keyword)) return opt;
      }
      return null;
    }

    final playlistOpt = findOpt('playlist');
    final nextOpt = findOpt('next') ?? findOpt('play next');
    final editOpt = findOpt('metadata') ?? findOpt('edit');
    final soundOpt = findOpt('sound') ?? findOpt('ringtone');

    SongMenuOption? deleteOpt;
    for (final opt in widget.options) {
      final title = opt.title.toLowerCase();
      if (title.contains('remove') || title.contains('delete')) {
        deleteOpt = opt;
        break;
      }
    }

    return _calculateOptionsHeight(
      nextOpt: nextOpt,
      playlistOpt: playlistOpt,
      editOpt: editOpt,
      soundOpt: soundOpt,
      deleteOpt: deleteOpt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.read<AudioPlayerService>();

    // Helper to find options by keyword
    SongMenuOption? findOpt(String keyword) {
      for (final opt in widget.options) {
        final title = opt.title.toLowerCase();
        if (title.contains(keyword)) return opt;
      }
      return null;
    }

    // Map options
    final likeOpt = findOpt('liked');
    final playlistOpt = findOpt('playlist');
    final queueOpt = widget.options.firstWhere(
      (opt) => opt.title.toLowerCase().contains('queue') && !opt.title.toLowerCase().contains('next'),
      orElse: () => SongMenuOption(
        icon: Icons.queue_music_rounded,
        title: 'Add to queue',
        onTap: () {
          audioService.playFileInContext(File(widget.song.filePath), [File(widget.song.filePath)]);
        },
      ),
    );
    final nextOpt = findOpt('next') ?? findOpt('play next');
    final editOpt = findOpt('metadata') ?? findOpt('edit');
    final soundOpt = findOpt('sound') ?? findOpt('ringtone');

    SongMenuOption? deleteOpt;
    for (final opt in widget.options) {
      final title = opt.title.toLowerCase();
      if (title.contains('remove') || title.contains('delete')) {
        deleteOpt = opt;
        break;
      }
    }

    return PlayerThemeWrapper(
      artPath: _song.albumArt,
      fallbackColor: widget.accentColor,
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
              // Legibly tinted background using a blend of the song's color and the dynamic dark surface
              final backgroundColor = Color.lerp(extractedColor, scheme.surfaceContainerHigh, 0.85) ?? scheme.surfaceContainerHigh;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
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

                    // Header: Album Art + Song Details (Title & Artist)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_song.albumArt.isNotEmpty && (_song.albumArt.startsWith('http://') || _song.albumArt.startsWith('https://')))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: Container(
                                color: const Color(0xFF121212),
                                child: CachedNetworkImage(
                                  imageUrl: _song.albumArt,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: Colors.white.withOpacity(0.05)),
                                  errorWidget: (_, __, ___) => Icon(Icons.music_note_rounded, size: 28, color: scheme.onPrimaryContainer),
                                ),
                              ),
                            )
                          else if (_song.albumArt.isNotEmpty && File(_song.albumArt).existsSync())
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: Container(
                                color: const Color(0xFF121212),
                                child: Image.file(
                                  File(_song.albumArt),
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          else () {
                            final isPlaylist = _song.artist.toLowerCase() == 'playlist';
                            final fallbackIcon = isPlaylist ? Icons.queue_music_rounded : Icons.music_note_rounded;
                            return Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                fallbackIcon,
                                size: 28,
                                color: scheme.onPrimaryContainer,
                              ),
                            );
                          }(),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _song.title,
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
                                  _song.artist,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant.withOpacity(0.7),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      height: _getTabHeight(),
                      child: PageView(
                        physics: const NeverScrollableScrollPhysics(),
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _activeTab = index;
                          });
                        },
                        children: [
                          _buildOptionsTab(
                            scheme: scheme,
                            audioService: audioService,
                            likeOpt: likeOpt,
                            playlistOpt: playlistOpt,
                            queueOpt: queueOpt,
                            nextOpt: nextOpt,
                            editOpt: editOpt,
                            deleteOpt: deleteOpt,
                            soundOpt: soundOpt,
                          ),
                          _buildInfoTab(scheme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tab Bar Controller at the very bottom (Capsule container matching buttons above)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            _SquishyTabButton(
                              isActive: _activeTab == 0,
                              activeColor: scheme.primaryContainer,
                              onTap: () {
                                if (_activeTab != 0) {
                                  _pageController.animateToPage(
                                    0,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOutCubic,
                                  );
                                }
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.menu_rounded,
                                    color: _activeTab == 0 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'OPTIONS',
                                    style: TextStyle(
                                      color: _activeTab == 0 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _SquishyTabButton(
                              isActive: _activeTab == 1,
                              activeColor: scheme.primaryContainer,
                              onTap: () {
                                if (_activeTab != 1) {
                                  _pageController.animateToPage(
                                    1,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOutCubic,
                                  );
                                }
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: _activeTab == 1 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'INFO',
                                    style: TextStyle(
                                      color: _activeTab == 1 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
  }

  Widget _buildOptionsTab({
    required ColorScheme scheme,
    required AudioPlayerService audioService,
    required SongMenuOption? likeOpt,
    required SongMenuOption? playlistOpt,
    required SongMenuOption queueOpt,
    required SongMenuOption? nextOpt,
    required SongMenuOption? editOpt,
    required SongMenuOption? deleteOpt,
    required SongMenuOption? soundOpt,
  }) {
    return StatefulBuilder(
      builder: (context, stateSetter) {
        final isLiked = audioService.isFileLiked(_song.filePath);

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Row 1: Play (wide) + Like / unlike (narrow) ────────────────
              ExpressiveButtonRow(
                leftFlex: 3.0,
                rightFlex: 1.0,
                left: SquishyButtonParams(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  onTap: () {
                    if (widget.onPlayTap != null) {
                      widget.onPlayTap!();
                    } else {
                      _showToast('Playing song');
                      audioService.playFileInContext(
                          File(_song.filePath),
                          [File(_song.filePath)]);
                    }
                  },
                ),
                right: widget.rightButtonIcon != null
                    ? SquishyButtonParams(
                        icon: Icon(widget.rightButtonIcon),
                        label: const SizedBox.shrink(),
                        backgroundColor: scheme.surfaceContainerHighest,
                        foregroundColor: widget.rightButtonColor ?? scheme.onSurface,
                        onTap: () {
                          if (widget.onRightButtonTap != null) {
                            widget.onRightButtonTap!();
                            stateSetter(() {});
                            setState(() {});
                          }
                        },
                      )
                    : SquishyButtonParams(
                        icon: Icon(isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded),
                        backgroundColor: scheme.surfaceContainerHighest,
                        foregroundColor: isLiked ? scheme.primary : scheme.onSurface,
                        onTap: () {
                          _showToast(isLiked
                              ? 'Removed from Library'
                              : 'Added to Library');
                          if (likeOpt != null) {
                            likeOpt.onTap();
                          } else {
                            audioService.toggleLikeFile(_song.filePath);
                          }
                          stateSetter(() {});
                          setState(() {});
                        },
                      ),
              ),
              const SizedBox(height: 8),

              // ── Row 2: Add to queue  [+ Play Next] ─────────────────────────
              if (nextOpt != null) ...[
                ExpressiveButtonRow(
                  leftFlex: 1.0,
                  rightFlex: 1.0,
                  left: SquishyButtonParams(
                    icon: const Icon(Icons.queue_music_rounded),
                    label: const Text('Add to queue'),
                    backgroundColor: scheme.tertiaryContainer,
                    foregroundColor: scheme.onTertiaryContainer,
                    onTap: () {
                      _showToast('Added to queue');
                      queueOpt.onTap();
                    },
                  ),
                  right: SquishyButtonParams(
                    icon: const Icon(Icons.playlist_play_rounded),
                    label: const Text('Next'),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    onTap: () {
                      _showToast('Play Next queued');
                      nextOpt.onTap();
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ] else ...[
                SquishyActionButton(
                  icon: const Icon(Icons.queue_music_rounded),
                  label: const Text('Add to queue'),
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  onTap: () {
                    _showToast('Added to queue');
                    queueOpt.onTap();
                  },
                ),
                const SizedBox(height: 8),
              ],

              // ── Row 3: Playlist [+ Edit Info] ──────────────────────────────
              if (playlistOpt != null || editOpt != null) ...[
                if (playlistOpt != null && editOpt != null)
                  ExpressiveButtonRow(
                    leftFlex: 1.0,
                    rightFlex: 1.0,
                    left: SquishyButtonParams(
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('Playlist'),
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.onSurface,
                      onTap: () => playlistOpt.onTap(),
                    ),
                    right: SquishyButtonParams(
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Edit Info'),
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.onSurface,
                      onTap: () async {
                        Navigator.of(context).pop(); // Dismiss menu sheet first
                        await editOpt.onTap();
                      },
                    ),
                  )
                else if (playlistOpt != null)
                  SquishyActionButton(
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('Playlist'),
                    backgroundColor: scheme.surfaceContainerHighest,
                    foregroundColor: scheme.onSurface,
                    onTap: () => playlistOpt.onTap(),
                  )
                else
                  SquishyActionButton(
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Edit Info'),
                    backgroundColor: scheme.surfaceContainerHighest,
                    foregroundColor: scheme.onSurface,
                    onTap: () async {
                      Navigator.of(context).pop(); // Dismiss menu sheet first
                      await editOpt!.onTap();
                    },
                  ),
                const SizedBox(height: 8),
              ],

              // ── Row 4: Set as ringtone ───────────────────────────────────
              if (soundOpt != null) ...[
                SquishyActionButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  label: const Text('Set as sound'),
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurface,
                  onTap: () {
                    _showToast('Ringtone updated');
                    soundOpt.onTap();
                  },
                ),
                const SizedBox(height: 8),
              ],

              // ── Row 5: Remove / Delete ───────────────────────────────────
              if (deleteOpt != null)
                SquishyActionButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: Text(deleteOpt.title),
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  onTap: () {
                    _showToast('Removed');
                    deleteOpt.onTap();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTab(ColorScheme scheme) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildInfoCard(
            scheme: scheme,
            icon: Icons.timer_outlined,
            label: 'DURATION',
            value: _formatDuration(_song.duration),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            scheme: scheme,
            icon: Icons.album_outlined,
            label: 'ALBUM',
            value: _song.album.isNotEmpty ? _song.album : 'Unknown Album',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            scheme: scheme,
            icon: Icons.donut_large_rounded,
            label: 'FILE FORMAT & SIZE',
            value: _getFileSizeAndFormat(),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            scheme: scheme,
            icon: Icons.folder_open_outlined,
            label: 'FILE PATH',
            value: _song.filePath,
            trailing: IconButton(
              icon: Icon(Icons.copy_rounded, color: scheme.onSurfaceVariant.withOpacity(0.7), size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _song.filePath));
                VoxelToast.show(
                  context,
                  'Path copied to clipboard',
                  icon: Icons.copy_rounded,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.12), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant.withOpacity(0.7), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _SquishyTabButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isActive;
  final Color activeColor;

  const _SquishyTabButton({
    required this.child,
    required this.onTap,
    required this.isActive,
    required this.activeColor,
  });

  @override
  State<_SquishyTabButton> createState() => _SquishyTabButtonState();
}

class _SquishyTabButtonState extends State<_SquishyTabButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    lowerBound: -0.20,
    upperBound: 1.20,
  );

  bool _isDown = false;
  Offset _downPos = Offset.zero;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _tapDown(PointerDownEvent event) {
    try {
      final settings = context.read<SettingsModel>();
      if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
        HapticFeedback.lightImpact();
      }
    } catch (_) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _isDown = true;
      _downPos = event.position;
    });
    _ctrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
    );
  }

  void _tapUp(PointerUpEvent event) {
    if (_isDown) {
      setState(() => _isDown = false);
      _springBack();
      if (_isRouteDismissing(context)) return;
      final diff = (event.position - _downPos).distance;
      if (diff < 15.0) {
        widget.onTap();
      }
    }
  }

  void _tapCancel(PointerCancelEvent _) {
    setState(() => _isDown = false);
    _springBack();
  }

  bool _isRouteDismissing(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return false;
    return !route.isCurrent || route.animation?.status == AnimationStatus.reverse;
  }

  void _springBack() {
    const desc = SpringDescription(mass: 0.8, stiffness: 450.0, damping: 20.0);
    _ctrl.animateWith(SpringSimulation(desc, _ctrl.value, 0.0, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Listener(
        onPointerDown: _tapDown,
        onPointerUp: _tapUp,
        onPointerCancel: _tapCancel,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final double scale = lerpDouble(1.0, 0.93, _ctrl.value.clamp(0.0, 1.0))!;
            final double borderRadiusVal = lerpDouble(23.0, 12.0, _ctrl.value.clamp(0.0, 1.0))!;
            
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: widget.isActive ? widget.activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(borderRadiusVal),
                ),
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadiusVal),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: widget.child),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _isDown ? 1.0 : 0.0,
                          duration: _isDown ? const Duration(milliseconds: 0) : const Duration(milliseconds: 100),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


