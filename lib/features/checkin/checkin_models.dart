import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';

/// Lo que el usuario reporta al cerrar una semana de entrenamiento.
@immutable
class WeeklyCheckin {
  const WeeklyCheckin({
    required this.id,
    required this.week,
    required this.date,
    required this.values,
    this.display = const {},
    this.bodyWeightKg,
    this.energy = 3,
    this.pain = false,
    this.painNote = '',
    this.sessionsDone = 0,
    this.sessionsPlanned = 0,
    this.stepDays = 0,
    this.note = '',
  });

  final String id;

  /// Semana del plan que se cierra. 0 = evaluación inicial.
  final int week;
  final DateTime date;

  /// id de prueba → valor normalizado (1RM en kg, segundos, km…).
  final Map<String, double> values;

  /// id de prueba → texto tal como lo escribió el usuario ("80 kg × 5").
  final Map<String, String> display;
  final double? bodyWeightKg;

  /// Energía y recuperación de 1 (agotado) a 5 (excelente).
  final int energy;
  final bool pain;
  final String painNote;
  final int sessionsDone;
  final int sessionsPlanned;

  /// Días de la semana en que se llegó a la meta de pasos.
  final int stepDays;
  final String note;

  bool get isBaseline => week == 0;

  /// La semana siguiente debería ser de descarga.
  bool get recommendsDeload => pain || energy <= 2;

  double? value(String id) =>
      id == 'body_kg' ? bodyWeightKg : values[id];

  Map<String, dynamic> toJson() => {
        'id': id,
        'week': week,
        'date': date.toIso8601String(),
        'values': values,
        'display': display,
        'bodyWeightKg': bodyWeightKg,
        'energy': energy,
        'pain': pain,
        'painNote': painNote,
        'sessionsDone': sessionsDone,
        'sessionsPlanned': sessionsPlanned,
        'stepDays': stepDays,
        'note': note,
      };

  static WeeklyCheckin? tryParse(Map<String, dynamic> j) {
    final date = DateTime.tryParse('${j['date']}');
    if (date == null) return null;
    final values = <String, double>{};
    final rawValues = j['values'];
    if (rawValues is Map) {
      for (final e in rawValues.entries) {
        final v = e.value;
        if (e.key is String && v is num && v.isFinite) {
          values[e.key as String] = v.toDouble();
        }
      }
    }
    final display = <String, String>{};
    final rawDisplay = j['display'];
    if (rawDisplay is Map) {
      for (final e in rawDisplay.entries) {
        if (e.key is String && e.value is String) {
          display[e.key as String] = e.value as String;
        }
      }
    }
    int i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return WeeklyCheckin(
      id: (j['id'] as String?) ?? date.microsecondsSinceEpoch.toString(),
      week: i(j['week'], 0).clamp(0, 104).toInt(),
      date: date,
      values: values,
      display: display,
      bodyWeightKg: (j['bodyWeightKg'] as num?)?.toDouble(),
      energy: i(j['energy'], 3).clamp(1, 5).toInt(),
      pain: j['pain'] == true,
      painNote: (j['painNote'] as String?) ?? '',
      sessionsDone: i(j['sessionsDone'], 0),
      sessionsPlanned: i(j['sessionsPlanned'], 0),
      stepDays: i(j['stepDays'], 0),
      note: (j['note'] as String?) ?? '',
    );
  }
}

class CheckinController extends StateNotifier<List<WeeklyCheckin>> {
  CheckinController() : super(_load());

  static List<WeeklyCheckin> _load() => LocalDb.readAllJson(LocalDb.checkins)
      .map(WeeklyCheckin.tryParse)
      .whereType<WeeklyCheckin>()
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  /// Guarda el check-in (si ya había uno de esa semana, lo reemplaza).
  Future<void> save(WeeklyCheckin c) async {
    final box = LocalDb.box(LocalDb.checkins);
    for (final old in state.where((x) => x.week == c.week && x.id != c.id)) {
      await box.delete(old.id);
    }
    await LocalDb.writeJson(LocalDb.checkins, c.id, c.toJson());
    state = [...state.where((x) => x.week != c.week), c]
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> remove(String id) async {
    await LocalDb.box(LocalDb.checkins).delete(id);
    state = state.where((c) => c.id != id).toList();
  }

  /// Al cambiar de plan, las semanas vuelven a empezar: se conservan los
  /// valores (para comparar récords) pero se renumeran como historial.
  void reset() => state = const [];
}

final checkinProvider =
    StateNotifierProvider<CheckinController, List<WeeklyCheckin>>(
  (ref) => CheckinController(),
);
