import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Time, a full-width seek bar and the action row for mobile landscape playback.
class LandscapeBottomControl extends StatelessWidget {
  const LandscapeBottomControl({
    super.key,
    required this.controller,
    required this.progressBar,
    required this.controls,
  });

  final PlPlayerController controller;
  final Widget progressBar;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(
            () => Text(
              '${DurationUtils.formatDuration(controller.progress)}/'
              '${DurationUtils.formatDuration(controller.duration.value)}',
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 18),
          progressBar,
          const SizedBox(height: 10),
          controls,
        ],
      ),
    );
  }
}
