// lib/search_screen.dart

import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  bool _isLoading = false;
  String _searchQuery = "";
  bool _searchPerformed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final newQuery = _searchController.text.trim(); // NEW: Kuraho toLowerCase hano
      if (newQuery != _searchQuery) {
        setState(() {
          _searchQuery = newQuery;
          _searchPerformed = true;
        });
        _performSearch();
      }
    });
  }

  // <<<--- NYAMURURU: SMART SEARCH LOGIC (PRO) --->>>
  Future<void> _performSearch() async {
    if (_searchQuery.isEmpty) {
      setState(() { _searchResults = []; _isLoading = false; _searchPerformed = false; });
      return;
    }

    setState(() { _isLoading = true; });
    
    try {
      // 1. Logic y'ubuhanga: Hagarika inyuguti ya mbere ukiyigira Nkuru (Capitalized)
      // Ibi ni ngombwa kuko Firestore isaba ko query ihuza neza n'inyuguti (Case-sensitive)
      String smartQuery = _searchQuery;
      if (_searchQuery.isNotEmpty) {
        smartQuery = _searchQuery[0].toUpperCase() + _searchQuery.substring(1);
      }

      // 2. Gushaka ukoresheje 'displayName' (Inkingi ihari kare muri database)
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: smartQuery)
          .where('displayName', isLessThanOrEqualTo: '$smartQuery\uf8ff')
          .limit(20)
          .get();

      if (mounted) {
        setState(() {
          _searchResults = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _searchResults = []; });
      debugPrint("Search Error: $e");
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      appBar: AppBar(
        title: Text(lang.t('search_users_title')), 
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CupertinoSearchTextField(
              controller: _searchController,
              backgroundColor: Colors.white10,
              style: const TextStyle(color: Colors.white),
              placeholder: lang.t('search_users_hint'),
              placeholderStyle: const TextStyle(color: Colors.white30),
            ),
          ),
          Expanded(child: _buildSearchResults(lang)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(LanguageProvider lang) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(color: Colors.white));
    }

    if (!_searchPerformed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 80, color: Colors.white.withAlpha(25)),
            const SizedBox(height: 16),
            Text(lang.t('search_users_prompt'), style: const TextStyle(color: Colors.white30)),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          "${lang.t('search_users_no_results')} '$_searchQuery'", 
          style: const TextStyle(color: Colors.white30)
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final userDoc = _searchResults[index];
        final userData = userDoc.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? "User";
        final photoUrl = userData['photoUrl'];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(13), 
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.white10,
              backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
              child: photoUrl == null ? const Icon(Icons.person, color: Colors.white24) : null,
            ),
            title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(userData['about'] ?? "Jembe Talk User", style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1),
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.push(context, MaterialPageRoute(builder: (context) => UserProfileScreen(userId: userDoc.id)));
            },
          ),
        );
      },
    );
  }
}