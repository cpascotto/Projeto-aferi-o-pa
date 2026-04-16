import 'package:flutter/material.dart';

class TotemBackButton extends StatelessWidget {
  const TotemBackButton({
    super.key,
    required this.onPressed,
    this.foregroundColor = Colors.white,
    this.backgroundColor = const Color(0x33000000),
  });

  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            Icons.arrow_back_rounded,
            color: foregroundColor,
            size: 34,
          ),
        ),
      ),
    );
  }
}
