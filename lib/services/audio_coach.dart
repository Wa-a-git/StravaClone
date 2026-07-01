// lib/services/audio_coach.dart
// Coach vocal (text-to-speech français, hors-ligne) pour les mini-jeux.
import 'package:flutter_tts/flutter_tts.dart';

class AudioCoach {
  final FlutterTts _tts = FlutterTts();
  DateTime _lastSpoke = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ready = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Parle [text]. [cooldown] évite de répéter trop souvent le même type de cue.
  Future<void> say(
    String text, {
    Duration cooldown = Duration.zero,
    bool interrupt = false,
  }) async {
    if (!_ready) return;
    final now = DateTime.now();
    if (cooldown > Duration.zero && now.difference(_lastSpoke) < cooldown) {
      return;
    }
    _lastSpoke = now;
    try {
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
