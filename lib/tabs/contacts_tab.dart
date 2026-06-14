// lib/tabs/contacts_tab.dart (VERSION 32.31 - RAM OPTIMIZED)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/chat_screen.dart';

class ContactsTab extends StatefulWidget {
  final ValueNotifier<List<ChatData>> contactsNotifier;
  final Future<void> Function() onRefresh;

  const ContactsTab(
      {super.key, required this.contactsNotifier, required this.onRefresh});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab>
    with AutomaticKeepAliveClientMixin {
  bool _isSearchingLocal = false;
  final TextEditingController _localSearchController = TextEditingController();
  String _localQuery = "";

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localSearchController.addListener(() {
      final q = _localSearchController.text.toLowerCase().trim();
      if (_localQuery != q) {
        if (mounted) setState(() => _localQuery = q);
      }
    });
  }

  Future<void> _handleAddNewContact() async {
    HapticFeedback.mediumImpact();
    if (await FlutterContacts.requestPermission()) {
      try {
        await FlutterContacts.openExternalInsert();
        await widget.onRefresh();
      } catch (e) {
        debugPrint("Error adding contact: $e");
      }
    }
  }

  void _closeSearch() {
    if (mounted) {
      setState(() {
        _isSearchingLocal = false;
        _localSearchController.clear();
        _localQuery = "";
      });
    }
  }

  @override
  void dispose() {
    _localSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ValueListenableBuilder<List<ChatData>>(
      valueListenable: widget.contactsNotifier,
      builder: (context, contacts, child) {
        final filtered = contacts.where((e) {
          if (_localQuery.isEmpty) return true;
          return e.displayName.toLowerCase().contains(_localQuery);
        }).toList();

        filtered.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

        return Padding(
          padding: const EdgeInsets.only(top: 155),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isSearchingLocal
                      ? _buildSearchField(theme)
                      : _buildDefaultHeader(theme, contacts.length),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  color: theme.colorScheme.secondary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 5, 10, 120),
                    physics: const BouncingScrollPhysics(),
                    // KOSORA: Kurinda lag binyuze muri optimization ya ListView
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: true,
                    itemCount: filtered.isEmpty ? 1 : filtered.length,
                    itemBuilder: (context, i) {
                      if (filtered.isEmpty) {
                        return const Center(
                            child: Padding(
                                padding: EdgeInsets.only(top: 60),
                                child: Text("Nta muntu ubonetse...",
                                    style: TextStyle(color: Colors.grey))));
                      }

                      final contact = filtered[i];
                      return RepaintBoundary(
                        // KOSORA: Isolate repaint kuri buri item
                        child: _SimpleContactItem(
                          key: ValueKey(contact.userId),
                          chatData: contact,
                          onTap: () {
                            _closeSearch();
                            HapticFeedback.lightImpact();
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) => ChatScreenWrapper(
                                        receiverEmail: contact.displayName,
                                        receiverID: contact.userId)));
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDefaultHeader(ThemeData theme, int count) {
    return Row(
      key: const ValueKey("default_hdr"),
      children: [
        Text("Contacts",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withAlpha(30),
              borderRadius: BorderRadius.circular(12)),
          child: Text("$count",
              style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _handleAddNewContact,
          icon: Icon(Icons.person_add_alt_1_rounded,
              size: 18, color: theme.colorScheme.secondary),
          label: Text("Add",
              style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(
              backgroundColor: theme.colorScheme.secondary.withAlpha(20),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(width: 5),
        IconButton(
            onPressed: () => setState(() => _isSearchingLocal = true),
            icon: Icon(Icons.search,
                color: theme.colorScheme.secondary, size: 24)),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      key: const ValueKey("search_fld"),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha(150),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.colorScheme.secondary.withAlpha(60))),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _localSearchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: "Shaka...",
                      border: InputBorder.none,
                      isDense: true),
                  style: const TextStyle(fontSize: 16))),
          IconButton(
              onPressed: _closeSearch, icon: const Icon(Icons.close, size: 20)),
        ],
      ),
    );
  }
}

class _SimpleContactItem extends StatelessWidget {
  final ChatData chatData;
  final VoidCallback onTap;
  const _SimpleContactItem(
      {super.key, required this.chatData, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget leadingWidget;

    // KOSORA: Gucunga RAM kuri buri foto (cacheWidth/height)
    if (chatData.localPhotoPath != null &&
        File(chatData.localPhotoPath!).existsSync()) {
      leadingWidget = CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.surface,
          backgroundImage:
              ResizeImage(FileImage(File(chatData.localPhotoPath!)),
                  width: 120, // Small memory footprint
                  height: 120));
    } else if (chatData.photoUrl != null && chatData.photoUrl!.isNotEmpty) {
      leadingWidget = CachedNetworkImage(
          imageUrl: chatData.photoUrl!,
          memCacheWidth: 120, // Kurinda RAM ku mafoto ya server
          memCacheHeight: 120,
          imageBuilder: (context, imageProvider) =>
              CircleAvatar(radius: 26, backgroundImage: imageProvider),
          placeholder: (context, url) => CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.surface,
              child: const Icon(Icons.person, color: Colors.grey)));
    } else {
      leadingWidget = CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.secondary.withAlpha(30),
          child: Icon(Icons.person, color: theme.colorScheme.secondary));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(180),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: theme.colorScheme.onSurface.withAlpha(15))),
            child: Row(
              children: [
                leadingWidget,
                const SizedBox(width: 15),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(chatData.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(chatData.phoneNumber ?? '',
                          style: TextStyle(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withAlpha(150),
                              fontSize: 12))
                    ])),
                Icon(Icons.chevron_right_rounded,
                    color: theme.colorScheme.secondary.withAlpha(100),
                    size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
