// lib/widgets/chat/chat_game_manager.dart (FIXED OVERFLOW & REMOVED REDUNDANT BUTTONS)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// --- SERVICES & WIDGETS ---
import '../../language_provider.dart';
import '../../dame_game_widget.dart';

class ChatGameManager extends StatelessWidget {
  final bool isPreparingInvitation;
  final bool isWaitingForGameAcceptance;
  final Map<String, dynamic>? currentGameData;
  final String chatRoomID;
  final String receiverEmail;
  final VoidCallback onSendInvitation;
  final VoidCallback onCancelInvitation;
  final VoidCallback onStopGame;

  const ChatGameManager({
    super.key,
    required this.isPreparingInvitation,
    required this.isWaitingForGameAcceptance,
    required this.currentGameData,
    required this.chatRoomID,
    required this.receiverEmail,
    required this.onSendInvitation,
    required this.onCancelInvitation,
    required this.onStopGame,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    Widget? gameWidget;

    // -------------------------------------------------------------------------
    // 1. INVITATION MODE (Iyo uri gutegura ubutumire)
    // -------------------------------------------------------------------------
    if (isPreparingInvitation) {
      final previewBoard = List.generate(10, (row) {
        return List.generate(10, (col) {
          if ((row + col) % 2 != 0) {
            if (row < 4) return {'player': 2, 'type': 'man'};
            if (row > 5) return {'player': 1, 'type': 'man'};
          }
          return null;
        });
      });

      gameWidget = Container(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ✅ Ibi bituma container itabyibuha cyane
          children: [
            // HEADER (Gahunda y'ubutumire)
            SizedBox(
              height: 45, // Nagabanyije height
              child: isWaitingForGameAcceptance
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text(lang.t('dame_invitation_sent'), style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                      ],
                    )
                  : Center(
                      child: Text(
                        lang.t('dame_send_invitation_header'), 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
                      )
                    ),
            ),

            // IKIBAHO (DameGameWidget)
            // ✅ Ubu DameGameWidget yakuwemo utubuto twayo imbere muri version 15.5
            DameGameWidget(
              key: const ValueKey('invitation_preview'),
              chatRoomID: chatRoomID,
              gameData: {'board': previewBoard, 'status': 'preview'},
              isInvitation: true,
              isWaiting: isWaitingForGameAcceptance,
            ),

            // FOOTER BUTTONS (Zazamutse kugira ngo overflow ishira)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // BUTTON OYA / CANCEL
                  ElevatedButton.icon(
                    onPressed: onCancelInvitation,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(lang.t('dialog_no')), 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                  // BUTTON YEGO / SEND
                  if (!isWaitingForGameAcceptance)
                    ElevatedButton.icon(
                      onPressed: onSendInvitation,
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(lang.t('dame_send_invitation_button')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } 
    // -------------------------------------------------------------------------
    // 2. ACTIVE GAME MODE (Iyo umukino uri kuba)
    // -------------------------------------------------------------------------
    else if (currentGameData != null && 
            (currentGameData!['status'] == 'active' || currentGameData!['status'] == 'finished')) {
      gameWidget = DameGameWidget(
        key: ValueKey('active_game_${currentGameData!['id'] ?? 'live'}'),
        chatRoomID: chatRoomID,
        gameData: currentGameData!,
        opponentDisplayName: receiverEmail,
        onGameStopped: onStopGame,
      );
    }

    // ANIMATION: Slide down effect
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)
          ),
          child: child,
        );
      },
      child: gameWidget ?? const SizedBox.shrink(key: ValueKey('no_game_active')),
    );
  }
}