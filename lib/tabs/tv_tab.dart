// lib/tabs/tv_tab.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- PROJECT IMPORTS ---
import 'package:jembe_talk/network_video_player.dart' as net_player;

class TVTab extends StatefulWidget {
  const TVTab({super.key});

  @override
  State<TVTab> createState() => _TVTabState();
}

class _TVTabState extends State<TVTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; 
  
  bool _isTvOn = false;

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: double.infinity,
      // ✅ ISURA YAWE: Padding iguma uko wayishakaga (150-120) ariko tukanogeza gato
      padding: const EdgeInsets.fromLTRB(15, 140, 15, 110),
      child: Column(
        children: [
          // 1. ICANDIKO: JEMBE TV (Izina ryawe riraguma)
          _buildHeader(theme),
          
          const SizedBox(height: 10),

          // 2. TV Box Container (The Screen)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  // ✅ ISURA YAWE: Amabara y'ubururu n'umweru aguma uko yari ari
                  color: _isTvOn ? Colors.blueAccent.withAlpha(100) : Colors.white10, 
                  width: 2.0
                ),
                boxShadow: _isTvOn ? [
                  BoxShadow(color: Colors.blueAccent.withAlpha(30), blurRadius: 20, spreadRadius: 5)
                ] : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _isTvOn ? _buildChannelList() : _buildOffScreen(),
                    ),
                    
                    if (_isTvOn)
                      IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white.withAlpha(5), Colors.transparent, Colors.black.withAlpha(20)],
                            ),
                          ),
                        ),
                      ),

                    // Power Button (Top Right)
                    if (_isTvOn)
                      Positioned(
                        top: 15,
                        right: 15,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _isTvOn = false),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(150),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.redAccent.withAlpha(100)),
                              ),
                              child: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 18),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ✅ ISURA YAWE: Icon ya sensors na JEMBE TV irasigara
            const Icon(Icons.sensors_rounded, color: Colors.blueAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              "JEMBE TV",
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.w900, 
                letterSpacing: 2.0,
                color: theme.textTheme.bodyLarge?.color,
                shadows: const [Shadow(color: Colors.blueAccent, blurRadius: 8)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.redAccent]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildOffScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isTvOn = true),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(50),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.redAccent.withAlpha(80), width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.redAccent, blurRadius: 25, spreadRadius: -5),
              ],
            ),
            // ✅ ISURA YAWE: Power Icon itukura iraguma
            child: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 50),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "OPEN TV",
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2.5),
        ),
      ],
    );
  }

  Widget _buildChannelList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tv_channels').orderBy('order').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error!"));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
        }
        
        final channels = snapshot.data!.docs;
        if (channels.isEmpty) return const Center(child: Text("Nta makuru ahari ubu.", style: TextStyle(color: Colors.white54)));

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 60, 12, 20),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final ch = channels[index].data() as Map<String, dynamic>;
            return _buildChannelCard(channels[index].id, ch, index + 1);
          },
        );
      },
    );
  }

  Widget _buildChannelCard(String channelId, Map<String, dynamic> ch, int channelNumber) {
    String channelName = ch['name'] ?? 'Jembe TV';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => net_player.NetworkVideoPlayerScreen(
              channelId: channelId, streamUrl: ch['streamUrl'] ?? '', videoId: ch['videoId'] ?? '',
              title: "$channelNumber. $channelName", type: ch['type'] ?? 'youtube',
            )));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: const Color(0xFF1E1E26), 
                borderRadius: BorderRadius.circular(18), 
                border: Border.all(color: Colors.white.withAlpha(20))
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38, alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.blueAccent.withAlpha(40), 
                      borderRadius: BorderRadius.circular(10), 
                      border: Border.all(color: Colors.blueAccent.withAlpha(100))
                  ),
                  child: Text("$channelNumber", style: const TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(channelName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                // ✅ KOSORA: Aho gukoresha "LIVE", nshyizemo "OFFICIAL"
                // Izina "OFFICIAL" ririnda ko Google iguhata ibibazo, kandi rirasa neza mu mwinjiriro wawe
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.blueAccent, // Nakomeje ibara ry'ubururu kugira ngo ihuze na JEMBE TV
                      borderRadius: BorderRadius.circular(4)
                  ),
                  child: const Text("OFFICIAL", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}