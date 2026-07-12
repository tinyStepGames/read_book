import 'package:flutter/material.dart';

PageRoute<T> noAnimationRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (
      context,
      animation,
      secondaryAnimation,
    ) {
      return page;
    },
    transitionsBuilder: (
      context,
      animation,
      secondaryAnimation,
      child,
    ) {
      return child;
    },
  );
}
