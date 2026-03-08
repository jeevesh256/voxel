import 'dart:async';
import 'package:flutter/material.dart';

/// Production-quality toast that instantly replaces itself on repeated calls.
/// No animation queue — works like Spotify / Apple Music toasts.
class VoxelToast {
  VoxelToast._();

  static final GlobalKey<_VoxelToastWidgetState> _key =
      GlobalKey<_VoxelToastWidgetState>();
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Show a toast.
  ///
  /// [bottomPadding] — distance from the bottom edge of the screen
  /// (include kBottomNavigationBarHeight + safe area + mini-player height).
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    double? bottomPadding,
  }) {
    _timer?.cancel();

    final state = _key.currentState;
    if (state != null) {
      // Already visible — just update text and reset the timer; no re-animation.
      state.update(message);
    } else {
      _entry?.remove();
      _entry = OverlayEntry(
        builder: (_) => _VoxelToastWidget(
          key: _key,
          initialMessage: message,
          bottomPadding: bottomPadding,
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
  final double? bottomPadding;
  final VoidCallback onDismissed;

  const _VoxelToastWidget({
    super.key,
    required this.initialMessage,
    required this.onDismissed,
    this.bottomPadding,
  });

  @override
  State<_VoxelToastWidget> createState() => _VoxelToastWidgetState();
}

class _VoxelToastWidgetState extends State<_VoxelToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  late String _message;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Update message without re-animating.
  void update(String message) {
    if (mounted) setState(() => _message = message);
  }

  /// Fade out, then notify parent to remove the overlay entry.
  void dismiss() {
    if (!mounted) return;
    _controller
        .animateTo(0,
            duration: const Duration(milliseconds: 180), curve: Curves.easeIn)
        .whenCompleteOrCancel(() {
      widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = widget.bottomPadding ??
        mq.padding.bottom + kBottomNavigationBarHeight + 8.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _slide,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade400,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
