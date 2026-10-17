import 'package:flutter/foundation.dart';

import '../onboarding/user_profile.dart';

/// Qué significa en números el objetivo que escribió el usuario.
@immutable
class GoalSpec {
  const GoalSpec({
    required this.type,
    required this.headline,
    this.facts = const [],
    this.elevationGainM,
    this.ascentHours,
    this.packKg,
    this.distanceKm,
    this.raceMinutes,
    this.weightChangeKg,
    this.liftBenchmark,
    this.liftLabel,
    this.liftTargetKg,
  });

  /// Tipo efectivo (puede corregir la categoría elegida si el texto es claro,
  /// p. ej. "General" + "correr 10k" → carrera).
  final GoalType type;
  final String headline;
  final List<String> facts;

  // Montaña
  final int? elevationGainM;
  final double? ascentHours;
  final double? packKg;

  // Carrera
  final double? distanceKm;
  final int? raceMinutes;

  // Composición corporal (+ ganar, − perder)
  final double? weightChangeKg;

  // Fuerza
  final String? liftBenchmark;
  final String? liftLabel;
  final double? liftTargetKg;
}

class _Peak {
  const _Peak(this.pattern, this.name, this.altitude, this.gain, this.hours,
      this.pack, this.note);
  final String pattern;
  final String name;
  final int altitude;
  final int gain;
  final double hours;
  final double pack;
  final String note;
}

/// Convierte la meta en lenguaje natural en parámetros de entrenamiento.
/// Todo se calcula en el teléfono; los datos de montañas son aproximados.
class GoalAnalyzer {
  GoalAnalyzer._();

  static const List<_Peak> _peaks = [
    _Peak(r'acatenango', 'Volcán Acatenango', 3976, 1500, 5.5, 10,
        'Ruta habitual desde La Soledad, casi siempre en 2 días con noche en campamento.'),
    _Peak(r'fuego', 'Volcán de Fuego (vía Acatenango)', 3763, 1900, 8, 10,
        'Se sube desde el campamento del Acatenango; ve solo con guías autorizados.'),
    _Peak(r'tajumulco', 'Volcán Tajumulco', 4220, 1200, 5, 10,
        'El punto más alto de Centroamérica: la altura y el frío pesan tanto como el desnivel.'),
    _Peak(r'volcan de agua|\bagua volcano', 'Volcán de Agua', 3760, 1700, 5.5, 6,
        'Subida larga y constante desde Santa María de Jesús.'),
    _Peak(r'pacaya', 'Volcán de Pacaya', 2552, 600, 2, 3,
        'Ruta corta y popular; buena primera meta o paso intermedio.'),
    _Peak(r'santa maria|santiaguito', 'Volcán Santa María', 3772, 1400, 4.5, 6,
        'Sendero empinado desde Llano del Pinal, cerca de Quetzaltenango.'),
    _Peak(r'atitlan', 'Volcán Atitlán', 3537, 1900, 6.5, 6,
        'Uno de los ascensos con más desnivel del lago; exige piernas para bajar.'),
    _Peak(r'toliman', 'Volcán Tolimán', 3158, 1500, 5, 6,
        'Sendero poco marcado: siempre con guía local.'),
    _Peak(r'san pedro', 'Volcán San Pedro', 3020, 1200, 3.5, 4,
        'Subida empinada y sostenida desde San Pedro La Laguna.'),
    _Peak(r'chicabal', 'Volcán Chicabal', 2900, 500, 2, 3,
        'Laguna sagrada en el cráter; ruta corta.'),
    _Peak(r'nariz del indio|indian nose', 'Nariz del Indio', 2350, 400, 1, 2,
        'Ruta corta para ver el amanecer sobre el lago.'),
  ];

