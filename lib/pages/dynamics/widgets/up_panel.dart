import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/live_follow/view.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class UpPanel extends StatefulWidget {
  const UpPanel({
    super.key,
    required this.upData,
    required this.dynamicsController,
  });

  final FollowUpModel upData;
  final DynamicsController dynamicsController;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;
  final _liveToggleKey = GlobalKey();
  late final Worker _selectionWorker;
  late List<int> _visibleMids;

  @override
  void initState() {
    super.initState();
    _visibleMids = controller.visibleUpList.map((item) => item.mid).toList();
    _selectionWorker = ever(controller.selectedUpMid, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedUp());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedUp());
  }

  @override
  void didUpdateWidget(covariant UpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mids = controller.visibleUpList.map((item) => item.mid).toList();
    if (!listEquals(_visibleMids, mids)) {
      _visibleMids = mids;
      if (controller.currentMid != -1) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _revealSelectedUp(),
        );
      }
    }
  }

  @override
  void dispose() {
    _selectionWorker.dispose();
    super.dispose();
  }

  void _revealSelectedUp() {
    if (!mounted || !controller.scrollController.hasClients) return;
    final mid = controller.currentMid;
    final index = mid == -1
        ? 0
        : controller.visibleUpList.indexWhere((item) => item.mid == mid) + 1;
    if (mid != -1 && index == 0) return;
    final toggle =
        _liveToggleKey.currentContext?.findRenderObject() as RenderBox?;
    if (toggle == null || !toggle.hasSize) return;
    final liveCount = controller.showLiveUp
        ? widget.upData.liveUsers?.items?.length ?? 0
        : 0;
    final itemExtent = isTop ? 70.0 : 76.0;
    final start =
        (isTop ? toggle.size.width : toggle.size.height) +
        (liveCount + index) * itemExtent;
    final position = controller.scrollController.position;
    final end = start + itemExtent;
    final double target;
    if (start < position.pixels) {
      target = start;
    } else if (end > position.pixels + position.viewportDimension) {
      target = end - position.viewportDimension;
    } else {
      return;
    }
    controller.scrollController.animateTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void toFollowPage() => Get.to(const LiveFollowPage());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upData = widget.upData;
    final upList = controller.visibleUpList;
    final liveList = upData.liveUsers?.items;
    return CustomScrollView(
      scrollDirection: isTop ? .horizontal : .vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: InkWell(
            key: _liveToggleKey,
            onTap: () => setState(() {
              controller.showLiveUp = !controller.showLiveUp;
            }),
            onLongPress: toFollowPage,
            onSecondaryTap: PlatformUtils.isMobile ? null : toFollowPage,
            child: Container(
              alignment: .center,
              height: isTop ? 76 : 60,
              padding: isTop ? const .only(left: 12, right: 6) : null,
              child: Text.rich(
                textAlign: .center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Live(${upData.liveUsers?.count ?? 0})',
                    ),
                    if (!isTop) ...[
                      const TextSpan(text: '\n'),
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ] else
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_left,
                          color: theme.colorScheme.primary,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (controller.showLiveUp && liveList != null && liveList.isNotEmpty)
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, liveList[index]);
            },
          ),
        SliverToBoxAdapter(
          child: upItemBuild(theme, UpItem(face: '', uname: '全部动态', mid: -1)),
        ),
        if (upList.isNotEmpty)
          SliverList.builder(
            itemCount: upList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, upList[index]);
            },
          ),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem item) {
    item.hasUpdate = false;
    controller.onSelectUp(item.mid);
    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem item) => Obx(
    () => _buildUpItem(theme, item, controller.currentMid),
  );

  Widget _buildUpItem(ThemeData theme, UpItem item, int currentMid) {
    final isLive = item is LiveUserItem;
    final isCurrent = isLive || currentMid == item.mid || currentMid == -1;

    final isAll = item.mid == -1;
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');

    Widget avatar;
    if (isAll) {
      avatar = DecoratedBox(
        decoration: const BoxDecoration(
          shape: .circle,
          color: Color(0xFF5CB67B),
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          color: Colors.white,
        ),
      );
    } else {
      avatar = Padding(
        padding: const .symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: item.face,
          type: .avatar,
        ),
      );
      if (isLive) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: isLive && !isTop ? -5 : 0,
              right: -6,
              child: Badge(
                label: const Text(' Live '),
                textColor: theme.colorScheme.onSecondaryContainer,
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.75),
              ),
            ),
          ],
        );
      } else if (item.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      height: 76,
      width: isTop ? 70 : null,
      child: InkWell(
        onTap: () {
          feedBack();
          if (isLive) {
            PageUtils.toLiveRoom(item.roomId);
          } else {
            _onSelect(item);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll ? toMemberPage : null,
        onSecondaryTap: !isAll && !PlatformUtils.isMobile ? toMemberPage : null,
        child: Opacity(
          opacity: isCurrent ? 1 : 0.6,
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              avatar,
              Padding(
                padding: const .symmetric(horizontal: 4),
                child: Text(
                  isTop ? '${item.uname}\n' : item.uname!,
                  maxLines: 2,
                  textAlign: .center,
                  style: TextStyle(
                    color: currentMid == item.mid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    height: 1.1,
                    fontSize: 12.5,
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
