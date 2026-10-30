import 'package:flutter/material.dart';

import 'temperature_models.dart';

/// Andamento delle ultime rilevazioni con la fascia dei limiti.
/// [readings] in ordine cronologico crescente.
class TempChart extends StatelessWidget {
  const TempChart({super.key, required this.readings, required this.minC, required this.maxC});

  final List<TempReading> readings;
  final double? minC;
  final double? maxC;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (readings.length < 2) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('Servono almeno due rilevazioni per il grafico.')),
      );
    }
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(
          readings: readings,
          minC: minC,
          maxC: maxC,
          line: cs.primary,
          band: cs.primary.withAlpha(30),
          bad: cs.error,
          text: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.readings,
    required this.minC,
    required this.maxC,
    required this.line,
    required this.band,
    required this.bad,
    required this.text,
  });

  final List<TempReading> readings;
  final double? minC;
  final double? maxC;
  final Color line;
  final Color band;
  final Color bad;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 8.0, top = 8.0, bottom = 8.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;

    final values = readings.map((r) => r.valueC).toList();
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (minC != null && minC! < lo) lo = minC!;
    if (maxC != null && maxC! > hi) hi = maxC!;
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;

    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));
    double x(int i) => left + w * (i / (readings.length - 1));

    // Fascia dei limiti
    final bandTop = y(maxC ?? hi);
    final bandBottom = y(minC ?? lo);
    canvas.drawRect(
        Rect.fromLTRB(left, bandTop, left + w, bandBottom), Paint()..color = band);

    // Etichette asse Y
    void label(double v) {
      final tp = TextPainter(
        text: TextSpan(
            text: v.toStringAsFixed(1).replaceAll('.', ','),
            style: TextStyle(fontSize: 11, color: text)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 6, y(v) - tp.height / 2));
    }

    label(hi - pad);
    label(lo + pad);

    // Linea
    final path = Path();
    for (var i = 0; i < readings.length; i++) {
      final p = Offset(x(i), y(readings[i].valueC));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Punti (rossi se fuori range)
    for (var i = 0; i < readings.length; i++) {
      canvas.drawCircle(Offset(x(i), y(readings[i].valueC)), 4,
          Paint()..color = readings[i].outOfRange ? bad : line);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.readings != readings || old.minC != minC || old.maxC != maxC;
}
