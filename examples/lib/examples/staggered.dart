import 'package:examples/common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class StaggeredPage extends StatefulWidget {
  const StaggeredPage({Key? key}) : super(key: key);

  @override
  _StaggeredPageState createState() => _StaggeredPageState();
}

class _StaggeredPageState extends State<StaggeredPage> {
  final List<Map<String, dynamic>> items = [
    {'id': 0, 'cross': 2, 'main': 2},
    {'id': 1, 'cross': 2, 'main': 1},
    {'id': 2, 'cross': 1, 'main': 1},
    {'id': 3, 'cross': 1, 'main': 1},
    {'id': 4, 'cross': 4, 'main': 2},
  ];

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);
    });
  }

  void _onResize(int index, int newCross, num? newMain) {
    setState(() {
      items[index]['cross'] = newCross;
      if (newMain != null) items[index]['main'] = newMain;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Staggered (reorderable)',
      child: SingleChildScrollView(
        child: ReorderableStaggeredGrid(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          onReorder: _onReorder,
          onResize: _onResize,
          children: items
              .map((it) => StaggeredGridTile.count(
                    crossAxisCellCount: it['cross'] as int,
                    mainAxisCellCount: it['main'] as num,
                    child: Tile(index: it['id'] as int),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
