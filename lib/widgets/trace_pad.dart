import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Zone de tracé : l'utilisateur dessine par-dessus un modèle en filigrane.
/// [TracePadController.score] compare le tracé au caractère (0 à 1).
class TracePadController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size size = Size.zero;

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) strokes.removeLast();
    notifyListeners();
  }

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  static const _n = 48; // résolution de la grille de comparaison

  static Future<Uint8List> _glyphMask(String glyph, double side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_n / side);
    final tp = _painter(glyph, side, Colors.black);
    tp.paint(canvas,
        Offset((side - tp.width) / 2, (side - tp.height) / 2));
    final img = await recorder.endRecording().toImage(_n, _n);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final mask = Uint8List(_n * _n);
    if (data == null) return mask;
    for (var i = 0; i < _n * _n; i++) {
      mask[i] = data.getUint8(i * 4 + 3) > 60 ? 1 : 0;
    }
    return mask;
  }

  Uint8List _userMask(double side, double strokeWidth) {
    final mask = Uint8List(_n * _n);
    final cell = side / _n;
    final r = max(1, (strokeWidth / 2 / cell).round());
    void mark(Offset p) {
      final cx = (p.dx / cell).floor();
      final cy = (p.dy / cell).floor();
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final x = cx + dx, y = cy + dy;
          if (x >= 0 && y >= 0 && x < _n && y < _n && dx * dx + dy * dy <= r * r) {
            mask[y * _n + x] = 1;
          }
        }
      }
    }

    for (final s in strokes) {
      for (var i = 0; i < s.length; i++) {
        mark(s[i]);
        if (i > 0) {
          final a = s[i - 1], b = s[i];
          final steps = ((b - a).distance / (cell / 2)).ceil();
          for (var k = 1; k < steps; k++) {
            mark(Offset.lerp(a, b, k / steps)!);
          }
        }
      }
    }
    return mask;
  }

  static Uint8List _dilate(Uint8List m, int r) {
    final out = Uint8List(_n * _n);
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        if (m[y * _n + x] == 0) continue;
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx >= 0 && yy >= 0 && xx < _n && yy < _n) out[yy * _n + xx] = 1;
          }
        }
      }
    }
    return out;
  }

  /// Score F1 entre le tracé et le caractère modèle.
  Future<double> score(String glyph, {double strokeWidth = 18}) async {
    if (isEmpty || size.isEmpty) return 0;
    final side = size.shortestSide;
    final g = await _glyphMask(glyph, side);
    final u = _userMask(side, strokeWidth);
    final gD = _dilate(g, 2);
    final uD = _dilate(u, 2);
    var uCount = 0, uIn = 0, gCount = 0, gCovered = 0;
    for (var i = 0; i < _n * _n; i++) {
      if (u[i] == 1) {
        uCount++;
        if (gD[i] == 1) uIn++;
      }
      if (g[i] == 1) {
        gCount++;
        if (uD[i] == 1) gCovered++;
      }
    }
    if (uCount == 0 || gCount == 0) return 0;
    final p = uIn / uCount;
    final r = gCovered / gCount;
    if (p + r == 0) return 0;
    return 2 * p * r / (p + r);
  }
}

TextPainter _painter(String glyph, double side, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: glyph,
      style: TextStyle(fontSize: side * 0.78, color: color, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp;
}

class TracePad extends StatefulWidget {
  final String glyph;
  final TracePadController controller;
  final bool showGuide;
  const TracePad(
      {super.key,
      required this.glyph,
      required this.controller,
      this.showGuide = true});

  @override
  State<TracePad> createState() => _TracePadState();
}

class _TracePadState extends State<TracePad> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        widget.controller.size = Size(c.maxWidth, c.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: cs.surfaceContainerHighest,
            child: GestureDetector(
              onPanStart: (d) {
                widget.controller.strokes.add([d.localPosition]);
                setState(() {});
              },
              onPanUpdate: (d) {
                widget.controller.strokes.last.add(d.localPosition);
                setState(() {});
              },
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _TracePainter(
                  glyph: widget.glyph,
                  strokes: widget.controller.strokes,
                  showGuide: widget.showGuide,
                  guideColor: cs.onSurface.withValues(alpha: 0.13),
                  gridColor: cs.outlineVariant,
                  inkColor: cs.primary,
                  repaint: widget.controller,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _TracePainter extends CustomPainter {
  final String glyph;
  final List<List<Offset>> strokes;
  final bool showGuide;
  final Color guideColor, gridColor, inkColor;
  _TracePainter({
    required this.glyph,
    required this.strokes,
    required this.showGuide,
    required this.guideColor,
    required this.gridColor,
    required this.inkColor,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grille « tianzige » (carré découpé en 4) pour aider à placer le trait.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    for (var i = 0; i < 20; i++) {
      final t = i / 20;
      if (i.isEven) {
        canvas.drawLine(Offset(w / 2, t * h), Offset(w / 2, (t + 0.025) * h), grid);
        canvas.drawLine(Offset(t * w, h / 2), Offset((t + 0.025) * w, h / 2), grid);
      }
    }
    if (showGuide) {
      final tp = _painter(glyph, size.shortestSide, guideColor);
      tp.paint(canvas,
          Offset((w - tp.width) / 2, (h - tp.height) / 2));
    }
    final ink = Paint()
      ..color = inkColor
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 9, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => true;
}
