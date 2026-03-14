import 'package:flutter/material.dart';

/// Chizze branded logo widget.
class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;

  const AppLogo({super.key, required this.size, this.borderRadius = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            // Match the logo's navy background for a natural depth shadow
            color: const Color(0xFF1B3A6E).withValues(alpha: 0.40),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Transform.scale(
          scale: 1.15,
          child: Image.asset(
            'assets/logo-new.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
