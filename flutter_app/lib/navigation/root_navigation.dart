import 'package:flutter/material.dart';

void popToRootRoute(BuildContext context) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator == null || !navigator.mounted) return;

  if (!navigator.canPop()) return;

  navigator.popUntil((route) => route.isFirst);
}
