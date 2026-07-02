import 'package:flutter/material.dart';

class FaceOverlay extends StatelessWidget {
  final Color color;
  const FaceOverlay({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _OvalPainter(color)),
    );
  }
}

class _OvalPainter extends CustomPainter {
  final Color color;
  _OvalPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final ovalWidth = size.width * 0.65;
    final ovalHeight = ovalWidth * 1.3;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: ovalWidth,
      height: ovalHeight,
    );

    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(rect);
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), dim);

    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(rect, border);
  }

  @override
  bool shouldRepaint(_OvalPainter old) => old.color != color;
}
