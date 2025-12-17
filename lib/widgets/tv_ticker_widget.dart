// lib/widgets/tv_ticker_widget.dart (YAKOSOWE: UMUVUDUKO MUKE)

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class TvTickerWidget extends StatefulWidget {
  const TvTickerWidget({super.key});

  @override
  State<TvTickerWidget> createState() => _TvTickerWidgetState();
}

class _TvTickerWidgetState extends State<TvTickerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _scrollController;
  String _message = "";
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    // =================================================================
    // HANO NIHO TWAHINDURIYE UMUVUDUKO
    // Twawushize kuri 35 seconds. Ubu biragenda buhoro cyane.
    // =================================================================
    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 35), 
    );
    _scrollController.repeat();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('tv_ticker').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          _message = data['message'] ?? '';
          _isActive = data['isActive'] ?? false;
        } else {
          _isActive = false;
        }

        if (!_isActive || _message.isEmpty) {
          return const SizedBox.shrink();
        }

        // AGACE KAMEZE NK'IKIRAHURI (GLASS)
        return Container(
          width: double.infinity,
          height: 40, 
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1), 
            border: const Border(
              top: BorderSide(color: Colors.white12, width: 1),
              bottom: BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ClipRect(
                child: AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, child) {
                    final double startPos = constraints.maxWidth;
                    // Twongereye intera (padding) inyuma kugira ngo hatabaho icyuho kinini
                    final double endPos = -(_message.length * 10.0) - 200; 
                    final double currentPos = startPos - (startPos - endPos) * _scrollController.value;

                    return Stack(
                      children: [
                        Positioned(
                          left: currentPos,
                          top: 9, 
                          child: Text(
                            _message,
                            style: const TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: 1.1,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 3.0,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}