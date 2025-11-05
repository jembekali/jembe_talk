// In lib/loading_screen.dart
// IYI NI CODE YUZUYE NEZA 100% IKOSORA AMAKOSA YOSE

import 'dart:math';
// =============================================================
// >>>>> UYU NI WO MURONGO W'INGENZI WARI WABUZEMO <<<<<
// =============================================================
import 'package:flutter/material.dart';

class LoadingScreen extends StatefulWidget {
  final String channelName;
  final Future<void> Function() onLoadingComplete;

  const LoadingScreen({
    super.key,
    required this.channelName,
    required this.onLoadingComplete,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _startLoading();
  }

  Future<void> _startLoading() async {
    await Future.delayed(const Duration(seconds: 3));
    
    if (mounted) {
      await widget.onLoadingComplete();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return ClipPath(
                  clipper: CircleWaveClipper(_controller.value),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            Text(
              "Mukanya gato urabona:",
              style: const TextStyle(color: Colors.white70, fontSize: 20, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            Text(
              widget.channelName,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class CircleWaveClipper extends CustomClipper<Path> {
  final double value;
  CircleWaveClipper(this.value);

  @override
  Path getClip(Size size) {
    final path = Path();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2;

    path.addOval(Rect.fromCircle(center: Offset(centerX, centerY), radius: radius));

    final waveHeight = 10.0;
    
    final path2 = Path();
    path2.moveTo(0, centerY);
    for (double i = 0; i < size.width; i++) {
      path2.lineTo(i, centerY + waveHeight * 0.5 * (1 + sin(i / size.width * 2 * pi + value * 2 * pi)));
    }
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    
    return Path.combine(PathOperation.intersect, path, path2);
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}