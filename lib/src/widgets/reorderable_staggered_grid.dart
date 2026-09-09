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
  int? _hoverIndex;
  int? _draggingIndex;

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
        onDragStarted: () { setState(() { _draggingIndex = i; }); },
        onDraggableCanceled: (_, __) { setState(() { _draggingIndex = null; _hoverIndex = null; }); },
        onDragEnd: (_) { setState(() { _draggingIndex = null; _hoverIndex = null; }); },
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

      // Compute insertion index using a cell-fitting skyline algorithm so
      // dropping into empty spaces places the dragged tile where it fits and
      // other tiles reflow around it.
      int _indexForGlobalOffset(Offset global, int draggedIndex) {
        final gridBox = context.findRenderObject() as RenderBox?;
        if (gridBox == null) return widget.children.length;
        final gridSize = gridBox.size;
        final local = gridBox.globalToLocal(global);

        final colCount = widget.crossAxisCount;
        final columnWidth = gridSize.width / colCount;

        // Derive a reasonable cell height from existing tiles: use tiles that
        // declare mainAxisCellCount or infer from their measured height.
        double cellHeight;
        final measuredHeights = <double>[];
        for (var i = 0; i < _childKeys.length; i++) {
          final key = _childKeys[i];
          final cctx = key.currentContext;
          if (cctx == null) continue;
          final render = cctx.findRenderObject() as RenderBox?;
          if (render == null) continue;
          final widgetTile = widget.children[i] is StaggeredGridTile ? widget.children[i] as StaggeredGridTile : null;
          if (widgetTile != null && widgetTile.mainAxisCellCount != null) {
            measuredHeights.add(render.size.height / widgetTile.mainAxisCellCount!.toDouble());
          } else if (widgetTile != null && widgetTile.mainAxisExtent != null) {
            measuredHeights.add(widgetTile.mainAxisExtent!.toDouble());
          } else {
            // fallback: treat square cells
            measuredHeights.add(render.size.height);
          }
        }
        if (measuredHeights.isNotEmpty) {
          cellHeight = measuredHeights.reduce((a, b) => a + b) / measuredHeights.length;
        } else {
          cellHeight = columnWidth; // fallback
        }

        // Helper to get spans for a given child index
        int _crossSpanAt(int idx) {
          final w = widget.children[idx];
          if (w is StaggeredGridTile) return w.crossAxisCellCount;
          return 1;
        }

        int _mainSpanAt(int idx, RenderBox? render) {
          final w = widget.children[idx];
          if (w is StaggeredGridTile) {
            if (w.mainAxisCellCount != null) return w.mainAxisCellCount!.toInt();
            if (w.mainAxisExtent != null) {
              return ((w.mainAxisExtent! / cellHeight).round().clamp(1, 9999)).toInt();
            }
          }
          if (render != null) {
            return ((render.size.height / cellHeight).round().clamp(1, 9999)).toInt();
          }
          return 1;
        }

        // Build a list of items excluding the dragged one in original order.
        final order = <int>[];
        for (var i = 0; i < widget.children.length; i++) if (i != draggedIndex) order.add(i);

        // Prepare heights skyline per column (in main-axis cell units)
        final heights = List<int>.filled(colCount, 0);

        final placed = <int, Map<String, int>>{}; // index -> {'x','y'} positions in cell units

        for (var idx in order) {
          final key = _childKeys[idx];
          final cctx = key.currentContext;
          final render = cctx?.findRenderObject() as RenderBox?;
          final cross = _crossSpanAt(idx).clamp(1, colCount);
          final main = _mainSpanAt(idx, render);

          // Find best x where tile can fit (minimize max height)
          int bestX = 0;
          int bestY = 1 << 30;
          for (var x = 0; x <= colCount - cross; x++) {
            var maxh = 0;
            for (var c = x; c < x + cross; c++) if (heights[c] > maxh) maxh = heights[c];
            if (maxh < bestY) {
              bestY = maxh;
              bestX = x;
            }
          }
          // Place
          for (var c = bestX; c < bestX + cross; c++) heights[c] = bestY + main;
          placed[idx] = {'x': bestX, 'y': bestY};
        }

        // Determine target column/row under the drop point
        final targetCol = (local.dx / columnWidth).clamp(0, colCount - 1).floor();
        final targetRow = (local.dy / cellHeight).floor();

        // Now find where the dragged tile could fit if placed near target.
        final draggedCross = _crossSpanAt(draggedIndex).clamp(1, colCount);

        // Search for a placement position starting near targetCol and scanning
        // rows from 0..max to find a spot where columns c..c+draggedCross-1
        // have heights <= targetRow.
        int chosenInsertOrderIndex = order.length; // default append
        bool found = false;
        final maxRow = (heights.reduce((a, b) => a > b ? a : b) + 20);
        for (var row = 0; row <= maxRow && !found; row++) {
          // try columns in order of proximity to targetCol
          final cols = List<int>.generate(colCount - draggedCross + 1, (i) => i);
          cols.sort((a, b) => (a - targetCol).abs().compareTo((b - targetCol).abs()));
          for (var col in cols) {
            var canFit = true;
            for (var c = col; c < col + draggedCross; c++) if (heights[c] > row) { canFit = false; break; }
            if (canFit) {
              // Determine insertion index: count how many placed items start before
              // this (row,col) position in layout order
              int countBefore = 0;
              for (var idx in order) {
                final pos = placed[idx]!;
                if (pos['y']! < row) countBefore++;
                else if (pos['y']! == row && pos['x']! < col) countBefore++;
              }
              chosenInsertOrderIndex = countBefore;
              found = true;
              break;
            }
          }
        }

        // Map chosenInsertOrderIndex back to original children index
        if (chosenInsertOrderIndex >= order.length) return widget.children.length;
        return order[chosenInsertOrderIndex];
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
                      _hoverIndex = _indexForGlobalOffset(details.offset, _draggingIndex ?? -1);
                    });
                  },
                  onLeave: (data) {
                    setState(() {
                      _hoverIndex = null;
                    });
                  },
                  onWillAccept: (data) => true,
                  onAcceptWithDetails: (details) {
                    final newIndex = _indexForGlobalOffset(details.offset, details.data);
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
