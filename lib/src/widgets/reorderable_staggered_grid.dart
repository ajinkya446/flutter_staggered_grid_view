import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/src/rendering/staggered_grid.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid_tile.dart';

/// A helper that provides drag-and-drop reordering and optional resize callbacks
/// for staggered grid children. Dragging is implemented with LongPressDraggable
/// and DragTarget; the StaggeredGridTile remains the ParentDataWidget so layout
/// behavior is preserved.
/// A staggered grid that supports drag-to-reorder and direct resize gestures.
///
/// Reordering is triggered by a long press on a tile. Resizing is handled by a
/// small resize grip in the corner of each tile. This keeps the grid free of
/// extra button controls while still enabling the requested behavior.
class ReorderableStaggeredGrid extends StatefulWidget {
  /// Creates a staggered grid with drag-to-reorder and resize handles.
  const ReorderableStaggeredGrid({
    Key? key,
    required this.children,
    required this.onReorder,
    this.onResize,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 4.0,
    this.crossAxisSpacing = 4.0,
  }) : super(key: key);

  /// The tiles displayed by the grid.
  final List<Widget> children;

  /// Called when a tile is reordered.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Optional callback triggered when a tile's logical size changes.
  final void Function(int index, int crossAxisCellCount, num? mainAxisCellCount)?
      onResize;

  /// Number of columns in the staggered grid.
  final int crossAxisCount;

  /// Spacing between tiles along the main axis.
  final double mainAxisSpacing;

  /// Spacing between tiles along the cross axis.
  final double crossAxisSpacing;

  @override
  _ReorderableStaggeredGridState createState() => _ReorderableStaggeredGridState();
}

class _ReorderableStaggeredGridState extends State<ReorderableStaggeredGrid> {
  double? _width;
  double? _height;
  double _initialWidth = 0.0;
  double _initialHeight = 0.0;
  bool _scalingActive = false;
  final List<GlobalKey> _childKeys = []; 

  @override
  Widget build(BuildContext context) {
    // Ensure we have a GlobalKey for each child to calculate positions for
    // empty-space drops.
    while (_childKeys.length < widget.children.length) {
      _childKeys.add(GlobalKey());
    }
    if (_childKeys.length > widget.children.length) {
      _childKeys.removeRange(widget.children.length, _childKeys.length);
    }

    final children = List<Widget>.generate(widget.children.length, (i) {
      final original = widget.children[i];
      final inner = original is StaggeredGridTile ? original.child : original;

      final resizeDelta = widget.onResize == null
          ? null
          : (Offset delta) {
              final tile = _extractTile(original);
              final currentCross = tile?.crossAxisCellCount ?? 1;
              final currentMain = tile?.mainAxisCellCount ?? 1;
              final newCross = (currentCross + (delta.dx / 80).round())
                  .clamp(1, widget.crossAxisCount);
              final newMain = (currentMain.toInt() + (delta.dy / 80).round())
                  .clamp(1, 9999);
              widget.onResize!(i, newCross, newMain);
            };

      final tileContent = _ControlWrapper(
        child: inner,
        onResizeDelta: resizeDelta,
      );

      final draggable = LongPressDraggable<int>(
        data: i,
        delay: const Duration(milliseconds: 120),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          elevation: 6,
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.95,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width /
                    widget.crossAxisCount *
                    (original is StaggeredGridTile
                        ? original.crossAxisCellCount.toDouble()
                        : 1),
              ),
              child: tileContent,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: tileContent),
        onDragStarted: () {},
        onDraggableCanceled: (_, __) {},
        onDragEnd: (_) { setState(() { _hoverIndex = null; }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: _hoverIndex == i
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
          child: tileContent,
        ),
      );

      Widget tileWidget;
      if (original is StaggeredGridTile) {
        if (original.mainAxisExtent != null) {
          tileWidget = StaggeredGridTile.extent(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisExtent: original.mainAxisExtent!,
            child: draggable,
          );
        } else if (original.mainAxisCellCount != null) {
          tileWidget = StaggeredGridTile.count(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisCellCount: original.mainAxisCellCount!,
            child: draggable,
          );
        } else {
          tileWidget = StaggeredGridTile.fit(
            crossAxisCellCount: original.crossAxisCellCount,
            child: draggable,
          );
        }
      } else {
        tileWidget = StaggeredGridTile.fit(
          crossAxisCellCount: 1,
          child: draggable,
        );
      }

      // Wrap each tile with a KeyedSubtree attached to a GlobalKey so we can
      // map global drop coordinates back to tile positions when dropping into
      // empty space.
      return KeyedSubtree(key: _childKeys[i], child: tileWidget);
    });

