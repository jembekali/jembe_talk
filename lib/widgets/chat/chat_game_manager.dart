// lib/widgets/chat/chat_game_manager.dart (VERSION 1.1 - SMOOTH TRANSITION & STABLE GAME OVERLAY)

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
    // 1. INVITATION MODE: Iyo uri gutegura ubutumire (Preview Board)
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
        padding: const EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header y'ubutumire
            SizedBox(
              height: 50,
              child: isWaitingForGameAcceptance
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(lang.t('dame_invitation_sent'), 
                          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
                      ],
                    )
                  : Center(
                      child: Text(
                        lang.t('dame_send_invitation_header'), 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                      )
                    ),
            ),

            // Ikibaho cy'ubutumire
            DameGameWidget(
              key: const ValueKey('invitation_preview'),
              chatRoomID: chatRoomID,
              gameData: {'board': previewBoard, 'status': 'preview'},
              isInvitation: true,
              isWaiting: isWaitingForGameAcceptance,
            ),

            // Buto zo kwemeza cyangwa guhagarika ubutumire
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: onCancelInvitation,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(lang.t('dialog_no')), 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                if (!isWaitingForGameAcceptance)
                  ElevatedButton.icon(
                    onPressed: onSendInvitation,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(lang.t('dame_send_invitation_button')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    } 
    // -------------------------------------------------------------------------
    // 2. ACTIVE GAME MODE: Iyo umukino uri kuba (Live Board)
    // -------------------------------------------------------------------------
    else if (currentGameData != null && 
            (currentGameData!['status'] == 'active' || currentGameData!['status'] == 'finished')) {
      gameWidget = DameGameWidget(
        key: ValueKey('active_game_${chatRoomID}'),
        chatRoomID: chatRoomID,
        gameData: currentGameData!,
        opponentDisplayName: receiverEmail,
        onGameStopped: onStopGame,
      );
    }

    // ✅ ANIMATION: Slide down effect (Kuva hejuru uza hasi)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.2), // Tura hanze gato ya screen
            end: Offset.zero
          ).animate(animation),
          child: child,
        );
      },
      child: gameWidget ?? const SizedBox.shrink(key: ValueKey('no_game_active')),
    );
  }
}