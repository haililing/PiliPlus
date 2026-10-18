import 'package:material_ui/material_ui.dart';

/// Horizontal swipes select adjacent creators instead of changing feed tabs.
class UpSwipeArea extends StatefulWidget {
  const UpSwipeArea({
    super.key,
    required this.onSwipe,
    required this.child,
  });

  final ValueChanged<int> onSwipe;
  final Widget child;

  @override
  State<UpSwipeArea> createState() => _UpSwipeAreaState();
}

class _UpSwipeAreaState extends State<UpSwipeArea> {
  double _dragDistance = 0;

  void _onDragEnd(DragEndDetails details) {
    final distance = _dragDistance;
    final velocity = details.velocity.pixelsPerSecond.dx;
    _dragDistance = 0;
    if (distance.abs() < 48 && (distance.abs() < 12 || velocity.abs() < 500)) {
      return;
    }
    final direction = distance.abs() >= 48 ? distance : velocity;
    widget.onSwipe(direction < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) =>
          _dragDistance += details.primaryDelta ?? 0,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => _dragDistance = 0,
      child: widget.child,
    );
  }
}
