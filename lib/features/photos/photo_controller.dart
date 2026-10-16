import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/local_db.dart';

@immutable
class PhotoEntry {
  const PhotoEntry({
    required this.id,
    required this.date,
    required this.pose,
    this.weightKg,
  });

  final String id;
  final DateTime date;

  /// 'frente', 'perfil' o 'espalda'.
  final String pose;
  final double? weightKg;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'pose': pose,
        'weightKg': weightKg,
      };

  static PhotoEntry? tryParse(Map<String, dynamic> j) {
    final date = DateTime.tryParse('${j['date']}');
    final id = j['id'];
    if (date == null || id is! String) return null;
    return PhotoEntry(
      id: id,
      date: date,
      pose: (j['pose'] as String?) ?? 'frente',
      weightKg: (j['weightKg'] as num?)?.toDouble(),
    );
  }
}

/// Diario de fotos de progreso.
///
/// Las imágenes se guardan DENTRO de la base cifrada (AES-256), no en la
/// galería: otras apps no pueden verlas, no van a copias de seguridad en la
/// nube y la app bloquea capturas de pantalla (FLAG_SECURE). La copia temporal
/// que crea el selector de imágenes se borra en cuanto se cifra.
class PhotoController extends StateNotifier<List<PhotoEntry>> {
  PhotoController() : super(_load());

  final ImagePicker _picker = ImagePicker();

  static List<PhotoEntry> _load() => LocalDb.readAllJson(LocalDb.photoMeta)
      .map(PhotoEntry.tryParse)
      .whereType<PhotoEntry>()
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<bool> add({
    required ImageSource source,
    required String pose,
    double? weightKg,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1440,
      imageQuality: 82,
      requestFullMetadata: false, // sin EXIF de ubicación
    );
    if (file == null) return false;

    final bytes = await file.readAsBytes();
    final now = DateTime.now();
    final entry = PhotoEntry(
      id: now.microsecondsSinceEpoch.toString(),
      date: now,
      pose: pose,
      weightKg: weightKg,
    );
    await LocalDb.photoBox.put(entry.id, bytes);
    await LocalDb.writeJson(LocalDb.photoMeta, entry.id, entry.toJson());

    try {
      await File(file.path).delete();
    } catch (_) {}

    state = [entry, ...state];
    return true;
  }

  Future<Uint8List?> bytesOf(String id) async {
    final raw = await LocalDb.photoBox.get(id);
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  Future<void> remove(String id) async {
    await LocalDb.photoBox.delete(id);
    await LocalDb.box(LocalDb.photoMeta).delete(id);
    state = state.where((p) => p.id != id).toList();
  }

  void reset() => state = const [];
}

final photoProvider = StateNotifierProvider<PhotoController, List<PhotoEntry>>(
  (ref) => PhotoController(),
);
