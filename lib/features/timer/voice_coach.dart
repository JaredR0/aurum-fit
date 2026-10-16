import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Asistente de voz y señales sonoras/hápticas del temporizador.
///
/// Privacidad: usa el motor de texto a voz del propio sistema operativo y
/// tonos generados en memoria. No graba audio ni usa el micrófono; nada sale
/// del teléfono.
///
/// Audio sobre la música: los tonos piden foco de audio "transitorio con
/// atenuación" (ducking), así que la música del usuario baja el volumen un
/// momento en lugar de pausarse.
class VoiceCoach {
  VoiceCoach();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  late final Uint8List _shortBeep = _tone(880, 120);
  late final Uint8List _longBeep = _tone(1320, 450);

  bool voiceEnabled = true;
  bool beepEnabled = true;
  bool vibrationEnabled = true;
  bool _ready = false;

  static const _numbers = {
    1: 'uno',
    2: 'dos',
    3: 'tres',
    4: 'cuatro',
    5: 'cinco',
  };

  Future<void> init() async {
    if (_ready) return;
    try {
      // Intenta español latinoamericano y cae a otras variantes.
      for (final lang in const ['es-US', 'es-MX', 'es-419', 'es-ES']) {
        final available = await _tts.isLanguageAvailable(lang);
        if (available == true) {
          await _tts.setLanguage(lang);
          break;
        }
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    } catch (_) {
      // Sin motor TTS disponible: el timer sigue funcionando con tonos.
    }

    try {
      await _beepPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
      await _beepPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
    _ready = true;
  }

  Future<void> say(String text) async {
    if (!voiceEnabled || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> countdown(int n) async {
    if (beepEnabled) await _play(_shortBeep);
    if (vibrationEnabled) HapticFeedback.selectionClick();
    final word = _numbers[n];
    if (word != null) await say(word);
  }

  Future<void> phaseChange({required bool work}) async {
    if (beepEnabled) await _play(_longBeep);
    if (vibrationEnabled) {
      await HapticFeedback.heavyImpact();
      if (work) await HapticFeedback.vibrate();
    }
  }

  Future<void> _play(Uint8List bytes) async {
    try {
      await _beepPlayer.stop();
      await _beepPlayer.play(BytesSource(bytes));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
      await _beepPlayer.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _beepPlayer.dispose();
  }

  /// Genera un WAV PCM 16-bit mono con una onda senoidal y envolvente suave.
  static Uint8List _tone(double freq, int ms) {
    const sampleRate = 44100;
    final samples = sampleRate * ms ~/ 1000;
    final data = ByteData(44 + samples * 2);

    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + samples * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // tamaño del bloque fmt
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    data.setUint16(32, 2, Endian.little); // block align
    data.setUint16(34, 16, Endian.little); // bits por muestra
    ascii(36, 'data');
    data.setUint32(40, samples * 2, Endian.little);

    const fade = 0.08;
    for (var i = 0; i < samples; i++) {
      final t = i / samples;
      final env = t < fade
          ? t / fade
          : (t > 1 - fade ? (1 - t) / fade : 1.0);
      final v = sin(2 * pi * freq * i / sampleRate) * env * 0.6;
      data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
