import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class DameTickerWidget extends StatefulWidget {
  const DameTickerWidget({super.key});

  @override
  State<DameTickerWidget> createState() => _DameTickerWidgetState();
}

class _DameTickerWidgetState extends State<DameTickerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final DatabaseReference _tickerRef = FirebaseDatabase.instance.ref('dame_ticker');

  @override
  void initState() {
    super.initState();
    // Iyi controller niyo ituma amagambo agenda. 
    // Duhinduye 'duration' amagambo yagenda buhoro cyangwa vuba.
    _controller = AnimationController(
      duration: const Duration(seconds: 10), 
      vsync: this,
    )..repeat(); // Irongera igasubiramo iyo irangije
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _tickerRef.onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.snapshot.value as Map;
        final bool isActive = data['isActive'] ?? false;
        final String message = data['message'] ?? "";

        if (!isActive || message.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 30,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.8),
            border: const Border(
              top: BorderSide(color: Colors.purpleAccent, width: 0.5),
              bottom: BorderSide(color: Colors.purpleAccent, width: 0.5),
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    // Ibi nibyo bituma amagambo akora scrolling
                    right: -500 + (_controller.value * (MediaQuery.of(context).size.width + 500)),
                    child: Center(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}