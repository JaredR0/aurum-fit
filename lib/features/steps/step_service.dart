import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/units.dart';

enum StepSource { none, sensor, healthConnect, healthKit }

@immutable
class StepState {
  const StepState({
    this.today = 0,
    this.source = StepSource.none,
    this.permissionDenied = false,
    this.history = const {},
  });

  final int today;
  final StepSource source;
  final bool permissionDenied;

  /// yyyy-mm-dd → pasos (últimos días guardados localmente).
  final Map<String, int> history;

  StepState copyWith({
    int? today,
    StepSource? source,
    bool? permissionDenied,
    Map<String, int>? history,
  }) =>
      StepState(
        today: today ?? this.today,
        source: source ?? this.source,
        permissionDenied: permissionDenied ?? this.permissionDenied,
        history: history ?? this.history,
      );
}

/// Podómetro nativo con dos fuentes:
///
/// 1. **Sensor de pasos del teléfono** (TYPE_STEP_COUNTER en Android,
///    CMPedometer en iOS) para el conteo en tiempo real.
/// 2. **Health Connect / HealthKit** (solo lectura de pasos) para el total
///    del día, que incluye relojes y otras apps.
///
/// Se muestra el mayor de ambos. Los datos se quedan en el teléfono: nunca se
/// envían al proxy ni a ningún servidor.
class StepController extends StateNotifier<StepState> {
  StepController() : super(const StepState()) {
    state = state.copyWith(history: _loadHistory());
    final todayKey = Units.dayKey(DateTime.now());
    state = state.copyWith(today: state.history[todayKey] ?? 0);
  }

  StreamSubscription<StepCount>? _sub;
  Timer? _healthPoll;
  final Health _health = Health();
  bool _healthAuthorized = false;
  bool _started = false;

  static const String _sensorKey = 'sensor_state';

  Map<String, int> _loadHistory() {
    final box = LocalDb.box(LocalDb.steps);
    final out = <String, int>{};
    for (final key in box.keys) {
      final v = box.get(key);
      if (key is String && key.startsWith('day:') && v is int) {
        out[key.substring(4)] = v;
      }
    }
    return out;
  }

  /// Pide permisos en tiempo de ejecución y arranca las fuentes de datos.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final permission = Platform.isAndroid
        ? Permission.activityRecognition
        : Permission.sensors;
    final status = await permission.request();
    if (!status.isGranted) {
      state = state.copyWith(permissionDenied: true);
    } else {
      _listenSensor();
    }

    await _connectHealth();
    if (_healthAuthorized) {
      await _pollHealth();
      _healthPoll =
          Timer.periodic(const Duration(minutes: 5), (_) => _pollHealth());
    }
  }

  void _listenSensor() {
    _sub = Pedometer.stepCountStream.listen(
      _onSensor,
      onError: (_) {},
      cancelOnError: false,
    );
    if (state.source == StepSource.none) {
      state = state.copyWith(source: StepSource.sensor);
    }
  }

  /// El sensor entrega pasos acumulados desde el último reinicio del
  /// teléfono; se guarda una línea base diaria para obtener "pasos de hoy".
  void _onSensor(StepCount event) {
    final raw = event.steps;
    final todayKey = Units.dayKey(DateTime.now());
    final saved = LocalDb.readJson(LocalDb.steps, _sensorKey);

    var baseline = raw;
    var lastRaw = raw;
    var counted = 0;
    if (saved != null && saved['day'] == todayKey) {
      baseline = (saved['baseline'] as num?)?.toInt() ?? raw;
      lastRaw = (saved['lastRaw'] as num?)?.toInt() ?? raw;
      counted = (saved['counted'] as num?)?.toInt() ?? 0;
      if (raw < lastRaw) {
        // El teléfono se reinició: el contador volvió a cero.
        baseline = raw - counted;
      }
    } else {
      // Primer evento del día: se conserva lo ya registrado hoy (si lo hay).
      counted = state.history[todayKey] ?? 0;
      baseline = raw - counted;
    }

    final sensorToday = (raw - baseline).clamp(0, 200000).toInt();
    LocalDb.writeJson(LocalDb.steps, _sensorKey, {
      'day': todayKey,
      'baseline': baseline,
      'lastRaw': raw,
      'counted': sensorToday,
    });
    _update(sensorToday, StepSource.sensor);
  }

  Future<void> _connectHealth() async {
    try {
      await _health.configure();
      const types = [HealthDataType.STEPS];
      final has = await _health.hasPermissions(types,
          permissions: const [HealthDataAccess.READ]);
      _healthAuthorized = has == true ||
          await _health.requestAuthorization(types,
              permissions: const [HealthDataAccess.READ]);
    } catch (_) {
      // Health Connect no instalado o no soportado: se usa solo el sensor.
      _healthAuthorized = false;
    }
  }

  Future<void> _pollHealth() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await _health.getTotalStepsInInterval(midnight, now);
      if (steps != null) {
        _update(
          steps,
          Platform.isIOS ? StepSource.healthKit : StepSource.healthConnect,
        );
      }
    } catch (_) {}
  }

  void _update(int value, StepSource source) {
    final todayKey = Units.dayKey(DateTime.now());
    final previous = state.history[todayKey] ?? 0;
    final best = value > previous ? value : previous;
    final history = Map<String, int>.from(state.history)..[todayKey] = best;
    LocalDb.box(LocalDb.steps).put('day:$todayKey', best);
    state = state.copyWith(
      today: best,
      history: history,
      source: value >= previous ? source : state.source,
    );
  }

  /// Pasos registrados para un día concreto.
  int stepsOn(DateTime day) => state.history[Units.dayKey(day)] ?? 0;

  @override
  void dispose() {
    _sub?.cancel();
    _healthPoll?.cancel();
    super.dispose();
  }
}

final stepProvider = StateNotifierProvider<StepController, StepState>(
  (ref) => StepController(),
);
