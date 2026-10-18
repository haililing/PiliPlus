import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Real neighboring feed pages, each with its own data and vertical scroller.
class UpSwipeArea extends StatefulWidget {
  const UpSwipeArea({
    super.key,
    required this.enabled,
    required this.controller,
  });

  final bool enabled;
  final DynamicsController controller;

  @override
  State<UpSwipeArea> createState() => _UpSwipeAreaState();
}

class _UpSwipeAreaState extends State<UpSwipeArea>
    with AutomaticKeepAliveClientMixin {
  late List<int> _mids;
  late final PageController _pages;
  late final Worker _selectionWorker;
  late final Worker _sourceWorker;
  bool _updatingFromPage = false;
  bool _syncingList = false;
  int? _targetMid;
  int _moveVersion = 0;

  @override
  bool get wantKeepAlive => true;

  List<int> _sourceMids() => [
    -1,
    ...widget.controller.visibleUpList.map((item) => item.mid),
  ];

  @override
  void initState() {
    super.initState();
    _mids = _sourceMids();
    final index = _mids.indexOf(widget.controller.currentMid);
    _pages = PageController(
      initialPage: index < 0 ? 0 : index,
      keepPage: false,
    );
    _selectionWorker = ever(widget.controller.selectedUpMid, (_) {
      if (!_updatingFromPage && !_syncingList) _moveToSelection();
    });
    _sourceWorker = ever(widget.controller.loadingState, (state) {
      if (state.isSuccess) _updateMids();
    });
  }

  @override
  void didUpdateWidget(covariant UpSwipeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToSelection(animate: false);
      });
    }
  }

  @override
  void dispose() {
    _moveVersion++;
    _selectionWorker.dispose();
    _sourceWorker.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _updateMids() {
    final next = _sourceMids();
    if (listEquals(_mids, next)) return;
    final selectedMid = widget.controller.currentMid;
    final nextIndex = next.indexOf(selectedMid);
    final needsAlignment = nextIndex != _mids.indexOf(selectedMid);
    if (needsAlignment) {
      _syncingList = true;
      _targetMid = null;
      _moveVersion++;
    }
    setState(() => _mids = next);
    if (nextIndex < 0) {
      _updatingFromPage = true;
      widget.controller.onUpPageChanged(-1);
      _updatingFromPage = false;
    }
    if (needsAlignment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _moveToSelection(animate: false);
        _syncingList = false;
      });
    }
  }

  Future<void> _moveToSelection({bool animate = true}) async {
    final version = ++_moveVersion;
    final mid = widget.controller.currentMid;
    final index = _mids.indexOf(mid);
    if (index < 0) return;
    if (!_pages.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && version == _moveVersion) {
          _moveToSelection(animate: false);
        }
      });
      return;
    }
    final distance = ((_pages.page ?? index.toDouble()) - index).abs();
    if (distance < 0.001) {
      _targetMid = mid;
      _pages.jumpToPage(index);
      _targetMid = null;
      return;
    }
    _targetMid = mid;
    // Distant avatar taps should not fetch every intermediate creator's feed.
    if (animate && widget.enabled && distance <= 1) {
      await _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(index);
    }
    if (mounted && version == _moveVersion) {
      _targetMid = null;
      _loadMoreNearEnd(index);
    }
  }

  void _onPageChanged(int index) {
    if (!widget.enabled ||
        _syncingList ||
        _targetMid != null ||
        index < 0 ||
        index >= _mids.length) {
      return;
    }
    _updatingFromPage = true;
    widget.controller.onUpPageChanged(_mids[index]);
    _updatingFromPage = false;
    _loadMoreNearEnd(index);
  }

  void _loadMoreNearEnd(int index) {
    if (widget.enabled &&
        index >= _mids.length - 2 &&
        widget.controller.loadingState.value.isSuccess &&
        !widget.controller.isLoading) {
      widget.controller.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.horizontal &&
            notification.dragDetails != null) {
          _moveVersion++;
          _targetMid = null;
          _onPageChanged((_pages.page ?? 0).round());
        }
        return false;
      },
      child: PageView.builder(
        controller: _pages,
        physics: widget.enabled
            ? tabBarScrollPhysics
            : const NeverScrollableScrollPhysics(),
        horizontalDragGestureRecognizer:
            CustomHorizontalDragGestureRecognizer.new,
        // Lay out and fetch one real neighboring page on either side.
        allowImplicitScrolling: true,
        onPageChanged: _onPageChanged,
        itemCount: _mids.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<int>) return null;
          final index = _mids.indexOf(key.value);
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          final mid = _mids[index];
          return DynamicsTabPage(
            key: ValueKey<int>(mid),
            dynamicsType: mid == -1 ? DynamicsTabType.all : DynamicsTabType.up,
            hostMid: mid == -1 ? null : mid,
          );
        },
      ),
    );
  }
}
