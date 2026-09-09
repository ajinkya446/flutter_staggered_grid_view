import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid_tile.dart';

/// A helper that provides drag-and-drop reordering and optional resize callbacks
/// for staggered grid children. Dragging is implemented with LongPressDraggable
/// and DragTarget; the StaggeredGridTile remains the ParentDataWidget so layout
/// behavior is preserved.
class ReorderableStaggeredGrid extends StatefulWidget {
  const ReorderableStaggeredGrid({
    Key? key,
    required this.children,
    required this.onReorder,
    this.onResize,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 4.0,
    this.crossAxisSpacing = 4.0,
  }) : super(key: key);

  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index, int crossAxisCellCount, num? mainAxisCellCount)?
      onResize;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  _ReorderableStaggeredGridState createState() => _ReorderableStaggeredGridState();
}

class _ReorderableStaggeredGridState extends State<ReorderableStaggeredGrid> {
  int? _draggingIndex;

  @override
  Widget build(BuildContext context) {
    final children = List<Widget>.generate(widget.children.length, (i) {
      final original = widget.children[i];

      Widget buildDraggableInner(Widget inner) {
        return LongPressDraggable<int>(
          data: i,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 6,
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width / widget.crossAxisCount * (original is StaggeredGridTile ? original.crossAxisCellCount.toDouble() : 1)),
                child: inner,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.0, child: inner),
          onDragStarted: () => setState(() => _draggingIndex = i),
          onDraggableCanceled: (_, __) => setState(() => _draggingIndex = null),
          onDragEnd: (_) => setState(() => _draggingIndex = null),
          child: inner,
        );
      }

      Widget tileWithDragTarget(Widget tileWidget) {
        return DragTarget<int>(
          onWillAccept: (from) => from != null && from != i,
          onAccept: (from) {
            // Reorder so that dragged item is inserted at the position of this tile
            widget.onReorder(from, i);
            setState(() => _draggingIndex = null);
          },
          builder: (context, candidateData, rejectedData) {
            final hasCandidate = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: hasCandidate
                  ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3))
                  : null,
              child: tileWidget,
            );
          },
        );
      }

      // If original is a StaggeredGridTile, recreate it and make its inner child draggable.
      if (original is StaggeredGridTile) {
        final inner = original.child;

        Widget draggableInner = buildDraggableInner(_ControlWrapper(
          index: i,
          child: inner,
          onIncreaseWidth: widget.onResize == null
              ? null
              : () {
                  final tile = _extractTile(original);
                  final newCross = (tile?.crossAxisCellCount ?? 1) + 1;
                  widget.onResize!(i, newCross, tile?.mainAxisCellCount);
                },
          onDecreaseWidth: widget.onResize == null
              ? null
              : () {
                  final tile = _extractTile(original);
                  final newCross = (tile?.crossAxisCellCount ?? 1) - 1;
                  widget.onResize!(i, newCross < 1 ? 1 : newCross, tile?.mainAxisCellCount);
                },
        ));

        final recreated = (original.mainAxisExtent != null)
            ? StaggeredGridTile.extent(
                crossAxisCellCount: original.crossAxisCellCount,
                mainAxisExtent: original.mainAxisExtent!,
                child: draggableInner,
              )
            : (original.mainAxisCellCount != null)
                ? StaggeredGridTile.count(
                    crossAxisCellCount: original.crossAxisCellCount,
                    mainAxisCellCount: original.mainAxisCellCount!,
                    child: draggableInner,
                  )
                : StaggeredGridTile.fit(
                    crossAxisCellCount: original.crossAxisCellCount,
                    child: draggableInner,
                  );

        return tileWithDragTarget(recreated);
      }

      // For non-tile widgets, just wrap them with draggable + drag target.
      final nonTileChild = buildDraggableInner(_ControlWrapper(
        index: i,
        child: original,
        onIncreaseWidth: widget.onResize == null
            ? null
            : () {
                final tile = _extractTile(original);
                final newCross = (tile?.crossAxisCellCount ?? 1) + 1;
                widget.onResize!(i, newCross, tile?.mainAxisCellCount);
              },
        onDecreaseWidth: widget.onResize == null
            ? null
            : () {
                final tile = _extractTile(original);
                final newCross = (tile?.crossAxisCellCount ?? 1) - 1;
                widget.onResize!(i, newCross < 1 ? 1 : newCross, tile?.mainAxisCellCount);
              },
      ));

      return tileWithDragTarget(nonTileChild);
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
    required this.index,
    required this.child,
    this.onMoveUp,
    this.onMoveDown,
    this.onIncreaseWidth,
    this.onDecreaseWidth,
  }) : super(key: key);

  final int index;
  final Widget child;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onIncreaseWidth;
  final VoidCallback? onDecreaseWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 4,
          top: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.drag_handle, color: Colors.white, size: 16),
              ),
              const SizedBox(height: 6),
              if (onIncreaseWidth != null)
                _IconButtonSmall(icon: Icons.add, onPressed: onIncreaseWidth!),
              if (onDecreaseWidth != null)
                _IconButtonSmall(icon: Icons.remove, onPressed: onDecreaseWidth!),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconButtonSmall extends StatelessWidget {
  const _IconButtonSmall({Key? key, required this.icon, required this.onPressed})
      : super(key: key);

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
