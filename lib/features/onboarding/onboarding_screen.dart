import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/input_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/units.dart';
import 'profile_controller.dart';
import 'user_profile.dart';

/// Onboarding en 4 pasos: datos corporales → actividad y lesiones →
/// objetivo con fecha límite → equipo disponible (obligatorio).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  static const int _steps = 4;

  // Paso 1
  Sex _sex = Sex.male;
  UnitSystem _units = UnitSystem.metric;
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _heightCm = TextEditingController();
  final _heightFt = TextEditingController();
  final _heightIn = TextEditingController();
  final _bodyFat = TextEditingController();

  // Paso 2
  ActivityLevel _activity = ActivityLevel.light;
  final _injuries = TextEditingController();

  // Paso 3
  GoalType _goalType = GoalType.general;
  final _goalText = TextEditingController();
  DateTime _deadline = DateTime.now().add(const Duration(days: 84));

  // Paso 4
  Equipment? _equipment;

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _age,
      _weight,
      _heightCm,
      _heightFt,
      _heightIn,
      _bodyFat,
      _injuries,
      _goalText,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- validación

  int? get _ageValue =>
      InputSanitizer.number(_age.text, min: 13, max: 100)?.round();

  double? get _weightKg {
    final imperial = _units == UnitSystem.imperial;
    final v = InputSanitizer.number(
      _weight.text,
      min: imperial ? 66 : 30,
      max: imperial ? 660 : 300,
    );
    if (v == null) return null;
    return imperial ? Units.lbToKg(v) : v;
  }

  double? get _heightValueCm {
    if (_units == UnitSystem.metric) {
      return InputSanitizer.number(_heightCm.text, min: 120, max: 230);
    }
    final ft = InputSanitizer.number(_heightFt.text, min: 3, max: 7);
    final inches =
        InputSanitizer.number(_heightIn.text.isEmpty ? '0' : _heightIn.text,
            min: 0, max: 11.99);
    if (ft == null || inches == null) return null;
    final cm = Units.inchesToCm(ft * 12 + inches);
    return (cm >= 120 && cm <= 230) ? cm : null;
  }

  double? get _bodyFatValue => _bodyFat.text.trim().isEmpty
      ? null
      : InputSanitizer.number(_bodyFat.text, min: 3, max: 70);

  String? _validateStep() {
    switch (_step) {
      case 0:
        if (_ageValue == null) return 'Edad entre 13 y 100 años.';
        if (_weightKg == null) return 'Revisa el peso.';
        if (_heightValueCm == null) return 'Revisa la altura.';
        if (_bodyFat.text.trim().isNotEmpty && _bodyFatValue == null) {
          return 'El % de grasa debe estar entre 3 y 70 (o déjalo vacío).';
        }
        return null;
      case 1:
        if (InputSanitizer.clean(_injuries.text).suspicious) {
          return 'Describe tus lesiones con palabras normales, sin instrucciones.';
        }
        return null;
      case 2:
        final goal = InputSanitizer.clean(_goalText.text, maxLength: 200);
        if (goal.text.length < 4) return 'Describe tu objetivo en una frase.';
        if (goal.suspicious) {
          return 'Tu objetivo contiene frases que parecen instrucciones para la IA. Reescríbelo.';
        }
        if (_deadline.difference(DateTime.now()).inDays < 7) {
          return 'La fecha límite debe estar al menos a una semana.';
        }
        return null;
      case 3:
        if (_equipment == null) return 'Elige dónde vas a entrenar.';
        return null;
    }
    return null;
  }

  Future<void> _next() async {
    final error = _validateStep();
    setState(() => _error = error);
    if (error != null) return;
    if (_step < _steps - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    final profile = UserProfile(
      sex: _sex,
      age: _ageValue!,
      weightKg: _weightKg!,
      heightCm: _heightValueCm!,
      bodyFatPct: _bodyFatValue,
      activity: _activity,
      equipment: _equipment!,
      injuries: InputSanitizer.clean(_injuries.text).text,
      units: _units,
      goal: Goal(
        type: _goalType,
        description: InputSanitizer.clean(_goalText.text, maxLength: 200).text,
        deadline: _deadline,
      ),
    );
    await ref.read(profileProvider.notifier).save(profile);
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tu perfil · ${_step + 1}/$_steps'),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _step--;
                  _error = null;
                }),
              )
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _steps,
            backgroundColor: AurumColors.surfaceHigh,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: switch (_step) {
                  0 => _bodyStep(),
                  1 => _activityStep(),
                  2 => _goalStep(),
                  _ => _equipmentStep(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AurumColors.danger),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : _next,
                    child: Text(_step == _steps - 1 ? 'Crear mi plan' : 'Siguiente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text, [String? subtitle]) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: AurumColors.textMuted)),
            ],
          ],
        ),
      );

  Widget _numberField(
    TextEditingController c,
    String label, {
    String? suffix,
    bool decimal = true,
  }) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]')),
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }

  Widget _bodyStep() {
    final imperial = _units == UnitSystem.imperial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Datos corporales',
            'Se usan para calcular calorías, macros y cargas iniciales.'),
        SegmentedButton<Sex>(
          segments: [
            for (final s in Sex.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {_sex},
          onSelectionChanged: (s) => setState(() => _sex = s.first),
        ),
        const SizedBox(height: 16),
        SegmentedButton<UnitSystem>(
          segments: const [
            ButtonSegment(value: UnitSystem.metric, label: Text('kg / cm')),
            ButtonSegment(value: UnitSystem.imperial, label: Text('lb / ft')),
          ],
          selected: {_units},
          onSelectionChanged: (s) => setState(() => _units = s.first),
        ),
        const SizedBox(height: 16),
        _numberField(_age, 'Edad', suffix: 'años', decimal: false),
        const SizedBox(height: 12),
        _numberField(_weight, 'Peso', suffix: imperial ? 'lb' : 'kg'),
        const SizedBox(height: 12),
        if (imperial)
          Row(
            children: [
              Expanded(child: _numberField(_heightFt, 'Altura', suffix: 'ft', decimal: false)),
              const SizedBox(width: 12),
              Expanded(child: _numberField(_heightIn, '', suffix: 'in')),
            ],
          )
        else
          _numberField(_heightCm, 'Altura', suffix: 'cm'),
        const SizedBox(height: 12),
        _numberField(_bodyFat, '% de grasa estimado (opcional)', suffix: '%'),
      ],
    );
  }

  Widget _activityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Actividad actual'),
        for (final a in ActivityLevel.values)
          RadioListTile<ActivityLevel>(
            value: a,
            groupValue: _activity,
            onChanged: (v) => setState(() => _activity = v ?? _activity),
            title: Text(a.label),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _injuries,
          maxLines: 3,
          maxLength: 400,
          decoration: const InputDecoration(
            labelText: 'Lesiones o restricciones médicas',
            hintText: 'Ej.: dolor de rodilla derecha, hipertensión controlada…',
          ),
        ),
        const Text(
          'Esto adapta los ejercicios, pero no sustituye la valoración de un profesional de la salud.',
          style: TextStyle(color: AurumColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _goalStep() {
    final weeks = (_deadline.difference(DateTime.now()).inDays / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Tu objetivo', 'Con una fecha límite concreta.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in GoalType.values)
              ChoiceChip(
                label: Text(g.label),
                selected: _goalType == g,
                onSelected: (_) => setState(() => _goalType = g),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _goalText,
          maxLength: 200,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Descríbelo con tus palabras',
            hintText: 'Ej.: Subir el Volcán Acatenango en 3 meses',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final w in const [4, 8, 12, 24])
              ActionChip(
                label: Text('$w semanas'),
                onPressed: () => setState(() => _deadline =
                    DateTime.now().add(Duration(days: w * 7))),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, color: AurumColors.gold),
          title: Text(
            'Fecha límite: ${_deadline.day}/${_deadline.month}/${_deadline.year}',
          ),
          subtitle: Text('$weeks semanas'),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _deadline,
              firstDate: now.add(const Duration(days: 7)),
              lastDate: now.add(const Duration(days: 730)),
            );
            if (picked != null) setState(() => _deadline = picked);
          },
        ),
      ],
    );
  }

  Widget _equipmentStep() {
    const icons = {
      Equipment.gym: Icons.fitness_center,
      Equipment.calisthenics: Icons.park_outlined,
      Equipment.home: Icons.home_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('¿Dónde entrenas?', 'La rutina solo usará el equipo que tengas.'),
        for (final e in Equipment.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _equipment == e ? AurumColors.gold : AurumColors.outline,
                  width: _equipment == e ? 2 : 1,
                ),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: Icon(icons[e], color: AurumColors.gold, size: 30),
                title: Text(e.label),
                onTap: () => setState(() => _equipment = e),
              ),
            ),
          ),
      ],
    );
  }
}
