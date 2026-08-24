import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared motion primitives.
///
/// Kept in one file so timing and curves stay consistent across screens —
/// previously each screen invented its own AnimationController with a
/// different duration, which is why the app felt uneven.
class Motion {
  Motion._();

  /// Entrance of a list item or card.
  static const Duration enter = Duration(milliseconds: 420);

  /// Small state flips: a chip selecting, a badge appearing.
  static const Duration quick = Duration(milliseconds: 180);

  /// Delay added per index in a staggered list.
  static const Duration stagger = Duration(milliseconds: 55);

  /// Deceleration curve used for anything entering the screen.
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Caps the stagger so item 40 does not wait two seconds.
  static Duration delayFor(int index, {int maxSteps = 8}) =>
      stagger * math.min(index, maxSteps);
}

/// Fades and lifts its child into place once, on first build.
///
/// Used for list items and dashboard sections. Pass [index] to stagger a run
/// of siblings.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration? delay;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.delay,
    this.offsetY = 24,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.enter);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Motion.enterCurve);

  @override
  void initState() {
    super.initState();
    final wait = widget.delay ?? Motion.delayFor(widget.index);
    if (wait == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Shrinks slightly while pressed. Gives cards and tiles a physical feel that
/// a bare InkWell does not.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.quick,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Counts from zero to [value] on first build, and animates between values
/// afterwards. Used for the host's stat tiles.
class AnimatedCount extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num)? format;

  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        format?.call(v) ?? v.round().toString(),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A softly pulsing grey block. Reads as "content is coming" rather than the
/// full-screen spinner that used to blank these screens out.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Shimmer({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 12,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
              Colors.grey.shade200, Colors.grey.shade100, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