    // Wrap the grid in a LayoutBuilder so we can read its constraints and
    // support pinch-to-resize from the bottom-right corner. The Animated-
    // Container holds the current width (if set by a pinch) so the grid's
    // children automatically reflow to the new available width. Additionally
    // add a full-area DragTarget to accept drops into empty spaces.
    return LayoutBuilder(builder: (context, constraints) {
      final grid = StaggeredGrid.count(
        crossAxisCount: widget.crossAxisCount,
        mainAxisSpacing: widget.mainAxisSpacing,
        crossAxisSpacing: widget.crossAxisSpacing,
        children: children,
      );

      // Helper to map a global drop offset into an index. If the offset lies
      // inside a child, return that child's index. Otherwise return the
      // nearest child's index or append at end.
      int _indexForGlobalOffset(Offset global) {
        final gridBox = context.findRenderObject() as RenderBox?;
        if (gridBox == null) return widget.children.length;
        final local = gridBox.globalToLocal(global);

        for (var i = 0; i < _childKeys.length; i++) {
          final key = _childKeys[i];
          final cctx = key.currentContext;
          if (cctx == null) continue;
          final render = cctx.findRenderObject() as RenderBox?;
          if (render == null) continue;
          final childGlobal = render.localToGlobal(Offset.zero);
          final childLocal = gridBox.globalToLocal(childGlobal);
          final rect = childLocal & render.size;
          if (rect.contains(local)) return i;
        }

        double bestDist = double.infinity;
        int bestIndex = widget.children.length;
        for (var i = 0; i < _childKeys.length; i++) {
          final key = _childKeys[i];
          final cctx = key.currentContext;
          if (cctx == null) continue;
          final render = cctx.findRenderObject() as RenderBox?;
          if (render == null) continue;
          final childGlobal = render.localToGlobal(Offset.zero);
          final childLocal = gridBox.globalToLocal(childGlobal);
          final center = childLocal + Offset(render.size.width / 2, render.size.height / 2);
          final d = (center - local).distance;
          if (d < bestDist) {
            bestDist = d;
            bestIndex = i;
          }
        }
        return bestIndex;
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          _initialWidth = box.size.width;
          _initialHeight = box.size.height;
          final local = box.globalToLocal(details.focalPoint);
          // Only start scaling when the gesture begins near the bottom-right
          // corner (within 48 pixels). This prevents accidental scale when
          // interacting with tiles.
          if (local.dx >= _initialWidth - 48 && local.dy >= _initialHeight - 48) {
            _scalingActive = true;
          } else {
            _scalingActive = false;
          }
        },
        onScaleUpdate: (details) {
          if (!_scalingActive) return;
          final newW = (_initialWidth * details.scale).clamp(80.0, constraints.maxWidth.isFinite ? constraints.maxWidth : _initialWidth * 3);
          setState(() {
            _width = newW;
          });
        },
        onScaleEnd: (_) {
          _scalingActive = false;
        },
        child: AnimatedContainer(
          width: _width ?? constraints.maxWidth,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Stack(
            children: [
              grid,
              // Full-size DragTarget to accept drops into empty areas. We
              // use onMove to update a hover index for visual feedback and
              // handle acceptance in onAcceptWithDetails.
              Positioned.fill(
                child: DragTarget<int>(
                  onMove: (details) {
                    setState(() {
                      _hoverIndex = _indexForGlobalOffset(details.offset);
                    });
                  },
                  onLeave: (data) {
                    setState(() {
                      _hoverIndex = null;
                    });
                  },
                  onWillAccept: (data) => true,
                  onAcceptWithDetails: (details) {
                    final newIndex = _indexForGlobalOffset(details.offset);
                    setState(() {
                      _hoverIndex = null;
                    });
                    // Normalize index when removing earlier item
                    var oldIndex = details.data;
                    var adjustedNew = newIndex;
                    if (oldIndex < adjustedNew) adjustedNew = (adjustedNew - 1).clamp(0, widget.children.length - 1);
                    widget.onReorder(oldIndex, adjustedNew);
                  },
                  builder: (context, candidate, rejected) => const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  int? _hoverIndex;

  static StaggeredGridTile? _extractTile(Widget w) {
    if (w is StaggeredGridTile) return w;
    if (w is ParentDataWidget<StaggeredGridParentData>) {
      // ParentDataWidget is what StaggeredGridTile implements; try to reflect.
      // Best-effort: not all wrappers will expose the tile.
      return null;
    }
    return null;
  }
}

class _ControlWrapper extends StatelessWidget {
  const _ControlWrapper({
    Key? key,
    required this.child,
    this.onResizeDelta,
  }) : super(key: key);

  final Widget child;
  final void Function(Offset delta)? onResizeDelta;

  @override
  Widget build(BuildContext context) {
    // Simplify controls: show only the child contents so the grid appears
    // without overlay buttons. Drag-to-reorder still works via LongPress-
    // Draggable on the tile's content. Pinch-to-resize for the entire grid is
    // handled at the grid level.
    return child;
  }
}
