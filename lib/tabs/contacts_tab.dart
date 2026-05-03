// lib/tabs/contacts_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:io';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/chat_screen.dart';

class ContactsTab extends StatefulWidget {
  final String searchQuery;
  final ValueNotifier<List<ChatData>> contactsNotifier;
  final Future<void> Function() onRefresh;

  const ContactsTab({
    super.key, 
    required this.searchQuery, 
    required this.contactsNotifier, 
    required this.onRefresh
  });

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; 

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    final theme = Theme.of(context);

    return ValueListenableBuilder<List<ChatData>>(
      valueListenable: widget.contactsNotifier,
      builder: (context, contacts, child) {
        final filtered = widget.searchQuery.isEmpty 
            ? contacts 
            : contacts.where((e) => e.displayName.toLowerCase().contains(widget.searchQuery.toLowerCase())).toList();

        // ✅ KOSORA HANO: Padding ya 160 imanura Refresh Area neza munsi ya Header
        return Padding(
          padding: const EdgeInsets.only(top: 160), 
          child: LiquidPullToRefresh(
            onRefresh: widget.onRefresh,
            color: theme.scaffoldBackgroundColor, // Ibara rya background y'amazi
            backgroundColor: theme.colorScheme.secondary, // ✅ Ibara ry'akaziga rigaragara neza
            height: 60, // Uburebure bwa kariya gace k'amazi
            animSpeedFactor: 2.5, // Bituma izinduka izamuka
            showChildOpacityTransition: false,
            child: ListView.builder(
              // Padding ya Top yagabanyijwe cyane kuko tumaze kuyishira kuri parent
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 120), 
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.isEmpty ? 1 : filtered.length,
              itemBuilder: (context, i) {
                if (filtered.isEmpty) {
                  return Container(
                    height: MediaQuery.of(context).size.height * 0.45,
                    alignment: Alignment.center,
                    child: const Text("Manura hasi ubone abagenzi...", style: TextStyle(color: Colors.grey)),
                  );
                }

                final contact = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withAlpha(190),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.onSurface.withAlpha(25)),
                    ),
                    child: _SimpleContactItem(chatData: contact),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SimpleContactItem extends StatelessWidget {
  final ChatData chatData;
  const _SimpleContactItem({required this.chatData});

  @override
  Widget build(BuildContext context) {
    // PRO: IMAGE CACHING
    ImageProvider? profilePic;
    if (chatData.localPhotoPath != null && File(chatData.localPhotoPath!).existsSync()) {
      profilePic = FileImage(File(chatData.localPhotoPath!));
    } else if (chatData.photoUrl != null && chatData.photoUrl!.isNotEmpty) {
      profilePic = CachedNetworkImageProvider(chatData.photoUrl!);
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {
        HapticFeedback.lightImpact(); // ✅ PRO TACTILE
        Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (c) => ChatScreenWrapper(
              receiverEmail: chatData.displayName, 
              receiverID: chatData.userId
            )
          )
        );
      },
      leading: CircleAvatar(
        radius: 28, 
        backgroundColor: Theme.of(context).colorScheme.secondary.withAlpha(40),
        backgroundImage: profilePic, 
        child: profilePic == null 
            ? Icon(Icons.person, color: Theme.of(context).colorScheme.secondary) 
            : null
      ),
      title: Text(
        chatData.displayName, 
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)
      ),
      subtitle: Text(
        chatData.phoneNumber ?? '',
        style: TextStyle(
          color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(150),
          fontSize: 13
        ),
      ),
    );
  }
}