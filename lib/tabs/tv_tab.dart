// lib/tabs/tv_tab.dart (VERSION 32.31 - GPU OPTIMIZED)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Menya neza ko izina rya file ririmo player ari iri
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
  Future<List<QueryDocumentSnapshot>>? _channelsFuture;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  void _loadChannels() {
    // Gufata amakuru muri Firestore rimwe gusa (Static Fetch) kugira ngo itongera guhamagara internet buri gihe
    _channelsFuture = FirebaseFirestore.instance
        .collection('tv_channels')
        .orderBy('order')
        .get()
        .then((snapshot) => snapshot.docs);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.fromLTRB(15, 140, 15, 110),
        child: Column(
          children: [
            // 1. Header (Isolate repaint)
            const RepaintBoundary(child: _TVHeader()),
            const SizedBox(height: 12),

            // 2. TV Screen Area
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isTvOn
                        ? Colors.blueAccent.withOpacity(0.4)
                        : Colors.white10,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child:
                              _isTvOn ? _buildChannelList() : _buildOffScreen(),
                        ),
                      ),
                      if (_isTvOn)
                        Positioned(
                          top: 15,
                          right: 15,
                          child: RepaintBoundary(
                            child: IconButton(
                              onPressed: () => setState(() => _isTvOn = false),
                              icon: const Icon(Icons.power_settings_new,
                                  color: Colors.redAccent, size: 22),
                              style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54),
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
      ),
    );
  }

  Widget _buildOffScreen() {
    return Column(
      key: const ValueKey("off_screen"),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isTvOn = true),
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.redAccent.withOpacity(0.3), width: 2),
            ),
            child: const Icon(Icons.power_settings_new,
                color: Colors.redAccent, size: 45),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "OPEN TV",
          style: TextStyle(
              color: Colors.white38,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0),
        ),
      ],
    );
  }

  Widget _buildChannelList() {
    return FutureBuilder<List<QueryDocumentSnapshot>>(
      key: const ValueKey("channel_list"),
      future: _channelsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Colors.blueAccent, strokeWidth: 2));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
              child: Text("Error loading channels",
                  style: TextStyle(color: Colors.white54)));
        }

        final channels = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 65, 12, 30),
          itemCount: channels.length,
          physics: const BouncingScrollPhysics(),
          // KOSORA: Kurinda lag binyuze muri optimization ya channel list
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            final chData = channels[index].data() as Map<String, dynamic>;
            final String channelId = channels[index].id;

            return RepaintBoundary(
              // KOSORA: Isolate buri card repaint
              child: _ChannelCard(
                channelId: channelId,
                data: chData,
                number: index + 1,
              ),
            );
          },
        );
      },
    );
  }
}

class _TVHeader extends StatelessWidget {
  const _TVHeader();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sensors_rounded,
                color: Colors.blueAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              "JEMBE TV",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: 50,
          height: 3,
          decoration: BoxDecoration(
              color: Colors.blueAccent, borderRadius: BorderRadius.circular(2)),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final String channelId;
  final Map<String, dynamic> data;
  final int number;

  const _ChannelCard(
      {required this.channelId, required this.data, required this.number});

  @override
  Widget build(BuildContext context) {
    final String name = data['name'] ?? 'Jembe TV';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => net_player.NetworkVideoPlayerScreen(
                  channelId: channelId,
                  streamUrl: data['streamUrl'] ?? '',
                  videoId: data['videoId'] ?? '',
                  title: "$number. $name",
                  type: data['type'] ?? 'tv',
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text("$number",
                      style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.play_circle_fill,
                    color: Colors.white24, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
