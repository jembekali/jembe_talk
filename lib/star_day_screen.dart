// ====================================================================
// === IYI CODE YA StarDayScreen  yerekana izina ryumusi tugezeko  ===
// === igihe umuntu watsinze muri stars of the day iyi code yerekana WINNER muri cakibanza cumusi. ===
// ====================================================================

// lib/star_day_screen.dart (Code ya nyuma yuzuye,)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/services/database_helper.dart'; // RABA KO IYI NZIRA ARI YO
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _getTime());
    _fetchAndDisplayWins(); 
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
      print("Amakuru ashaje. Turondera kuri Firebase...");
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
        print("Ikosa ryo kubona intsinzi za Star: $e");
      }
    } else {
      print("Amakuru akiri mashasha. Dukoresha ayo muri telefone.");
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
      setState(() {
        _timeString = formattedDateTime;
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('HH:mm:ss').format(dateTime);
  }

  void _returnToMainScreenWithPostId(String postId) {
    if(mounted) {
      Navigator.of(context).pop(postId);
    }
  }
  
  String _getCurrentDayInKirundi() {
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

  String _getCurrentDateInKirundi() {
    final now = DateTime.now();
    const monthsInKirundi = {
      'January': 'Nzero', 'February': 'Ruhuhuma', 'March': 'Ntwarante',
      'April': 'Ndamukiza', 'May': 'Rusama', 'June': 'Ruheshi',
      'July': 'Mukakaro', 'August': 'Myandagaro', 'September': 'Nyakanga',
      'October': 'Gitugutu', 'November': 'Munyonyo', 'December': 'Kigarama',
    };
    String monthName = DateFormat.MMMM().format(now);
    return "${now.day} ${monthsInKirundi[monthName] ?? ''} ${now.year}";
  }

  Widget _buildCalendarView(BuildContext context) {
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
              _getCurrentDayInKirundi(),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color?.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getCurrentDateInKirundi(),
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
    return Scaffold(
      appBar: AppBar(title: const Text("   UMUSI MWIZA"), backgroundColor: const Color.fromARGB(255, 54, 136, 202)),
      body: ListView(
        children: [
          _buildCalendarView(context),
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
                            _returnToMainScreenWithPostId(postId);
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
                                      win['title'] ?? 'Wabaye Star!',
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
                              Text(win['body'] ?? 'Turagukeje ku bw\'iyi ntsinzi.', style: const TextStyle(fontSize: 16)),
                              if (postId != null) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      "fyonda hano urabe post yawe nziza cane!",
                                      style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                    ),
                                    const Spacer(),
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