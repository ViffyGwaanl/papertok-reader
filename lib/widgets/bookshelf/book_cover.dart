import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:flutter/material.dart';

class BookCover extends StatefulWidget {
  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.radius,
  });

  final Book book;
  final double? height;
  final double? width;
  final double? radius;

  @override
  State<BookCover> createState() => _BookCoverState();
}

Widget bookCover(
  BuildContext context,
  Book book, {
  double? height,
  double? width,
  double? radius,
}) {
  return BookCover(
    book: book,
    height: height,
    width: width,
    radius: radius,
  );
}

class _BookCoverState extends State<BookCover> {
  ImageProvider? _imageProvider;
  bool _hasCover = false;
  late String _coverPath;

  @override
  void initState() {
    super.initState();
    _coverPath = widget.book.coverFullPath;
    _prepareImageProvider();
  }

  @override
  void didUpdateWidget(covariant BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPath = widget.book.coverFullPath;
    if (newPath != _coverPath) {
      _coverPath = newPath;
      _prepareImageProvider();
    }
  }

  void _prepareImageProvider() {
    final file = File(_coverPath);
    if (file.existsSync()) {
      _imageProvider = FileImage(file);
      _hasCover = true;
    } else {
      _imageProvider = null;
      _hasCover = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double effectiveRadius = widget.radius ?? 8;
    final BorderRadius borderRadius = BorderRadius.circular(effectiveRadius);

    Widget child;
    if (_hasCover && _imageProvider != null) {
      child = Image(
        image: _imageProvider!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
      );
    } else {
      child = Container(
        color: Colors
            .primaries[widget.book.title.hashCode % Colors.primaries.length]
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
      side: const BorderSide(
        width: 0.3,
        color: Colors.grey,
      ),
    );

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: widget.width,
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
