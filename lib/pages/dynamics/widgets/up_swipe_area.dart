import 'package:material_ui/material_ui.dart';

/// Animates one live feed so outgoing and incoming views never share a scroller.
class UpSwipeArea extends StatefulWidget {
  const UpSwipeArea({
    super.key,
    required this.enabled,
    required this.prepareSwipe,
    required this.onSelectUp,
    required this.selectionRevision,
    required this.child,
  });

  final bool enabled;
  final Future<int?> Function(int direction) prepareSwipe;
  final ValueChanged<int> onSelectUp;
  final ValueGetter<int> selectionRevision;
  final Widget child;

  @override
  State<UpSwipeArea> createState() => _UpSwipeAreaState();
}

class _UpSwipeAreaState extends State<UpSwipeArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController(
    vsync: this,
    value: 0,
    lowerBound: -1,
    upperBound: 1,
  );
  double _dragDistance = 0;
  double _width = 1;
  bool _switching = false;
  int _transition = 0;

  @override
  void didUpdateWidget(covariant UpSwipeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _transition++;
      _offset
        ..stop()
        ..value = 0;
      _dragDistance = 0;
      _switching = false;
    }
  }

  @override
  void dispose() {
    _transition++;
    _offset.dispose();
    super.dispose();
  }

  bool _isActive(int transition) =>
      mounted && widget.enabled && transition == _transition;

  Future<void> _settle(double target, int milliseconds) => _offset
      .animateTo(
        target,
        duration: Duration(milliseconds: milliseconds),
        curve: Curves.easeOutCubic,
      )
      .orCancel;

  void _onDragStart(DragStartDetails details) {
    if (_switching) return;
    _offset.stop();
    _dragDistance = _offset.value * _width;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_switching) return;
    _dragDistance += details.primaryDelta ?? 0;
    _offset.value = (_dragDistance / _width).clamp(-0.45, 0.45);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_switching || !widget.enabled) return;
    final distance = _dragDistance;
    final velocity = details.velocity.pixelsPerSecond.dx;
    _dragDistance = 0;
    final transition = ++_transition;
    final revision = widget.selectionRevision();
    _switching = true;
    try {
      if (distance.abs() < 48 &&
          (distance.abs() < 12 || velocity.abs() < 500)) {
        await _settle(0, 180);
        return;
      }
      final movement = distance.abs() >= 48 ? distance : velocity;
      final direction = movement < 0 ? 1 : -1;
      final mid = await widget.prepareSwipe(direction);
      if (!_isActive(transition)) return;
      if (mid == null || revision != widget.selectionRevision()) {
        await _settle(0, 180);
        return;
      }

      await _settle(direction == 1 ? -1 : 1, 160);
      if (!_isActive(transition)) return;
      if (revision != widget.selectionRevision()) {
        await _settle(0, 180);
        return;
      }
      widget.onSelectUp(mid);
      // Let the selected feed rebuild before animating it into view.
      await WidgetsBinding.instance.endOfFrame;
      if (!_isActive(transition)) return;
      _offset.value = direction == 1 ? 1 : -1;
      await _settle(0, 240);
    } on TickerCanceled {
      // Tab changes and disposal cancel any pending gesture animation.
    } finally {
      if (_isActive(transition)) _switching = false;
    }
  }

  void _onDragCancel() {
    if (_switching) return;
    _dragDistance = 0;
    _onDragEnd(DragEndDetails());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: widget.enabled ? _onDragStart : null,
          onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
          onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
          onHorizontalDragCancel: widget.enabled ? _onDragCancel : null,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) => FractionalTranslation(
                translation: Offset(_offset.value, 0),
                child: Opacity(
                  opacity: 1 - _offset.value.abs(),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
