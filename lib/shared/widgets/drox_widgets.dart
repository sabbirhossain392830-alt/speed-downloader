import 'package:flutter/material.dart';

class DroxAnimatedSwitch extends StatelessWidget {
  const DroxAnimatedSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = dark ? const Color(0xFF4FC3F7) : const Color(0xFF6B351B);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: 54,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? activeColor : (dark ? const Color(0xFF555555) : const Color(0xFFD8D8D8)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: value ? Colors.white : (dark ? const Color(0xFFBDBDBD) : Colors.white),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .20), blurRadius: 3, offset: const Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DroxLogoMark extends StatelessWidget {
  const DroxLogoMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFF7F6F3),
      borderRadius: BorderRadius.circular(size * .27),
      border: Border.all(color: const Color(0xFFE8E5E0)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: size * .20, offset: const Offset(0, 3)),
      ],
    ),
    child: CustomPaint(painter: _DroxWingPainter(), size: Size(size, size)),
  );
}

class _DroxWingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    final orange = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9DA5AA), Color(0xFFD0D2D1), Color(0xFFC47A50), Color(0xFF858D93)],
      ).createShader(const Rect.fromLTWH(0, 0, 44, 44))
      ..style = PaintingStyle.fill;
    final upper = Path()
      ..moveTo(9, 28)
      ..cubicTo(8, 27, 8, 25, 10, 23)
      ..lineTo(31, 5)
      ..cubicTo(33, 3, 37, 4, 36, 7)
      ..lineTo(17, 30)
      ..cubicTo(15, 33, 12, 32, 9, 28)
      ..close();
    final lower = Path()
      ..moveTo(16, 31)
      ..cubicTo(17, 29, 18, 27, 20, 25)
      ..lineTo(33, 14)
      ..cubicTo(36, 12, 39, 14, 36, 17)
      ..lineTo(27, 26)
      ..cubicTo(25, 28, 26, 30, 28, 32)
      ..lineTo(39, 39)
      ..cubicTo(40, 40, 39, 42, 36, 42)
      ..lineTo(25, 41)
      ..cubicTo(22, 41, 20, 39, 18, 37)
      ..lineTo(11, 32)
      ..cubicTo(10, 31, 13, 29, 16, 31)
      ..close();
    canvas.drawPath(upper, orange);
    canvas.drawPath(lower, orange);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DroxDownloadProgress extends StatelessWidget {
  const DroxDownloadProgress({super.key, required this.progress, required this.isDark});
  final double progress;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? Colors.white : Colors.black;
    return ClipRect(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _DroxDownloadStripePainter(
            progress: progress.clamp(0.0, 1.0),
            stripeColor: ink,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

class _DroxDownloadStripePainter extends CustomPainter {
  const _DroxDownloadStripePainter({
    required this.progress,
    required this.stripeColor,
    required this.isDark,
  });

  final double progress;
  final Color stripeColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // A very subtle track keeps the row clean without looking like a thick bar.
    final track = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .025 : .018);
    canvas.drawRect(Offset.zero & size, track);

    final filledWidth = size.width * progress;
    if (filledWidth <= 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, filledWidth, size.height));

    final fill = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .055 : .035);
    canvas.drawRect(Rect.fromLTWH(0, 0, filledWidth, size.height), fill);

    // Static, fine pinstripes: only the progress boundary moves as bytes download.
    final stripe = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .48 : .42);
    const stripeWidth = 1.0;
    const spacing = 38.0;
    for (double x = 0; x < filledWidth; x += spacing) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripeWidth, size.height), stripe);
    }

    final edge = Paint()
      ..color = stripeColor.withValues(alpha: isDark ? .72 : .62);
    canvas.drawRect(
      Rect.fromLTWH((filledWidth - 1).clamp(0.0, size.width), 0, 1, size.height),
      edge,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DroxDownloadStripePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.stripeColor != stripeColor ||
      oldDelegate.isDark != isDark;
}

