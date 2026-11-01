import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme.dart';

const destinations =
    <({String label, String path, IconData icon, IconData active})>[
      (
        label: '社区',
        path: '/',
        icon: Icons.forum_outlined,
        active: Icons.forum_rounded,
      ),
      (
        label: '广场',
        path: '/gallery',
        icon: Icons.widgets_outlined,
        active: Icons.widgets_rounded,
      ),
      (
        label: '发现',
        path: '/discover',
        icon: Icons.explore_outlined,
        active: Icons.explore_rounded,
      ),
      (
        label: '消息',
        path: '/messages',
        icon: Icons.chat_bubble_outline_rounded,
        active: Icons.chat_bubble_rounded,
      ),
      (
        label: '我的',
        path: '/me',
        icon: Icons.person_outline_rounded,
        active: Icons.person_rounded,
      ),
    ];

class DestinationTransitions extends StatefulWidget {
  const DestinationTransitions({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  State<DestinationTransitions> createState() => _DestinationTransitionsState();
}

class _DestinationTransitionsState extends State<DestinationTransitions> {
  int direction = 0;

  @override
  void didUpdateWidget(DestinationTransitions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location == oldWidget.location) return;
    final from = destinations.indexWhere((d) => d.path == oldWidget.location);
    final to = destinations.indexWhere((d) => d.path == widget.location);
    direction = from >= 0 && to >= 0 ? to.compareTo(from) : 0;
  }

  @override
  Widget build(BuildContext context) =>
      _DestinationDirection(direction: direction, child: widget.child);
}

class _DestinationDirection extends InheritedWidget {
  const _DestinationDirection({required this.direction, required super.child});

  final int direction;

  static int of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DestinationDirection>()
          ?.direction ??
      0;

  @override
  bool updateShouldNotify(_DestinationDirection oldWidget) =>
      direction != oldWidget.direction;
}

Page<void> destinationPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: motionDuration(context, 400),
  reverseTransitionDuration: motionDuration(context, 400),
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      _DestinationTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
);

class _DestinationTransition extends StatefulWidget {
  const _DestinationTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation, secondaryAnimation;
  final Widget child;

  @override
  State<_DestinationTransition> createState() => _DestinationTransitionState();
}

class _DestinationTransitionState extends State<_DestinationTransition> {
  int? entryDirection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 保留入场方向，连续切换时不会把尚未完成的入场动画突然翻转。
    entryDirection ??= _DestinationDirection.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final direction = _DestinationDirection.of(context);
    if (direction == 0 || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return DualTransitionBuilder(
      animation: widget.animation,
      forwardBuilder: (_, animation, child) =>
          _motion(animation, entryDirection!, entering: true, child: child),
      reverseBuilder: (_, animation, child) =>
          _motion(animation, direction, entering: false, child: child),
      child: DualTransitionBuilder(
        animation: ReverseAnimation(widget.secondaryAnimation),
        forwardBuilder: (_, animation, child) =>
            _motion(animation, direction, entering: true, child: child),
        reverseBuilder: (_, animation, child) =>
            _motion(animation, direction, entering: false, child: child),
        child: widget.child,
      ),
    );
  }

  Widget _motion(
    Animation<double> animation,
    int direction, {
    required bool entering,
    required Widget? child,
  }) {
    final progress = animation.drive(CurveTween(curve: motionCurve));
    return FadeTransition(
      opacity: entering
          ? progress
          : progress.drive(Tween<double>(begin: 1, end: 0)),
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            40 * direction * (entering ? 1 - progress.value : -progress.value),
            0,
          ),
          child: child,
        ),
        child: child,
      ),
    );
  }
}
