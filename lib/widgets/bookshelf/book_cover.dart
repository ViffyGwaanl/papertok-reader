import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:flutter/material.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.radius,
    this.showBorder = true,
  });

  final Book book;
  final double? height;
  final double? width;
  final double? radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final double effectiveRadius = radius ?? 8;
    final BorderRadius borderRadius = BorderRadius.circular(effectiveRadius);
    final file = File(book.coverFullPath);
    final hasCover = file.existsSync();

    Widget child;
    if (hasCover) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      child = Container(
        color: Colors
            .primaries[book.title.hashCode % Colors.primaries.length]
            .shade200,
        child: Center(
          child: Icon(
            Icons.book,
            size: 40,
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    }

    final RoundedSuperellipseBorder borderShape = RoundedSuperellipseBorder(
      borderRadius: borderRadius,
      side: showBorder
          ? BorderSide(
              width: 0.3,
              color: Theme.of(context).dividerColor,
            )
          : BorderSide.none,
    );

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: width,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: borderShape,
          ),
          child: ClipRSuperellipse(
            borderRadius: borderRadius,
            child: child,
          ),
        ),
      ),
    );
  }
}
