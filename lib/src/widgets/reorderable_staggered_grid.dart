import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid.dart';
import 'package:flutter_staggered_grid_view/src/widgets/staggered_grid_tile.dart';

/// A simple helper that provides programmatic reorder/resize controls for
/// staggered grid children. This is intentionally lightweight: it exposes
/// onReorder and onResize callbacks so the parent can update the underlying
/// data and rebuild the grid.
class ReorderableStaggeredGrid extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Wrap each child with simple controls for move up / move down and resize.
    // If the provided child is a StaggeredGridTile, recreate it and wrap its
    // inner child so the ParentDataWidget remains the direct child of the
    // StaggeredGrid (this preserves layout behavior).
    final wrapped = List<Widget>.generate(children.length, (i) {
      final original = children[i];

      // Build control overlay to be placed inside the tile's child.
      Widget buildWithOverlay(Widget inner) {
        return _ControlWrapper(
          index: i,
          child: inner,
          onMoveUp: i > 0 ? () => onReorder(i, i - 1) : null,
          onMoveDown: i < children.length - 1 ? () => onReorder(i, i + 1) : null,
          onIncreaseWidth: onResize == null
              ? null
              : () {
                  final tile = _extractTile(original);
                  final newCross = (tile?.crossAxisCellCount ?? 1) + 1;
                  onResize!(i, newCross, tile?.mainAxisCellCount);
                },
          onDecreaseWidth: onResize == null
              ? null
              : () {
                  final tile = _extractTile(original);
                  final newCross = (tile?.crossAxisCellCount ?? 1) - 1;
                  onResize!(i, newCross < 1 ? 1 : newCross, tile?.mainAxisCellCount);
                },
        );
      }

      if (original is StaggeredGridTile) {
        // Recreate the tile with the inner child wrapped by the controls.
        final inner = original.child;
        if (original.mainAxisExtent != null) {
          return StaggeredGridTile.extent(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisExtent: original.mainAxisExtent!,
            child: buildWithOverlay(inner),
          );
        } else if (original.mainAxisCellCount != null) {
          return StaggeredGridTile.count(
            crossAxisCellCount: original.crossAxisCellCount,
            mainAxisCellCount: original.mainAxisCellCount!,
            child: buildWithOverlay(inner),
          );
        } else {
          return StaggeredGridTile.fit(
            crossAxisCellCount: original.crossAxisCellCount,
            child: buildWithOverlay(inner),
          );
        }
      }

      // If it's not a StaggeredGridTile, just wrap the widget directly.
      return buildWithOverlay(original);
    });

    // Use StaggeredGrid.count so callers can still use StaggeredGridTile children.
    return StaggeredGrid.count(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      children: wrapped,
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
              if (onMoveUp != null)
                _IconButtonSmall(icon: Icons.arrow_upward, onPressed: onMoveUp!),
              if (onMoveDown != null)
                _IconButtonSmall(icon: Icons.arrow_downward, onPressed: onMoveDown!),
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
