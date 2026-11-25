import 'package:flutter/widgets.dart';

/// Google's four-colour "G", for "Continue with Google". The same shapes as the website's
/// "Login with Google" button (frontend/src/App.tsx, an SVG on a 48 × 48 grid), drawn here directly so
/// it stays sharp at any size without an image file or an SVG package.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Google',
      child: CustomPaint(size: Size.square(size), painter: const _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()..isAntiAlias = true;

    // M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5.1h6.6c3.9-3.6 6.1-8.9 6.1-15z
    final blue = Path()
      ..moveTo(43.6, 24.5)
      ..relativeCubicTo(0, -1.4, -0.1, -2.8, -0.4, -4.1)
      ..lineTo(24, 20.4)
      ..relativeLineTo(0, 7.8)
      ..relativeLineTo(11, 0)
      ..relativeArcToPoint(const Offset(-4.1, 6.2), radius: const Radius.circular(9.4), clockwise: true)
      ..relativeLineTo(0, 5.1)
      ..relativeLineTo(6.6, 0)
      ..relativeCubicTo(3.9, -3.6, 6.1, -8.9, 6.1, -15)
      ..close();

    // M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.6-5.1c-1.8 1.2-4.1 2-6.9 2-5.3 0-9.8-3.6-11.5-8.4H5.7v5.2A20 20 0 0 0 24 44z
    final green = Path()
      ..moveTo(24, 44)
      ..relativeCubicTo(5.5, 0, 10.1, -1.8, 13.5, -4.9)
      ..relativeLineTo(-6.6, -5.1)
      ..relativeCubicTo(-1.8, 1.2, -4.1, 2, -6.9, 2)
      ..relativeCubicTo(-5.3, 0, -9.8, -3.6, -11.5, -8.4)
      ..lineTo(5.7, 27.6)
      ..relativeLineTo(0, 5.2)
      ..arcToPoint(const Offset(24, 44), radius: const Radius.circular(20), clockwise: false)
      ..close();

    // M12.5 27.6a12 12 0 0 1 0-7.2v-5.2H5.7a20 20 0 0 0 0 17.6l6.8-5.2z
    final yellow = Path()
      ..moveTo(12.5, 27.6)
      ..relativeArcToPoint(const Offset(0, -7.2), radius: const Radius.circular(12), clockwise: true)
      ..relativeLineTo(0, -5.2)
      ..lineTo(5.7, 15.2)
      ..relativeArcToPoint(const Offset(0, 17.6), radius: const Radius.circular(20), clockwise: false)
      ..relativeLineTo(6.8, -5.2)
      ..close();

    // M24 12c3 0 5.7 1 7.9 3.1l5.9-5.9C34.2 5.9 29.6 4 24 4A20 20 0 0 0 5.7 15.2l6.8 5.2C14.2 15.6 18.7 12 24 12z
    final red = Path()
      ..moveTo(24, 12)
      ..relativeCubicTo(3, 0, 5.7, 1, 7.9, 3.1)
      ..relativeLineTo(5.9, -5.9)
      ..cubicTo(34.2, 5.9, 29.6, 4, 24, 4)
      ..arcToPoint(const Offset(5.7, 15.2), radius: const Radius.circular(20), clockwise: false)
      ..relativeLineTo(6.8, 5.2)
      ..cubicTo(14.2, 15.6, 18.7, 12, 24, 12)
      ..close();

    canvas
      ..drawPath(blue, paint..color = _blue)
      ..drawPath(green, paint..color = _green)
      ..drawPath(yellow, paint..color = _yellow)
      ..drawPath(red, paint..color = _red);
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
