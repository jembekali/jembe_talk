import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

// Iyi ni class nshya izajya itanga animation nziza kandi yitonze
// Aho gukoresha MaterialPageRoute, tuzajya dukoresha iyi.
class CustomPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  CustomPageRoute({required this.child})
      : super(
          // Igihe animation yo kwinjira imara. Ushobora kongera iyi 'milliseconds'
          // niba ushaka ko igenda buhoro cyane kurushaho.
          transitionDuration: const Duration(milliseconds: 700),
          
          // Igihe animation yo gusohoka imara
          reverseTransitionDuration: const Duration(milliseconds: 400),
          
          pageBuilder: (context, animation, secondaryAnimation) => child,
          
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Hano niho duhitamo ubwoko bwa animation.
            // 'FadeScaleTransition' ituma paji nshya iza igaragara buhoro (fade)
            // kandi yiyongera ubunini (scale).
            return FadeScaleTransition(
              animation: animation,
              child: child,
            );
          },
        );
}