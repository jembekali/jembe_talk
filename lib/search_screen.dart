// lib/search_screen.dart (VERSION YAKOSOWE AMOSA YOSE)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:jembe_talk/tangaza_star/user_profile_screen.dart';
// <--- TWONGEREYEMWO IZI DOSIYE --->
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final newQuery = _searchController.text.trim().toLowerCase(); 
      if (newQuery != _searchQuery) {
        setState(() {
          _searchQuery = newQuery;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (newQuery == _searchController.text.trim().toLowerCase()) {
            _performSearch();
          }
        });
      }
    });
  }

  Future<void> _performSearch() async {
    setState(() { _searchPerformed = true; });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() { _isLoading = true; });
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('displayName_lowercase', isGreaterThanOrEqualTo: _searchQuery)
          .where('displayName_lowercase', isLessThanOrEqualTo: '$_searchQuery\uf8ff')
          .limit(20)
          .get();

      setState(() {
        _searchResults = snapshot.docs;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
      print("🚨🚨🚨 HABAYE IKOSA: $e");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // <--- Duhamagara LanguageProvider --->
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('search_users_title')),
        backgroundColor: Colors.blueGrey[900],
      ),
      backgroundColor: Colors.blueGrey[800],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: lang.t('search_users_hint'),
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.blueGrey[700],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _buildSearchResults(lang)), // <--- Twongeyemwo 'lang'
        ],
      ),
    );
  }

  Widget _buildSearchResults(LanguageProvider lang) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_searchPerformed) {
      return Center(
        child: Text(
          lang.t('search_users_prompt'),
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          "${lang.t('search_users_no_results')} '$_searchQuery'",
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final userDoc = _searchResults[index];
        final userData = userDoc.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? lang.t('search_users_unknown_name');
        final photoUrl = userData['photoUrl'];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Text(displayName, style: const TextStyle(color: Colors.white)),
          onTap: () {
            FocusScope.of(context).unfocus();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => UserProfileScreen(userId: userDoc.id)),
            );
          },
        );
      },
    );
  }
}