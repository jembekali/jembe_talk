// lib/services/audio_service.dart (VERSION 2.6 - MARK AS PLAYED INTEGRATION)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jembe_talk/services/sync_service.dart'; // ✅ Twongereyemo iyi service

class AudioPlayerService extends ChangeNotifier {
  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  final just_audio.AudioPlayer _notificationPlayer = just_audio.AudioPlayer();

  SharedPreferences? _prefs;

  String? _currentMessageId;
  just_audio.PlayerState? _state;
  Duration _pos = Duration.zero;
  Duration? _dur;
  double _speed = 1.0;
  
  bool _isManualSeeking = false;
  Timer? _prefsTimer;

  AudioPlayerService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();

    _player.playerStateStream.listen((s) {
      _state = s;
      if (s.processingState == just_audio.ProcessingState.completed) {
        _handlePlaybackComplete();
      }
      notifyListeners();
    });

    _player.positionStream.listen((p) {
      if (!_isManualSeeking) {
        _pos = p;
        _debounceSavePosition(p.inMilliseconds);
        notifyListeners();
      }
    });

    _player.durationStream.listen((d) {
      if (d != null) {
        _dur = d;
        notifyListeners();
      }
    });
  }

  // --- GETTERS ---
  String? get currentMessageId => _currentMessageId;
  bool get isPlaying => _state?.playing ?? false;
  Duration get position => _pos;
  Duration get duration => _dur ?? Duration.zero;
  Duration? get totalDuration => _dur; 
  double get playbackSpeed => _speed;
  just_audio.AudioPlayer get audioPlayer => _player;

  // --- LOGIC ---

  Future<void> playNotificationSound(String assetPath) async {
    try {
      await _notificationPlayer.setAsset(assetPath);
      await _notificationPlayer.play();
    } catch (e) {
      debugPrint("Notification Sound Error: $e");
    }
  }

  void _handlePlaybackComplete() async {
    await _player.seek(Duration.zero);
    await _player.pause();
    _pos = Duration.zero;
    if (_currentMessageId != null) {
      _savePositionToPrefs(0);
    }
    notifyListeners();
  }

  void _debounceSavePosition(int ms) {
    _prefsTimer?.cancel();
    _prefsTimer = Timer(const Duration(seconds: 2), () {
      if (_currentMessageId != null) {
        _prefs?.setInt('pos_${_currentMessageId!}', ms);
      }
    });
  }

  void _savePositionToPrefs(int ms) {
    if (_currentMessageId != null) {
      _prefs?.setInt('pos_${_currentMessageId!}', ms);
    }
  }

  // ✅ KOSORA HANO: loadAudio ubu ikenera na roomId kugira ngo imenye aho ihindura Firestore
  Future<void> loadAudio(String id, String path, bool isLocal, String roomId) async {
    if (_currentMessageId == id) {
      await playPause();
      return;
    }
    
    await stop();
    _currentMessageId = id;

    try {
      // ✅ TANGIRA HANO: Bwira SyncService ko iyi Voice Note yatangiye gukina
      syncService.markVoiceNoteAsPlayed(roomId, id);

      if (isLocal) {
        await _player.setFilePath(path);
      } else {
        await _player.setUrl(path);
      }

      final savedPos = _prefs?.getInt('pos_$id') ?? 0;
      final remembered = Duration(milliseconds: savedPos);

      if (remembered > Duration.zero && remembered < (_player.duration ?? Duration.zero)) {
        await _player.seek(remembered);
        _pos = remembered;
      } else {
        await _player.seek(Duration.zero);
        _pos = Duration.zero;
      }

      await _player.setSpeed(_speed);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint("Audio Player Error: $e");
    }
  }

  Future<void> playPause() async {
    if (isPlaying) {
      await _player.pause();
    } else {
      if (_player.position >= (_player.duration ?? Duration.zero)) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    try {
      _isManualSeeking = true; 
      _pos = pos;              
      notifyListeners();        
      await _player.seek(pos); 
      Future.delayed(const Duration(milliseconds: 200), () {
        _isManualSeeking = false; 
      });
    } catch (e) {
      _isManualSeeking = false;
      debugPrint("Seek Error: $e");
    }
  }

  Future<void> toggleSpeed() async {
    if (_speed == 1.0) _speed = 1.5;
    else if (_speed == 1.5) _speed = 2.0;
    else _speed = 1.0;
    await _player.setSpeed(_speed);
    notifyListeners();
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _currentMessageId = null;
      _pos = Duration.zero;
      _dur = Duration.zero;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _prefsTimer?.cancel();
    _player.dispose();
    _notificationPlayer.dispose(); 
    super.dispose();
  }
}