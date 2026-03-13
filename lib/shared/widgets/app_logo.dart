import 'package:flutter/material.dart';

/// Chizze branded logo widget.
///
/// The source JPEG has a white canvas with the navy rounded-square logo
/// centered inside it. [BoxFit.cover] fills a square container from the
/// landscape image (clipping the wide white left/right margins), and
/// [Transform.scale] zooms in slightly to remove the remaining thin
/// white strip at the top and bottom.
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
          // Zoom in 18 % so the white canvas margins are clipped away
          scale: 1.18,
          child: Image.asset(
            'assets/logo.jpeg',
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
