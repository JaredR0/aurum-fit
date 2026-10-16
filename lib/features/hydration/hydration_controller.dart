import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../../core/utils/units.dart';

/// Registro diario de agua (ml), guardado en la base cifrada.
class HydrationController extends StateNotifier<int> {
  HydrationController() : super(_read(DateTime.now()));

  static int _read(DateTime day) {
    final v = LocalDb.box(LocalDb.hydration).get(Units.dayKey(day));
    return v is int ? v : 0;
  }

  Future<void> add(int ml) async {
    final value = (state + ml).clamp(0, 15000).toInt();
    await LocalDb.box(LocalDb.hydration).put(Units.dayKey(DateTime.now()), value);
    state = value;
  }

  /// Relee el día actual (p. ej. al volver a la app después de medianoche).
  void refresh() => state = _read(DateTime.now());

  int on(DateTime day) => _read(day);
}

final hydrationProvider = StateNotifierProvider<HydrationController, int>(
  (ref) => HydrationController(),
);