  static String _norm(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  static double? _num(String s) => double.tryParse(s.replaceAll(',', '.'));

  static String _fmtInt(num n) {
    final s = n.round().toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  static String fmtHours(double h) {
    final totalMin = (h * 60).round();
    final hh = totalMin ~/ 60;
    final mm = totalMin % 60;
    return mm == 0 ? '$hh h' : '$hh h $mm min';
  }

  static GoalSpec analyze(UserProfile p) {
    final text = _norm(p.goal.description);
    var type = p.goal.type;

    final mentionsMountain =
        RegExp(r'volcan|montan|cerro|senderis|hiking|trek|cumbre|ascen').hasMatch(text) ||
            _peaks.any((k) => RegExp(k.pattern).hasMatch(text));
    final mentionsRun =
        RegExp(r'correr|carrera|trot|maraton|\b\d+ ?k\b|\d+ ?km').hasMatch(text);
    if (type == GoalType.general) {
      if (mentionsMountain) {
        type = GoalType.mountain;
      } else if (mentionsRun) {
        type = GoalType.running;
      }
    }

    switch (type) {
      case GoalType.mountain:
        return _mountain(text, p);
      case GoalType.running:
        return _running(text, p);
      case GoalType.muscle:
      case GoalType.fatLoss:
        return _bodyComp(text, p, type);
      case GoalType.strength:
        return _strength(text, p);
      case GoalType.general:
        return GoalSpec(
          type: type,
          headline: p.goal.description.isEmpty
              ? 'Condición física general'
              : p.goal.description,
          facts: const [
            'Fuerza en todo el cuerpo 3 días por semana',
            'Base aeróbica y pasos diarios',
          ],
        );
    }
  }

  static GoalSpec _mountain(String text, UserProfile p) {
    _Peak? peak;
    for (final k in _peaks) {
      if (RegExp(k.pattern).hasMatch(text)) {
        peak = k;
        break;
      }
    }

    var gain = peak?.gain ?? 1000;
    var hours = peak?.hours ?? 4.0;
    var pack = peak?.pack ?? 7.0;

    final gainMatch = RegExp(r'(\d{3,4}) ?m(etros)? de desnivel').firstMatch(text);
    if (gainMatch != null) gain = int.parse(gainMatch.group(1)!).clamp(200, 3000).toInt();
    final hoursMatch = RegExp(r'(\d+(?:[.,]\d+)?) ?h(oras)?\b').firstMatch(text);
    if (hoursMatch != null) {
      hours = (_num(hoursMatch.group(1)!) ?? hours).clamp(1, 14).toDouble();
    }
    final packMatch = RegExp(r'mochila de (\d+(?:[.,]\d+)?) ?(kg|kilos)').firstMatch(text);
    if (packMatch != null) {
      pack = (_num(packMatch.group(1)!) ?? pack).clamp(2, 25).toDouble();
    }

    return GoalSpec(
      type: GoalType.mountain,
      headline: peak == null
          ? 'Montaña · ~${_fmtInt(gain)} m de desnivel'
          : '${peak.name} · ${_fmtInt(peak.altitude)} m',
      facts: [
        '≈ ${_fmtInt(gain)} m de desnivel positivo',
        '≈ ${fmtHours(hours)} de subida (ritmo promedio)',
        'Mochila de ~${pack.round()} kg',
        if (peak != null) peak.note,
        'La bajada castiga las rodillas: el plan incluye trabajo excéntrico.',
      ],
      elevationGainM: gain,
      ascentHours: hours,
      packKg: pack,
    );
  }

  static GoalSpec _running(String text, UserProfile p) {
    double? km;
    if (RegExp(r'media maraton|medio maraton|\b21 ?k\b|21[.,]1').hasMatch(text)) {
      km = 21.1;
    } else if (RegExp(r'maraton|\b42 ?k\b').hasMatch(text)) {
      km = 42.2;
    } else {
      final m = RegExp(r'(\d+(?:[.,]\d+)?) ?(k|km|kilometros?)\b').firstMatch(text);
      if (m != null) km = _num(m.group(1)!);
    }
    km = (km ?? 10).clamp(1, 100).toDouble();

    int? minutes;
    final t = RegExp(r'(?:en|bajo|menos de|sub) ?(\d{1,3}) ?(min|minutos)').firstMatch(text);
    if (t != null) minutes = int.parse(t.group(1)!).clamp(10, 600).toInt();
    final hm = RegExp(r'(?:en|bajo|menos de|sub) ?(\d)[:h](\d{2})').firstMatch(text);
    if (hm != null) {
      minutes = int.parse(hm.group(1)!) * 60 + int.parse(hm.group(2)!);
    }

    final label = km == 21.1
        ? 'Media maratón'
        : km == 42.2
            ? 'Maratón'
            : '${km == km.roundToDouble() ? km.round() : km} km';
    return GoalSpec(
      type: GoalType.running,
      headline: 'Carrera · $label${minutes != null ? ' en ${_fmtTime(minutes)}' : ''}',
      facts: [
        'Distancia objetivo: ${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1)} km',
        if (minutes != null)
          'Ritmo objetivo: ${_pace(minutes * 60 / km)} por km',
        'La tirada larga crece poco a poco y baja las 2 últimas semanas.',
      ],
      distanceKm: km,
      raceMinutes: minutes,
    );
  }

  static String _fmtTime(int minutes) => minutes >= 60
      ? '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h'
      : '$minutes min';

  static String _pace(double secondsPerKm) {
    final s = secondsPerKm.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static GoalSpec _bodyComp(String text, UserProfile p, GoalType type) {
    final weeks = p.goal.weeksLeft;
    double? change;
    final m = RegExp(
            r'(ganar|subir|aumentar|bajar|perder|reducir|quitar)\D{0,25}?(\d+(?:[.,]\d+)?) ?(kg|kilos|libras|lb)')
        .firstMatch(text);
    if (m != null) {
      var v = _num(m.group(2)!) ?? 0;
      if (m.group(3) == 'libras' || m.group(3) == 'lb') v = v / 2.2046;
      final down = RegExp(r'bajar|perder|reducir|quitar').hasMatch(m.group(1)!);
      change = down ? -v : v;
    }

    final facts = <String>[];
    if (type == GoalType.fatLoss) {
      final safe = p.weightKg * 0.0075 * weeks; // ≤ 0.75 % por semana
      change ??= -(p.weightKg * 0.005 * weeks).clamp(1, p.weightKg * 0.12).toDouble();
      final perWeek = -change / weeks;
      facts.add('Meta: −${(-change).toStringAsFixed(1)} kg en $weeks semanas '
          '(${perWeek.toStringAsFixed(2)} kg/semana)');
      if (-change > safe) {
        facts.add('Es una meta agresiva: lo recomendable es ≤ '
            '${(p.weightKg * 0.0075).toStringAsFixed(2)} kg por semana para no perder músculo.');
      }
      facts.add('Fuerza 3 días para conservar músculo + cardio y pasos para el déficit.');
    } else {
      final realistic = (0.2 * weeks).clamp(0.5, 6).toDouble();
      change ??= realistic;
      facts.add('Meta: +${change.toStringAsFixed(1)} kg en $weeks semanas');
      if (change > realistic * 1.5) {
        facts.add('Ganar más de ~${(0.25 * weeks).toStringAsFixed(1)} kg en ese tiempo suele ser grasa, no músculo.');
      }
      facts.add('Bloques de 4 semanas: acumulación, intensificación y descarga.');
    }

    return GoalSpec(
      type: type,
      headline: type == GoalType.fatLoss
          ? 'Pérdida de grasa · ${(p.weightKg + change).toStringAsFixed(1)} kg meta'
          : 'Hipertrofia · ${(p.weightKg + change).toStringAsFixed(1)} kg meta',
      facts: facts,
      weightChangeKg: change,
    );
  }

  static GoalSpec _strength(String text, UserProfile p) {
    const lifts = <String, (String, String)>{
      r'sentadilla|squat': ('squat_1rm', 'Sentadilla'),
      r'banca|bench|press de pecho': ('bench_1rm', 'Press de banca'),
      r'peso muerto|deadlift': ('hinge_1rm', 'Peso muerto'),
      r'remo|row': ('row_1rm', 'Remo'),
    };
    String? id;
    String? label;
    double? kg;
    for (final e in lifts.entries) {
      final m = RegExp('(${e.key})\\D{0,25}?(\\d{2,3}(?:[.,]\\d+)?) ?(kg|kilos)').firstMatch(text);
      if (m != null) {
        id = e.value.$1;
        label = e.value.$2;
        kg = _num(m.group(2)!);
        break;
      }
    }
    return GoalSpec(
      type: GoalType.strength,
      headline: label != null && kg != null
          ? 'Fuerza · $label ${kg.round()} kg'
          : 'Fuerza máxima',
      facts: [
        'Fases: volumen → fuerza → pico, con descarga cada 4 semanas.',
        if (label != null && kg != null)
          'La prueba de 1RM se hace la última semana, siempre con ayudante.',
        'Registra cada semana tu mejor serie para estimar tu 1RM.',
      ],
      liftBenchmark: id,
      liftLabel: label,
      liftTargetKg: kg,
    );
  }
}
