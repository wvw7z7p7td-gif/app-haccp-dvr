import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Raccoglie i tratti della firma ed esporta un PNG (nero su bianco).
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  /// Vuota anche se c'e' solo un tocco: serve un tratto vero.
  bool get isEmpty => !_strokes.any((s) => s.length > 2);

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _add(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _paint(Canvas canvas, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in _strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.25, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  Future<Uint8List?> toPng() async {
    if (isEmpty || _size.isEmpty) return null;
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _paint(canvas, Colors.black);
    final image = await recorder
        .endRecording()
        .toImage((_size.width * scale).round(), (_size.height * scale).round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 160});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        controller._size = Size(box.maxWidth, height);
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            // Il riconoscitore "eager" impedisce alla lista di scorrere mentre si firma.
            child: RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                  (_) {},
                ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => controller._start(e.localPosition),
                onPointerMove: (e) => controller._add(e.localPosition),
                child: Stack(children: [
                  CustomPaint(painter: _SigPainter(controller), size: Size.infinite),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (_, __) => controller._strokes.isEmpty
                        ? const Center(
                            child: Text('Firma qui', style: TextStyle(color: Colors.black38)))
                        : const SizedBox.shrink(),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: controller.clear,
          icon: const Icon(Icons.refresh),
          label: const Text('Cancella firma'),
        ),
      ),
    ]);
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.controller) : super(repaint: controller);
  final SignatureController controller;

  @override
  void paint(Canvas canvas, Size size) => controller._paint(canvas, Colors.black);

  @override
  bool shouldRepaint(covariant _SigPainter old) => false;
}
