import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:m3e_buttons/m3e_buttons.dart';

class VoxelPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;

  const VoxelPlayPauseButton({
    Key? key,
    required this.isPlaying,
    required this.onPressed,
    this.size = 72.0,
  }) : super(key: key);

  @override
  State<VoxelPlayPauseButton> createState() => _VoxelPlayPauseButtonState();
}

class _VoxelPlayPauseButtonState extends State<VoxelPlayPauseButton> with TickerProviderStateMixin {
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late final AnimationController _pressController = AnimationController(
    vsync: this,
    lowerBound: -0.15,
    upperBound: 1.15,
  );

  late final Animation<double> _bounceAnimation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 1.05).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40.0,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.05, end: 0.98).chain(CurveTween(curve: Curves.easeIn)),
      weight: 30.0,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.98, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30.0,
    ),
  ]).animate(_bounceController);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant VoxelPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _bounceController.forward(from: 0.0);
    }
  }

  Timer? _longPressTimer;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _bounceController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _longPressTimer?.cancel();
    
    // Smoothly scale down first (0.0 -> 0.15 progress)
    _pressController.animateTo(
      0.15,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );

    _longPressTimer = Timer(const Duration(milliseconds: 250), () {
      // Continue smoothly from 0.15 to 1.0 (morph to cookie shape) with spring
      const desc = SpringDescription(mass: 1.0, stiffness: 150.0, damping: 20.0);
      _pressController.animateWith(SpringSimulation(desc, _pressController.value, 1.0, 0.0));
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _handleRelease();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _handleRelease();
  }

  void _handleRelease() {
    _longPressTimer?.cancel();
    // Smooth spring back to 0.0 (rest circle and full scale)
    const desc = SpringDescription(mass: 1.0, stiffness: 180.0, damping: 22.0);
    _pressController.animateWith(SpringSimulation(desc, _pressController.value, 0.0, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressController, _bounceAnimation]),
        builder: (context, child) {
          final double pressVal = _pressController.value.clamp(0.0, 1.0);
          final double scale = lerpDouble(1.0, 0.94, pressVal)! * _bounceAnimation.value;
          
          final clipper = PlayPauseCookieClipper(
            progress: pressVal,
            size: widget.size,
          );

          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: ClipPath(
                clipper: clipper,
                child: RepaintBoundary(
                  child: M3EButton(
                    onPressed: widget.onPressed,
                    style: M3EButtonStyle.filled,
                    shape: M3EButtonShape.round,
                    decoration: M3EButtonDecoration(
                      backgroundColor: WidgetStateProperty.all(primary),
                      padding: EdgeInsets.zero,
                      fixedSize: Size(widget.size, widget.size),
                      minimumSize: Size(widget.size, widget.size),
                      borderRadius: widget.size / 2,
                      pressedRadius: widget.size / 2,
                      motion: M3EMotion.standardSpatialDefault,
                    ),
                    child: Icon(
                      widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: widget.size * 0.45,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PlayPauseCookieClipper extends CustomClipper<Path> {
  final double progress;
  final double size;

  PlayPauseCookieClipper({required this.progress, required this.size});

  @override
  Path getClip(Size sizeVal) {
    final double w = sizeVal.width;
    final double h = sizeVal.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double maxR = min(w, h) / 2;

    // Very gentle wave amplitude for extremely smooth/pillowy 7-sided cookie lobes
    final double amp = maxR * 0.065;
    final double avgR = maxR - amp;

    final Path path = Path();
    const int totalPoints = 240; // High resolution sampling for perfectly smooth edges

    for (int i = 0; i < totalPoints; i++) {
      final double phi = (i * 2 * pi) / totalPoints;
      
      final double rCircle = maxR;
      // 7-sided cookie shape (cos(7 * phi))
      final double rCookie = avgR + amp * cos(7 * phi);
      
      final double r = lerpDouble(rCircle, rCookie, progress)!;
      
      final double x = cx + r * cos(phi);
      final double y = cy + r * sin(phi);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant PlayPauseCookieClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.size != size;
  }
}

class VoxelPlayerControlButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color? activeColor;

  const VoxelPlayerControlButton({
    Key? key,
    required this.child,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
  }) : super(key: key);

  @override
  State<VoxelPlayerControlButton> createState() => _VoxelPlayerControlButtonState();
}

class _VoxelPlayerControlButtonState extends State<VoxelPlayerControlButton> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  double _pressScale = 1.0;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 35.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 0.96).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35.0,
      ),
    ]).animate(_bounceController);
  }

  @override
  void didUpdateWidget(covariant VoxelPlayerControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive && widget.isActive) {
      _bounceController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final isEnabled = widget.onPressed != null;

    return Listener(
      onPointerDown: isEnabled ? (_) => setState(() => _pressScale = 0.88) : null,
      onPointerUp: isEnabled ? (_) => setState(() => _pressScale = 1.0) : null,
      onPointerCancel: isEnabled ? (_) => setState(() => _pressScale = 1.0) : null,
      child: AnimatedScale(
        scale: _pressScale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.4,
          child: AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _bounceAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      child: M3EButton(
                        onPressed: () {
                          _bounceController.forward(from: 0.0);
                          widget.onPressed?.call();
                        },
                        style: M3EButtonStyle.text,
                        shape: M3EButtonShape.round,
                        decoration: const M3EButtonDecoration(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          borderRadius: 24.0,
                          pressedRadius: 12.0,
                          motion: M3EMotion.expressiveSpatialFast,
                        ),
                        child: widget.child,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: widget.isActive ? 1.0 : 0.0,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                           shape: BoxShape.circle,
                           color: primary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class VoxelActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const VoxelActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<VoxelActionButton> createState() => _VoxelActionButtonState();
}

class _VoxelActionButtonState extends State<VoxelActionButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scale = 0.94),
      onPointerUp: (_) => setState(() => _scale = 1.0),
      onPointerCancel: (_) => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: 145,
          height: 44,
          child: RepaintBoundary(
            child: M3EButton.icon(
              onPressed: widget.onPressed,
              style: M3EButtonStyle.outlined,
              shape: M3EButtonShape.round,
              decoration: const M3EButtonDecoration(
                borderRadius: 24.0,
                pressedRadius: 12.0,
                motion: M3EMotion.expressiveSpatialFast,
              ),
              icon: Icon(
                widget.icon,
                size: 18,
                color: Colors.white.withOpacity(0.9),
              ),
              label: Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

