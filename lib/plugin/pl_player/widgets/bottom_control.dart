import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/landscape_bottom_control.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/portrait_bottom_control.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({
    super.key,
    required this.maxWidth,
    required this.isFullScreen,
    this.usePortraitLayout = false,
    this.useLandscapeLayout = false,
    required this.controller,
    required this.buildBottomControl,
    required this.videoDetailController,
  });

  final double maxWidth;
  final bool isFullScreen;
  final bool usePortraitLayout;
  final bool useLandscapeLayout;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;
  final VideoDetailController videoDetailController;

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onSeekStart(duration.seconds);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    if (!controller.isFileSource && controller.showSeekPreview) {
      controller.updatePreviewIndex(duration.seconds);
    }
    controller.seekPosition.value = duration.seconds;
  }

  void onSeek(int milliseconds) {
    controller
      ..position.value = milliseconds ~/ 1000
      ..onSeekEnd()
      ..seekTo(Duration(milliseconds: milliseconds), isSeek: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = usePortraitLayout || useLandscapeLayout
        ? Colors.white
        : colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = useLandscapeLayout
        ? const Color(0x73FFFFFF)
        : usePortraitLayout
        ? const Color(0xD9FFFFFF)
        : primary.withValues(alpha: 0.4);

    final progressBar = _buildProgressBar(
      primary,
      thumbGlowColor,
      bufferedBarColor,
    );
    if (usePortraitLayout) {
      return PortraitBottomControl(
        controller: controller,
        progressBar: progressBar,
      );
    }
    if (useLandscapeLayout) {
      return LandscapeBottomControl(
        controller: controller,
        progressBar: progressBar,
        controls: buildBottomControl(),
      );
    }

    return Padding(
      padding: const .symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: progressBar,
          ),
          buildBottomControl(),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    Color primary,
    Color thumbGlowColor,
    Color bufferedBarColor,
  ) {
    final compactBar = usePortraitLayout || useLandscapeLayout;
    return Obx(
      () => Offstage(
        offstage: !controller.showControls.value,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Obx(
              () => ProgressBar(
                progress: controller.progress,
                buffered: controller.buffered.value,
                total: controller.duration.value,
                progressBarColor: primary,
                baseBarColor: usePortraitLayout
                    ? const Color(0xB3FFFFFF)
                    : const Color(0x33FFFFFF),
                bufferedBarColor: bufferedBarColor,
                thumbColor: primary,
                thumbGlowColor: thumbGlowColor,
                barHeight: compactBar ? 3 : 3.5,
                thumbRadius: compactBar ? 6 : 7,
                thumbGlowRadius: 25,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onSeek: onSeek,
              ),
            ),
            if (controller.enableBlock &&
                videoDetailController.segmentProgressList.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: compactBar ? 4.5 : 5.25,
                child: SegmentProgressBar(
                  segments: videoDetailController.segmentProgressList,
                ),
              ),
            if (controller.showViewPoints &&
                videoDetailController.viewPointList.isNotEmpty &&
                videoDetailController.showVP.value)
              Padding(
                padding: EdgeInsets.only(
                  bottom: compactBar ? 7.5 : 8.75,
                ),
                child: ViewPointSegmentProgressBar(
                  segments: videoDetailController.viewPointList,
                  onSeek: PlatformUtils.isDesktop
                      ? (position) => controller.seekTo(position, isSeek: false)
                      : null,
                ),
              ),
            if (videoDetailController.showDmTrendChart.value)
              if (videoDetailController.dmTrend.value?.dataOrNull
                  case final list?)
                buildDmChart(
                  primary,
                  list,
                  videoDetailController,
                  compactBar ? 3.25 : 4.5,
                ),
          ],
        ),
      ),
    );
  }
}
