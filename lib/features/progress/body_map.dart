import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'muscle_group.dart';
import 'progress_engine.dart';

enum BodySide { front, back }

/// Forma descrita con un subconjunto de la sintaxis "d" de SVG
/// (M, L, C, Q, Z absolutos). `mirror` duplica la forma reflejada en el eje
/// central, así solo se dibuja el lado izquierdo de cada músculo par.
class _S {
  const _S(this.muscle, this.d, {this.mirror = false});
  final MuscleGroup? muscle;
  final String d;
  final bool mirror;
}

class _Region {
  const _Region(this.muscle, this.path);
  final MuscleGroup? muscle;
  final Path path;
}

/// Geometría vectorial original del cuerpo (vista frontal y posterior) en un
/// lienzo lógico de 200 × 430, con estilo de lámina anatómica: silueta
/// neutra + paneles musculares separados por líneas.
class BodyGeometry {
  BodyGeometry._();

  static const Size canvas = Size(200, 430);

  /// Refleja respecto al eje vertical central (x → 200 − x).
  static final Float64List _mirrorMatrix = Float64List.fromList(<double>[
    -1, 0, 0, 0, //
    0, 1, 0, 0, //
    0, 0, 1, 0, //
    200, 0, 0, 1, //
  ]);

  static final RegExp _token = RegExp(r'[MLCQZ]|-?\d+(?:\.\d+)?');

  /// Parser mínimo de path SVG → [Path] de Flutter.
  static Path parse(String d) {
    final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
    final path = Path();
    var i = 0;
    var cmd = 'M';
    double next() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'^[MLCQZ]$').hasMatch(t)) {
        cmd = t;
        i++;
        if (cmd == 'Z') {
          path.close();
          continue;
        }
      }
      switch (cmd) {
        case 'M':
          path.moveTo(next(), next());
          cmd = 'L'; // pares extra tras M son líneas, como en SVG
        case 'L':
          path.lineTo(next(), next());
        case 'C':
          path.cubicTo(next(), next(), next(), next(), next(), next());
        case 'Q':
          path.quadraticBezierTo(next(), next(), next(), next());
        default:
          i++;
      }
    }
    return path;
  }

  static List<_Region> _build(List<_S> shapes) {
    final out = <_Region>[];
    for (final s in shapes) {
      final p = parse(s.d);
      out.add(_Region(s.muscle, p));
      if (s.mirror) out.add(_Region(s.muscle, p.transform(_mirrorMatrix)));
    }
    return out;
  }

  static final List<_Region> neutral = _build(_neutral);
  static final List<_Region> front = _build(_front);
  static final List<_Region> back = _build(_back);
  static final List<_Region> frontLines = _build(_frontLines);
  static final List<_Region> backLines = _build(_backLines);

  static List<_Region> regions(BodySide side) =>
      side == BodySide.front ? front : back;

  static List<_Region> lines(BodySide side) =>
      side == BodySide.front ? frontLines : backLines;

  static const List<_S> _neutral = [
    _S(null, 'M100,4 C112,4 118,14 118,26 C118,40 110,50 100,50 C90,50 82,40 82,26 C82,14 88,4 100,4 Z', mirror: false),
    _S(null, 'M90,40 L110,40 L118,68 L82,68 Z', mirror: false),
    _S(null, 'M66,64 L134,64 C142,90 132,122 127,150 C125,166 129,182 131,204 L100,214 L69,204 C71,182 75,166 73,150 C68,122 58,90 66,64 Z', mirror: false),
    _S(null, 'M62,66 C48,70 42,96 38,150 L56,154 C60,128 66,108 72,90 Z', mirror: true),
    _S(null, 'M37,146 C30,170 24,192 21,214 L37,217 C43,194 50,172 56,152 Z', mirror: true),
    _S(null, 'M22,212 C15,222 13,238 18,248 C23,253 31,251 34,243 C37,233 37,222 36,216 Z', mirror: true),
    _S(null, 'M69,196 C65,232 67,270 75,302 C73,332 75,370 80,398 L97,398 C99,370 99,332 97,302 C99,270 101,240 100,212 Z', mirror: true),
    _S(null, 'M80,394 C75,404 72,418 79,426 L99,426 C101,414 99,402 97,394 Z', mirror: true),
  ];

  static const List<_S> _front = [
    _S(MuscleGroup.traps, 'M90,52 C88,60 78,64 66,67 L88,69 Z', mirror: true),
    _S(MuscleGroup.shoulders, 'M70,64 C55,62 44,74 42,94 C42,102 44,108 46,112 C52,102 60,95 68,90 C73,82 75,72 70,64 Z', mirror: true),
    _S(MuscleGroup.chest, 'M99,72 L99,113 C90,118 77,116 70,107 C64,99 65,86 70,76 C78,70 90,70 99,72 Z', mirror: true),
    _S(MuscleGroup.biceps, 'M48,110 C43,124 40,138 41,148 L56,151 C60,136 64,120 68,100 C60,97 52,100 48,110 Z', mirror: true),
    _S(MuscleGroup.forearms, 'M39,156 C32,174 26,192 22,208 L36,212 C42,194 49,176 55,158 Z', mirror: true),
    _S(MuscleGroup.abs, 'M88,117 L112,117 C115,142 115,172 111,200 L100,207 L89,200 C85,172 85,142 88,117 Z', mirror: false),
    _S(MuscleGroup.obliques, 'M85,117 C76,119 72,132 72,148 C72,168 78,186 87,199 C84,172 83,142 85,117 Z', mirror: true),
    _S(MuscleGroup.quads, 'M72,204 C67,232 69,264 77,294 L95,294 C97,268 99,240 99,214 C90,212 80,209 72,204 Z', mirror: true),
    _S(MuscleGroup.calves, 'M78,308 C73,332 75,362 81,388 L95,388 C97,362 97,332 95,308 Z', mirror: true),
  ];

  static const List<_S> _frontLines = [
    _S(null, 'M88,136 L112,136', mirror: false),
    _S(null, 'M87,155 L113,155', mirror: false),
    _S(null, 'M87,174 L113,174', mirror: false),
    _S(null, 'M100,117 L100,205', mirror: false),
    _S(null, 'M86,213 C82,240 83,268 88,292', mirror: true),
    _S(null, 'M87,310 C85,336 85,362 87,386', mirror: true),
  ];

  static const List<_S> _back = [
    _S(MuscleGroup.lats, 'M70,92 C61,112 63,138 74,158 C84,166 92,168 99,168 L99,140 C92,118 82,102 70,92 Z', mirror: true),
    _S(MuscleGroup.traps, 'M100,46 C94,56 82,63 67,67 C80,78 92,100 100,142 C108,100 120,78 133,67 C118,63 106,56 100,46 Z', mirror: false),
    _S(MuscleGroup.shoulders, 'M70,64 C55,62 44,74 42,94 C42,102 44,108 46,112 C52,102 60,95 68,90 C73,82 75,72 70,64 Z', mirror: true),
    _S(MuscleGroup.lowerBack, 'M78,170 L122,170 C123,180 124,190 125,198 L100,206 L75,198 C76,190 77,180 78,170 Z', mirror: false),
    _S(MuscleGroup.triceps, 'M48,106 C43,121 40,136 41,148 L56,151 C60,134 64,118 68,98 C61,95 53,98 48,106 Z', mirror: true),
    _S(MuscleGroup.forearms, 'M39,156 C32,174 26,192 22,208 L36,212 C42,194 49,176 55,158 Z', mirror: true),
    _S(MuscleGroup.glutes, 'M99,206 C87,201 75,202 71,210 C69,226 73,240 83,244 C91,246 97,242 99,236 Z', mirror: true),
    _S(MuscleGroup.hamstrings, 'M72,248 C70,266 72,284 78,300 L95,300 C97,284 99,266 99,248 C90,250 81,250 72,248 Z', mirror: true),
    _S(MuscleGroup.calves, 'M78,310 C70,326 71,348 79,362 C84,370 92,370 94,360 C98,344 98,324 95,310 Z', mirror: true),
  ];

  static const List<_S> _backLines = [
    _S(null, 'M100,142 L100,206', mirror: false),
    _S(null, 'M86,252 C84,270 85,286 87,298', mirror: true),
    _S(null, 'M86,314 C85,332 86,350 88,364', mirror: true),
  ];}

