import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../onboarding/user_profile.dart';
import 'local_plan_generator.dart';
import 'plan_api.dart';
import 'plan_models.dart';

@immutable
class PlanState {
  const PlanState({this.plan, this.loading = false, this.message});

  final FitnessPlan? plan;
  final bool loading;

  /// Último aviso para el usuario (error de IA, fallback, etc.).
  final String? message;
}

class PlanController extends StateNotifier<PlanState> {
  PlanController() : super(PlanState(plan: _load()));

  static const String _key = 'current';

  static FitnessPlan? _load() {
    final json = LocalDb.readJson(LocalDb.plans, _key);
    final plan = json == null ? null : FitnessPlan.tryParse(json);
    // Los planes locales de la versión 1 eran una sola semana repetida: se
    // regeneran con el nuevo generador periodizado.
    if (plan != null &&
        plan.training.source == 'local' &&
        plan.training.schemaVersion < TrainingPlan.currentSchema) {
      return null;
    }
    return plan;
  }

  Future<void> _save(FitnessPlan plan, {String? message}) async {
    await LocalDb.writeJson(LocalDb.plans, _key, plan.toJson());
    state = PlanState(plan: plan, message: message);
  }

  /// Plan inmediato y offline. Se crea al terminar el onboarding.
  Future<void> generateLocal(UserProfile profile) =>
      _save(LocalPlanGenerator.generate(profile));

  /// Plan con IA + búsqueda de evidencia. Si falla, se conserva el plan
  /// actual (o se genera uno local) y se informa el motivo.
  Future<void> generateWithAi(
    UserProfile profile, {
    String request = '',
    Map<String, double> progress = const {},
  }) async {
    state = PlanState(plan: state.plan, loading: true);
    try {
      final plan = await PlanApi.generate(profile,
          extraRequest: request, progress: progress);
      await _save(plan, message: 'Plan generado con IA.');
    } on PlanApiException catch (e) {
      final fallback = state.plan ?? LocalPlanGenerator.generate(profile);
      await _save(fallback, message: e.message);
    }
  }

  void clearMessage() =>
      state = PlanState(plan: state.plan, loading: state.loading);

  void reset() => state = const PlanState();
}

final planProvider = StateNotifierProvider<PlanController, PlanState>(
  (ref) => PlanController(),
);
