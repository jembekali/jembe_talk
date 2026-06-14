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
    // Debounce: Tega 600ms kugira ngo tudasoma Firestore buri nyuguti
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final newQuery = _searchController.text.trim();
      if (newQuery != _searchQuery) {
        setState(() {
          _searchQuery = newQuery;
          _searchPerformed = true;
        });
        _performSearch();
      }
    });
  }

  Future<void> _performSearch() async {
    if (_searchQuery.isEmpty) {
      setState(() { _searchResults = []; _isLoading = false; _searchPerformed = false; });
      return;
    }

    setState(() { _isLoading = true; });
    
    try {
      // SMART QUERY: Gushaka ukoresheje Inyuguti Inkuru (Firestore Case-Sensitivity Fix)
      String smartQuery = _searchQuery;
      if (_searchQuery.isNotEmpty) {
        smartQuery = _searchQuery[0].toUpperCase() + _searchQuery.substring(1);
      }

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
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: Colors.black, // Match Tangaza Star theme
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          lang.t('search_users_title'), 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
      ),
      body: Column(
        children: [
          // Search Input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CupertinoSearchTextField(
              controller: _searchController,
              backgroundColor: Colors.white.withOpacity(0.1),
              style: const TextStyle(color: Colors.white),
              placeholder: lang.t('search_users_hint'),
              itemColor: Colors.greenAccent,
              placeholderStyle: const TextStyle(color: Colors.white30),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          
          // Results
          Expanded(child: _buildSearchResults(lang)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(LanguageProvider lang) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(color: Colors.greenAccent));
    }

    if (!_searchPerformed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 80, color: Colors.white.withOpacity(0.05)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final userDoc = _searchResults[index];
        final userData = userDoc.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? "User";
        final photoUrl = userData['photoUrl'];
        final isStar = userData['isStarUser'] ?? false; // Pro Feature: Star Badge

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05), 
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey[900],
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null,
              child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white24) : null,
            ),
            title: Row(
              children: [
                Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                if (isStar) const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 18),
                ),
              ],
            ),
            subtitle: Text(
              userData['about'] ?? "Jembe Talk User", 
              style: const TextStyle(color: Colors.white54, fontSize: 12), 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
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