import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

Duration get platformLongPressDuration {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return const Duration(milliseconds: 300);
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return const Duration(milliseconds: 500);
  }
}

class PlatformGestureDetector extends StatelessWidget {
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureTapUpCallback? onSecondaryTapUp;
  final HitTestBehavior behavior;
  final Widget child;

  const PlatformGestureDetector({
    super.key,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapUp,
    this.behavior = HitTestBehavior.deferToChild,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    if (onTap != null || onSecondaryTapUp != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(),
        (instance) {
          instance.onTap = onTap;
          instance.onSecondaryTapUp = onSecondaryTapUp;
        },
      );
    }

    if (onLongPress != null || onLongPressStart != null) {
      gestures[LongPressGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: platformLongPressDuration),
        (instance) {
          instance.onLongPress = onLongPress;
          instance.onLongPressStart = onLongPressStart;
        },
      );
    }

    return RawGestureDetector(
      behavior: behavior,
      gestures: gestures,
      child: child,
    );
  }
}
