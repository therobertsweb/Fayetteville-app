import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps forms and prose readable while letting their scroll views fill height.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 840});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Variable-height cards wrap without clipping headlines or enlarged text.
class ArticleColumns extends StatelessWidget {
  const ArticleColumns({
    super.key,
    required this.children,
    this.maxColumns = 3,
    this.minWidth = 340,
  });
  final List<Widget> children;
  final int maxColumns;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cardMinWidth = minWidth * MediaQuery.textScalerOf(context).scale(1);
      final columns = (constraints.maxWidth / cardMinWidth).floor().clamp(
        1,
        maxColumns,
      );
      return _ArticleRows(
        columns: columns,
        direction: Directionality.of(context),
        children: children,
      );
    },
  );
}

class _ArticleRows extends MultiChildRenderObjectWidget {
  const _ArticleRows({
    required this.columns,
    required this.direction,
    required super.children,
  });

  final int columns;
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArticleRows(columns, direction);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderArticleRows renderObject,
  ) {
    renderObject
      ..columns = columns
      ..direction = direction
      ..markNeedsLayout();
  }
}

class _ArticleParentData extends ContainerBoxParentData<RenderBox> {}

/// Tiles can hide themselves after loading author details. A zero-height tile
/// must not consume a column, even though it received a fixed width.
class _RenderArticleRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ArticleParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ArticleParentData> {
  _RenderArticleRows(this.columns, this.direction);
  int columns;
  TextDirection direction;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ArticleParentData) {
      child.parentData = _ArticleParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cardWidth = (width - 16 * (columns - 1)) / columns;
    var column = 0;
    var top = 0.0;
    var rowHeight = 0.0;
    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ArticleParentData;
      child.layout(
        BoxConstraints.tightFor(width: cardWidth),
        parentUsesSize: true,
      );
      data.offset = Offset.zero;
      if (child.size.height > 0) {
        if (column == columns) {
          top += rowHeight;
          rowHeight = 0;
          column = 0;
        }
        final left = column * (cardWidth + 16);
        data.offset = Offset(
          direction == TextDirection.ltr ? left : width - cardWidth - left,
          top,
        );
        if (child.size.height > rowHeight) rowHeight = child.size.height;
        column++;
      }
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(width, top + rowHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