/// Mapa anatómico interactivo. Toca un músculo para ver su detalle.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.side,
    required this.progress,
    this.selected,
    this.onSelect,
  });

  final BodySide side;
  final Map<MuscleGroup, MuscleProgress> progress;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup>? onSelect;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: BodyGeometry.canvas.width / BodyGeometry.canvas.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final scale = size.width / BodyGeometry.canvas.width;
          return GestureDetector(
            onTapUp: (details) {
              final p = details.localPosition / scale;
              // Se recorre al revés: las regiones dibujadas encima ganan.
              for (final r in BodyGeometry.regions(side).reversed) {
                if (r.muscle != null && r.path.contains(p)) {
                  onSelect?.call(r.muscle!);
                  return;
                }
              }
            },
            child: CustomPaint(
              size: size,
              painter: _BodyPainter(
                side: side,
                progress: progress,
                selected: selected,
                scale: scale,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.side,
    required this.progress,
    required this.selected,
    required this.scale,
  });

  final BodySide side;
  final Map<MuscleGroup, MuscleProgress> progress;
  final MuscleGroup? selected;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    // Silueta: contorno claro + relleno neutro, como una lámina anatómica.
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = AurumColors.outline;
    final neutralFill = Paint()..color = AurumColors.surfaceHigh;
    for (final r in BodyGeometry.neutral) {
      canvas.drawPath(r.path, contour);
    }
    for (final r in BodyGeometry.neutral) {
      canvas.drawPath(r.path, neutralFill);
    }

    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = AurumColors.background;

    for (final region in BodyGeometry.regions(side)) {
      final muscle = region.muscle!;
      final score = progress[muscle]?.score ?? 0;
      final color = ProgressEngine.colorFor(score);

      // Halo dorado en músculos de nivel Oro.
      if (score >= 0.85) {
        canvas.drawPath(
          region.path,
          Paint()
            ..color = AurumColors.goldBright.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawPath(region.path, Paint()..color = color);
      canvas.drawPath(region.path, gap);
    }

    // Líneas de definición (abdomen, cabezas del cuádriceps, etc.).
    final detail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..color = AurumColors.background.withValues(alpha: 0.75);
    for (final l in BodyGeometry.lines(side)) {
      canvas.drawPath(l.path, detail);
    }

    // Músculo seleccionado: contorno blanco encima de todo.
    if (selected != null) {
      final highlight = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      for (final r in BodyGeometry.regions(side)) {
        if (r.muscle == selected) canvas.drawPath(r.path, highlight);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.side != side ||
      old.selected != selected ||
      old.scale != scale ||
      !identical(old.progress, progress);
}
