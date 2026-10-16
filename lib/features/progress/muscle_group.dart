enum MuscleGroup {
  chest,
  abs,
  obliques,
  shoulders,
  biceps,
  triceps,
  forearms,
  traps,
  lats,
  lowerBack,
  glutes,
  quads,
  hamstrings,
  calves,
}

extension MuscleGroupX on MuscleGroup {
  String get label => switch (this) {
        MuscleGroup.chest => 'Pectorales',
        MuscleGroup.abs => 'Abdomen',
        MuscleGroup.obliques => 'Oblicuos',
        MuscleGroup.shoulders => 'Deltoides',
        MuscleGroup.biceps => 'Bíceps',
        MuscleGroup.triceps => 'Tríceps',
        MuscleGroup.forearms => 'Antebrazos',
        MuscleGroup.traps => 'Trapecio',
        MuscleGroup.lats => 'Espalda (dorsales)',
        MuscleGroup.lowerBack => 'Lumbares',
        MuscleGroup.glutes => 'Glúteos',
        MuscleGroup.quads => 'Cuádriceps',
        MuscleGroup.hamstrings => 'Isquiotibiales',
        MuscleGroup.calves => 'Pantorrillas',
      };

  /// Acepta el nombre interno o sinónimos en español que pueda devolver la IA.
  static MuscleGroup? tryParse(Object? raw) {
    if (raw is! String) return null;
    final v = raw.trim().toLowerCase();
    for (final m in MuscleGroup.values) {
      if (m.name.toLowerCase() == v) return m;
    }
    const synonyms = <String, MuscleGroup>{
      'pecho': MuscleGroup.chest,
      'pectorales': MuscleGroup.chest,
      'abdomen': MuscleGroup.abs,
      'core': MuscleGroup.abs,
      'oblicuos': MuscleGroup.obliques,
      'hombros': MuscleGroup.shoulders,
      'deltoides': MuscleGroup.shoulders,
      'biceps': MuscleGroup.biceps,
      'bíceps': MuscleGroup.biceps,
      'triceps': MuscleGroup.triceps,
      'tríceps': MuscleGroup.triceps,
      'antebrazos': MuscleGroup.forearms,
      'trapecio': MuscleGroup.traps,
      'espalda': MuscleGroup.lats,
      'dorsales': MuscleGroup.lats,
      'back': MuscleGroup.lats,
      'lumbar': MuscleGroup.lowerBack,
      'lumbares': MuscleGroup.lowerBack,
      'gluteos': MuscleGroup.glutes,
      'glúteos': MuscleGroup.glutes,
      'cuadriceps': MuscleGroup.quads,
      'cuádriceps': MuscleGroup.quads,
      'isquiotibiales': MuscleGroup.hamstrings,
      'isquios': MuscleGroup.hamstrings,
      'femorales': MuscleGroup.hamstrings,
      'pantorrillas': MuscleGroup.calves,
      'gemelos': MuscleGroup.calves,
    };
    return synonyms[v];
  }
}
