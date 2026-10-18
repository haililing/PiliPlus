import 'dart:ui' show FontFeature;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/common_btn.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Single-row controls for the embedded player on a portrait phone screen.
/// Fullscreen players continue to use the standard bottom controls.
class PortraitBottomControl extends StatelessWidget {
  const PortraitBottomControl({
    super.key,
    required this.controller,
    required this.progressBar,
  });

  final PlPlayerController controller;
  final Widget progressBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: 40,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              PlayOrPauseButton(
                plPlayerController: controller,
                iconSize: 32,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: progressBar,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.36,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Obx(
                    () => Text(
                      '${DurationUtils.formatDuration(controller.progress)}/'
                      '${DurationUtils.formatDuration(controller.duration.value)}',
                      maxLines: 1,
                      softWrap: false,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ComBtn(
                width: 40,
                height: 40,
                tooltip: '全屏',
                onTap: () => controller.triggerFullScreen(status: true),
                icon: const Center(
                  child: CustomPaint(
                    size: Size(24, 24),
                    painter: _PortraitFullscreenIcon(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two rounded, opposite corners matching the portrait control reference.
class _PortraitFullscreenIcon extends CustomPainter {
  const _PortraitFullscreenIcon();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.45, size.height * 0.12)
      ..lineTo(size.width * 0.20, size.height * 0.12)
      ..quadraticBezierTo(
        size.width * 0.12,
        size.height * 0.12,
        size.width * 0.12,
        size.height * 0.20,
      )
      ..lineTo(size.width * 0.12, size.height * 0.45)
      ..moveTo(size.width * 0.55, size.height * 0.88)
      ..lineTo(size.width * 0.80, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.88,
        size.width * 0.88,
        size.height * 0.80,
      )
      ..lineTo(size.width * 0.88, size.height * 0.55);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PortraitFullscreenIcon oldDelegate) => false;
}
