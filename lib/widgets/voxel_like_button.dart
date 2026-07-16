import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class VoxelLikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback onPressed;
  final double iconSize;
  final Color? color;
  final Color? activeColor;

  const VoxelLikeButton({
    Key? key,
    required this.isLiked,
    required this.onPressed,
    this.iconSize = 24.0,
    this.color,
    this.activeColor,
  }) : super(key: key);

  @override
  State<VoxelLikeButton> createState() => _VoxelLikeButtonState();
}

class _VoxelLikeButtonState extends State<VoxelLikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    if (widget.isLiked) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant VoxelLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked != oldWidget.isLiked) {
      if (widget.isLiked) {
        _playSpringForward();
      } else {
        _controller.reverse();
      }
    }
  }

  void _playSpringForward() {
    final spring = const SpringDescription(
      mass: 1.0,
      stiffness: 180.0,
      damping: 15.0,
    );
    final simulation = SpringSimulation(spring, 0.0, 1.0, 0.0);
    _controller.animateWith(simulation);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final color = widget.color ?? Colors.white.withOpacity(0.8);

    return GestureDetector(
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double val = _controller.value;

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Unliked state: upright, outline heart with spring scale transition
              if (val < 0.5)
                Transform.scale(
                  scale: (1.0 - val * 2.0).clamp(0.0, 1.0),
                  child: Icon(
                    Icons.favorite_border_rounded,
                    color: color,
                    size: widget.iconSize,
                  ),
                ),
              // Liked state: upright, filled heart with spring scale transition
              if (val >= 0.5)
                Transform.scale(
                  scale: val,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: activeColor,
                    size: widget.iconSize,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
