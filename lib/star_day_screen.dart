// lib/star_day_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/database_helper.dart'; 
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

// NYAMURURU: Import za ngombwa kugira ngo tujye kuri Screen ya Video
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart';
import 'package:jembe_talk/widgets/custom_page_route.dart';

class StarDayScreen extends StatefulWidget {
  final String userId;
  const StarDayScreen({super.key, required this.userId});

  @override
  State<StarDayScreen> createState() => _StarDayScreenState();
}

class _StarDayScreenState extends State<StarDayScreen> {
  late Timer _timer;
  late String _timeString;
  
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _starWinsToDisplay = [];
  bool _isLoading = true;
  bool _isFirstLoad = true; 

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _getTime());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final langProvider = Provider.of<LanguageProvider>(context);
    _initializeLocale(langProvider.currentLanguage);

    if (_isFirstLoad) {
      _fetchAndDisplayWins();
      _isFirstLoad = false;
    }
  }

  Future<void> _initializeLocale(String langCode) async {
    String locale;
    switch (langCode) {
      case 'fr': locale = 'fr_FR'; break;
      case 'en': locale = 'en_US'; break;
      case 'sw': locale = 'sw_TZ'; break;
      case 'ki':
      default:
        locale = 'fr_FR'; 
        break;
    }
    if (Intl.getCurrentLocale() != locale) {
       await initializeDateFormatting(locale, null);
    }
  }

  Future<void> _fetchAndDisplayWins() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final lastFetchMillis = prefs.getInt('lastStarFetchTimestamp_${widget.userId}') ?? 0;
    final lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMillis);

    final now = DateTime.now();
    final todayAnnouncementTime = DateTime(now.year, now.month, now.day, 18);
    DateTime lastAnnouncementTime;
    if (now.isBefore(todayAnnouncementTime)) {
      lastAnnouncementTime = todayAnnouncementTime.subtract(const Duration(days: 1));
    } else {
      lastAnnouncementTime = todayAnnouncementTime;
    }

    if (lastFetchTime.isBefore(lastAnnouncementTime)) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: widget.userId)
            .where('type', isEqualTo: 'star_winner')
            .get();

        final notificationsToSave = querySnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'title': data['title'],
            'body': data['body'],
            'timestamp': (data['timestamp'] as Timestamp).millisecondsSinceEpoch,
            'relatedPostId': data['relatedPostId'],
          };
        }).toList();

        await _dbHelper.saveStarNotifications(notificationsToSave);
        await prefs.setInt('lastStarFetchTimestamp_${widget.userId}', DateTime.now().millisecondsSinceEpoch);
        
      } catch (e) {
        debugPrint("Ikosa ryo kubona intsinzi za Star: $e");
      }
    }

    final localWins = await _dbHelper.getStarNotifications();
    final List<Map<String, dynamic>> validWins = [];
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));

    for (var win in localWins) {
      final winTime = DateTime.fromMillisecondsSinceEpoch(win['timestamp']);
      if (winTime.isAfter(twentyFourHoursAgo)) {
        validWins.add(win);
      }
    }

    if (mounted) {
      setState(() {
        _starWinsToDisplay = validWins;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _getTime() {
    final DateTime now = DateTime.now();
    final String formattedDateTime = _formatDateTime(now);
    if (mounted) {
      setState(() { _timeString = formattedDateTime; });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('HH:mm:ss').format(dateTime);
  }

  // =========================================================================
  // FIX: NAVIGATION IFUNGUYE YA POST YAWE
  // =========================================================================
  void _goToTargetPost(String postId) {
    if(mounted) {
      // Aho gu-pop, tugiye kujya kuri TangazaStarScreen Directly
      Navigator.push(
        context, 
        CustomPageRoute(
          child: TangazaStarScreen(targetPostId: postId)
        )
      );
    }
  }
  
  String _getCurrentDay(String langCode) {
    if (langCode == 'ki') {
      final now = DateTime.now();
      switch (now.weekday) {
        case DateTime.monday: return "Kuwambere";
        case DateTime.tuesday: return "Kuwakabiri";
        case DateTime.wednesday: return "Kuwagatatu";
        case DateTime.thursday: return "Kuwakane";
        case DateTime.friday: return "Kuwagatanu";
        case DateTime.saturday: return "Kuwagatandatu";
        case DateTime.sunday: return "Kuwamungu";
        default: return "";
      }
    }
    final locale = langCode == 'en' ? 'en_US' : langCode == 'fr' ? 'fr_FR' : 'sw_TZ';
    String dayName = DateFormat.EEEE(locale).format(DateTime.now());
    return dayName[0].toUpperCase() + dayName.substring(1);
  }

  String _getCurrentDate(String langCode) {
    final now = DateTime.now();
    if (langCode == 'ki') {
        const monthsInKirundi = {
        'January': 'Nzero', 'February': 'Ruhuhuma', 'March': 'Ntwarante',
        'April': 'Ndamukiza', 'May': 'Rusama', 'June': 'Ruheshi',
        'July': 'Mukakaro', 'August': 'Myandagaro', 'September': 'Nyakanga',
        'October': 'Gitugutu', 'November': 'Munyonyo', 'December': 'Kigarama',
      };
      String monthName = DateFormat.MMMM('en_US').format(now);
      return "${now.day} ${monthsInKirundi[monthName] ?? ''} ${now.year}";
    }
    final locale = langCode == 'en' ? 'en_US' : langCode == 'fr' ? 'fr_FR' : 'sw_TZ';
    return DateFormat.yMMMMd(locale).format(now);
  }

  Widget _buildCalendarView(BuildContext context, LanguageProvider lang) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_outlined, size: 100, color: Colors.deepPurple.shade200),
            const SizedBox(height: 30),
            Text(
              _getCurrentDay(lang.currentLanguage),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color?.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getCurrentDate(lang.currentLanguage),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                _timeString,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple.shade300,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.t('star_screen_title')), 
        backgroundColor: const Color.fromARGB(255, 54, 136, 202)
      ),
      body: ListView(
        children: [
          _buildCalendarView(context, lang),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
          else if (_starWinsToDisplay.isNotEmpty)
            Column(
              children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider()),
                const SizedBox(height: 10),
                ..._starWinsToDisplay.map((win) {
                  final String? postId = win['relatedPostId'];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (postId != null) {
                            // HANO: Ihamagara rishya rya Direct Navigation
                            _goToTargetPost(postId);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 30),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      win['title'] ?? lang.t('star_win_default_title'),
                                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                                    ),
                                  ),
                                  Text(
                                    DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(win['timestamp'])),
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(win['body'] ?? lang.t('star_win_default_body'), style: const TextStyle(fontSize: 16)),
                              if (postId != null) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        lang.t('star_win_tap_to_see'),
                                        style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue.shade700)
                                  ],
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            )
        ],
      ),
    );
  }
}