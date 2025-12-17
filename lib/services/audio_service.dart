// lib/services/audio_service.dart (YOROHEJE KANDI IKOSOYE)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:shared_preferences/shared_preferences.dart';

// <<<< AudioRecorderService yose yavuyemo kuko itagikenewe >>>>

// ----------------- PLAYER SERVICE (IRACYAKENEWE MU GUCURANGA) -----------------
class AudioPlayerService extends ChangeNotifier {
  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  SharedPreferences? _prefs;

  String? _currentMessageId;
  just_audio.PlayerState? _state;
  Duration _pos = Duration.zero;
  Duration? _dur;
  double _speed = 1.0;

  AudioPlayerService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();

    _player.playerStateStream.listen((s) {
      _state = s;
      notifyListeners();
    });

    _player.positionStream.listen((p) {
      _pos = p;
      if (_currentMessageId != null) {
        _prefs?.setInt('pos_${_currentMessageId!}', p.inMilliseconds);
      }
      notifyListeners();
    });

    _player.durationStream.listen((d) {
      _dur = d;
      notifyListeners();
    });
  }

  String? get currentMessageId => _currentMessageId;
  bool get isPlaying => _state?.playing ?? false;
  Duration get position => _pos;
  Duration get duration => _dur ?? Duration.zero;
  double get playbackSpeed => _speed;

  Future<void> loadAudio(String id, String path, bool isLocal) async {
    if (_currentMessageId == id) {
      await playPause();
      return;
    }
    await stop();
    _currentMessageId = id;

    try {
      if (isLocal) {
        await _player.setFilePath(path);
      } else {
        await _player.setUrl(path);
      }

      final remembered = Duration(
        milliseconds: _prefs?.getInt('pos_$id') ?? 0,
      );
      if (remembered > Duration.zero &&
          remembered < (_player.duration ?? Duration.zero)) {
        await _player.seek(remembered);
      }

      await _player.setSpeed(_speed);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint("Audio load error: $e");
    }
  }

  Future<void> playPause() async {
    if (isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  Future<void> toggleSpeed() async {
    if (_speed == 1.0) {
      _speed = 1.5;
    } else if (_speed == 1.5) {
      _speed = 2.0;
    } else {
      _speed = 1.0;
    }
    await _player.setSpeed(_speed);
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentMessageId = null;
    _pos = Duration.zero;
    _dur = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}