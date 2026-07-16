import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';

class SquishyButtonParams {
  final Widget? icon;
  final Widget? label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  const SquishyButtonParams({
    this.icon,
    this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onTap,
  });
}

/// A layout widget containing two squishy action buttons that interact physically.
/// When one button is pressed, it expands dynamically in width, and the neighbor
/// button's adjacent corners morph in sync to create a unified fluid surface.
class ExpressiveButtonRow extends StatefulWidget {
  final SquishyButtonParams left;
  final SquishyButtonParams right;
  final double leftFlex;
  final double rightFlex;
  final double height;

  const ExpressiveButtonRow({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 1.0,
    this.rightFlex = 1.0,
    this.height = 54.0,
  });

  @override
  State<ExpressiveButtonRow> createState() => _ExpressiveButtonRowState();
}

class _ExpressiveButtonRowState extends State<ExpressiveButtonRow>
    with TickerProviderStateMixin {
  late final AnimationController _leftCtrl = AnimationController(
    vsync: this,
    lowerBound: -0.20,
    upperBound: 1.20,
  );

  late final AnimationController _rightCtrl = AnimationController(
    vsync: this,
    lowerBound: -0.20,
    upperBound: 1.20,
  );

  bool _leftDown = false;
  bool _rightDown = false;
  Offset _leftDownPos = Offset.zero;
  Offset _rightDownPos = Offset.zero;

  @override
  void dispose() {
    _leftCtrl.dispose();
    _rightCtrl.dispose();
    super.dispose();
  }

  void _triggerHaptic(BuildContext context) {
    try {
      final settings = context.read<SettingsModel>();
      if (settings.hapticsEnabled && settings.hapticsOnButtonTaps) {
        HapticFeedback.lightImpact();
      }
    } catch (_) {
      HapticFeedback.lightImpact();
    }
  }

  void _springBack(AnimationController ctrl) {
    const desc = SpringDescription(mass: 0.8, stiffness: 450.0, damping: 20.0);
    ctrl.animateWith(SpringSimulation(desc, ctrl.value, 0.0, 0.0));
  }

  bool _isRouteDismissing(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return false;
    return !route.isCurrent || route.animation?.status == AnimationStatus.reverse;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_leftCtrl, _rightCtrl]),
      builder: (context, _) {
        final double tLeft = _leftCtrl.value.clamp(0.0, 1.0);
        final double tRight = _rightCtrl.value.clamp(0.0, 1.0);

        // Highly dramatic flex shift: pressed button expands significantly
        final double currentLeftFlex = widget.leftFlex + (tLeft * 0.9) - (tRight * 0.5);
        final double currentRightFlex = widget.rightFlex + (tRight * 0.9) - (tLeft * 0.5);

        // Morph corner radius properties
        final double pillR = widget.height / 2;
        const double pressedR = 8.0;
        const double pillInnerR = 5.0;
        const double pressedInnerR = 0.0;

        final double leftOuterR = lerpDouble(pillR, pressedR, tLeft)!;
        final double rightOuterR = lerpDouble(pillR, pressedR, tRight)!;

        final double maxT = tLeft > tRight ? tLeft : tRight;
        final double innerR = lerpDouble(pillInnerR, pressedInnerR, maxT)!;

        final leftBr = BorderRadius.only(
          topLeft: Radius.circular(leftOuterR),
          bottomLeft: Radius.circular(leftOuterR),
          topRight: Radius.circular(innerR),
          bottomRight: Radius.circular(innerR),
        );

        final rightBr = BorderRadius.only(
          topLeft: Radius.circular(innerR),
          bottomLeft: Radius.circular(innerR),
          topRight: Radius.circular(rightOuterR),
          bottomRight: Radius.circular(rightOuterR),
        );

        return Row(
          children: [
            // Left Button
            Expanded(
              flex: (currentLeftFlex * 1000).toInt().clamp(100, 10000),
              child: Listener(
                onPointerDown: (event) {
                  _triggerHaptic(context);
                  setState(() => _leftDown = true);
                  _leftDownPos = event.position;
                  _leftCtrl.animateTo(1.0, duration: const Duration(milliseconds: 90), curve: Curves.easeOutCubic);
                },
                onPointerUp: (event) {
                  if (_leftDown) {
                    setState(() => _leftDown = false);
                    _springBack(_leftCtrl);
                    if (_isRouteDismissing(context)) return;
                    final diff = (event.position - _leftDownPos).distance;
                    if (diff < 15.0) {
                      widget.left.onTap?.call();
                    }
                  }
                },
                onPointerCancel: (_) {
                  setState(() => _leftDown = false);
                  _springBack(_leftCtrl);
                },
                child: Transform.scale(
                  scale: lerpDouble(1.0, 0.93, tLeft)!,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: widget.left.backgroundColor,
                      borderRadius: leftBr,
                    ),
                    child: ClipRRect(
                      borderRadius: leftBr,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: _buildButtonContent(widget.left)),
                          _buildPressOverlay(_leftDown),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3), // The subtle seam between merged buttons
            // Right Button
            Expanded(
              flex: (currentRightFlex * 1000).toInt().clamp(100, 10000),
              child: Listener(
                onPointerDown: (event) {
                  _triggerHaptic(context);
                  setState(() => _rightDown = true);
                  _rightDownPos = event.position;
                  _rightCtrl.animateTo(1.0, duration: const Duration(milliseconds: 90), curve: Curves.easeOutCubic);
                },
                onPointerUp: (event) {
                  if (_rightDown) {
                    setState(() => _rightDown = false);
                    _springBack(_rightCtrl);
                    if (_isRouteDismissing(context)) return;
                    final diff = (event.position - _rightDownPos).distance;
                    if (diff < 15.0) {
                      widget.right.onTap?.call();
                    }
                  }
                },
                onPointerCancel: (_) {
                  setState(() => _rightDown = false);
                  _springBack(_rightCtrl);
                },
                child: Transform.scale(
                  scale: lerpDouble(1.0, 0.93, tRight)!,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: widget.right.backgroundColor,
                      borderRadius: rightBr,
                    ),
                    child: ClipRRect(
                      borderRadius: rightBr,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: _buildButtonContent(widget.right)),
                          _buildPressOverlay(_rightDown),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildButtonContent(SquishyButtonParams params) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (params.icon != null)
          IconTheme(
            data: IconThemeData(color: params.foregroundColor, size: 22),
            child: params.icon!,
          ),
        if (params.icon != null && params.label != null)
          const SizedBox(width: 8),
        if (params.label != null)
          Flexible(
            child: DefaultTextStyle(
              style: TextStyle(
                color: params.foregroundColor,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: params.label!,
            ),
          ),
      ],
    );
  }

  Widget _buildPressOverlay(bool isDown) {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: isDown ? 1.0 : 0.0,
        duration: isDown ? const Duration(milliseconds: 0) : const Duration(milliseconds: 100),
        child: Container(
          color: Colors.black.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

/// A pill-shaped action button with spring-animated corner morphing,
/// press scale-down, and haptic feedback.
class SquishyActionButton extends StatefulWidget {
  const SquishyActionButton({
    super.key,
    this.icon,
    this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onTap,
    this.isFirst = true,
    this.isLast = true,
    this.height = 54.0,
    this.neighborNotifier,
  }) : assert(icon != null || label != null,
            'Provide at least an icon or a label.');

  final Widget? icon;
  final Widget? label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;
  final double height;
  final ValueNotifier<double>? neighborNotifier;

  @override
  State<SquishyActionButton> createState() => _SquishyActionButtonState();
}

class _SquishyActionButtonState extends State<SquishyActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    lowerBound: -0.20,
    upperBound: 1.20,
  );

  bool _isDown = false;
  Offset _downPos = Offset.zero;

  double get _pillR => widget.height / 2;
  static const double _pressedR = 10.0;

  double get _t => _ctrl.value.clamp(0.0, 1.0);
  double get _scale => lerpDouble(1.0, 0.93, _t)!;

  BorderRadius get _br {
    final o = lerpDouble(_pillR, _pressedR, _t)!;
    return BorderRadius.circular(o);
  }

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
        widget.onTap?.call();
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
    return Listener(
      onPointerDown: _tapDown,
      onPointerUp: _tapUp,
      onPointerCancel: _tapCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final br = _br;
          return Transform.scale(
            scale: _scale,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: br,
              ),
              child: ClipRRect(
                borderRadius: br,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null)
                            IconTheme(
                              data: IconThemeData(
                                color: widget.foregroundColor,
                                size: 20,
                              ),
                              child: widget.icon!,
                            ),
                          if (widget.icon != null && widget.label != null)
                            const SizedBox(width: 6),
                          if (widget.label != null)
                            Flexible(
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: widget.foregroundColor,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                child: widget.label!,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _isDown ? 1.0 : 0.0,
                        duration: _isDown
                            ? const Duration(milliseconds: 0)
                            : const Duration(milliseconds: 100),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.18),
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
    );
  }
}

