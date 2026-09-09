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
  @override
  Widget build(BuildContext context) {
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
        onDragEnd: (_) {},
        child: DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != i,
          onAcceptWithDetails: (details) {
            widget.onReorder(details.data, i);
          },
          builder: (context, candidateData, rejectedData) {
            final hasCandidate = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: hasCandidate
                  ? BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    )
                  : null,
              child: tileContent,
            );
          },
        ),
      );

      if (original is StaggeredGridTile) {
        if (original.mainAxisExtent != null) {
          return StaggeredGridTile.extent(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisExtent: original.mainAxisExtent!,
            child: draggable,
          );
        }
        if (original.mainAxisCellCount != null) {
          return StaggeredGridTile.count(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisCellCount: original.mainAxisCellCount!,
            child: draggable,
          );
        }
        return StaggeredGridTile.fit(
          crossAxisCellCount: original.crossAxisCellCount,
          child: draggable,
        );
      }

      return StaggeredGridTile.fit(
        crossAxisCellCount: 1,
        child: draggable,
      );
    });

    return StaggeredGrid.count(
      crossAxisCount: widget.crossAxisCount,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      children: children,
    );
  }

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
    final resizeHandle = onResizeDelta == null
        ? null
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onResizeDelta!(details.delta),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.open_in_full,
                color: Colors.white,
                size: 16,
              ),
            ),
          );

    return Stack(
      children: [
        // Place the content as a non-positioned child so the Stack can size
        // itself based on the child's intrinsic dimensions. Using
        // Positioned.fill here caused unbounded constraints when the widget
        // was used inside an Overlay (drag feedback), producing a RenderBox
        // with missing size.
        child,
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.drag_handle, color: Colors.white, size: 16),
          ),
        ),
        if (resizeHandle != null)
          Positioned(
            bottom: 6,
            right: 6,
            child: resizeHandle,
          ),
      ],
    );
  }
}
