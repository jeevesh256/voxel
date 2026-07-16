import 'dart:async';
import 'package:flutter/material.dart';

/// Non-disruptive pill-style overlay toast.
/// Floats above all content, IgnorePointer so taps pass straight through.
/// Replaces itself instantly on rapid-fire calls (no queue).
class VoxelToast {
  VoxelToast._();

  static final GlobalKey<_VoxelToastWidgetState> _key =
      GlobalKey<_VoxelToastWidgetState>();
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Show a toast pill.
  ///
  /// [bottomPadding] — distance from bottom of screen.
  /// [icon] — optional leading icon inside the pill.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    double? bottomPadding,
    IconData? icon,
  }) {
    _timer?.cancel();

    final resolvedPadding =
        bottomPadding ?? (MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 8.0);

    final state = _key.currentState;
    if (state != null) {
      // Already visible — just swap text, no re-animation.
      state.update(message, icon);
    } else {
      _entry?.remove();
      _entry = OverlayEntry(
        builder: (_) => _VoxelToastWidget(
          key: _key,
          initialMessage: message,
          initialIcon: icon,
          bottomPadding: resolvedPadding,
          onDismissed: _cleanup,
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_entry!);
    }

    _timer = Timer(duration, () => _key.currentState?.dismiss());
  }

  static void _cleanup() {
    _entry?.remove();
    _entry = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VoxelToastWidget extends StatefulWidget {
  final String initialMessage;
  final IconData? initialIcon;
  final double? bottomPadding;
  final VoidCallback onDismissed;

  const _VoxelToastWidget({
    super.key,
    required this.initialMessage,
    required this.onDismissed,
    this.initialIcon,
    this.bottomPadding,
  });

  @override
  State<_VoxelToastWidget> createState() => _VoxelToastWidgetState();
}

class _VoxelToastWidgetState extends State<_VoxelToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late String _message;
  IconData? _icon;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _icon = widget.initialIcon;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void update(String message, IconData? icon) {
    if (mounted) setState(() { _message = message; _icon = icon; });
  }

  void dismiss() {
    if (!mounted) return;
    _controller
        .animateTo(0,
            duration: const Duration(milliseconds: 160), curve: Curves.easeIn)
        .whenCompleteOrCancel(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = widget.bottomPadding ??
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 8.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.bottomCenter,
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_icon != null) ...[
                        Icon(_icon, color: scheme.onInverseSurface, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          _message,
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
