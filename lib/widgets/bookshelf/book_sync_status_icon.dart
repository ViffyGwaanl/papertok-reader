import 'package:papertok_reader/enums/book_sync_status.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/widgets/bookshelf/spining_sync_icon.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class BookSyncStatusIcon extends StatelessWidget {
  const BookSyncStatusIcon({
    super.key,
    required this.syncStatus,
    this.iconSize = 16,
  });

  final BookSyncStatusEnum syncStatus;
  final double iconSize;

  /// Morandi-adaptive color for a given sync status. Requires a
  /// [BuildContext] so light/dark variants resolve correctly.
  static Color colorFor(BuildContext context, BookSyncStatusEnum status) {
    switch (status) {
      case BookSyncStatusEnum.localOnly:
        return MorandiPalette.warning(context);
      case BookSyncStatusEnum.remoteOnly:
        return MorandiPalette.warmGray(context);
      case BookSyncStatusEnum.both:
        return MorandiPalette.success(context);
      case BookSyncStatusEnum.nonExistent:
        return MorandiPalette.error(context);
      case BookSyncStatusEnum.downloading:
        return MorandiPalette.info(context);
      case BookSyncStatusEnum.uploading:
        return MorandiPalette.info(context);
      case BookSyncStatusEnum.checking:
        return MorandiPalette.warmGray(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, syncStatus);
    Widget child = switch (syncStatus) {
      BookSyncStatusEnum.localOnly => Stack(
          children: [
            Center(
              child: Icon(
                Bootstrap.cloud,
                color: color,
                size: iconSize,
              ),
            ),
            Center(
              child: Icon(
                Bootstrap.x,
                color: color,
                size: iconSize * 0.7,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.remoteOnly => Stack(
          children: [
            Center(
              child: Icon(
                Bootstrap.cloud,
                color: color,
                size: iconSize,
              ),
            ),
            Center(
              child: Icon(
                Icons.sync,
                color: color,
                size: iconSize * 0.5,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.both => Icon(
          Bootstrap.cloud_check,
          color: color,
          size: iconSize,
        ),
      BookSyncStatusEnum.nonExistent => Icon(
          OctIcons.x_circle,
          color: color,
          size: iconSize * 0.8,
        ),
      BookSyncStatusEnum.downloading => Stack(
          children: [
            Center(
              child: SpiningSyncIcon(
                size: iconSize,
                color: color,
              ),
            ),
            Center(
              child: Icon(
                Bootstrap.arrow_down_short,
                color: color,
                size: iconSize * 0.7,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.uploading => Stack(
          children: [
            Center(
              child: SpiningSyncIcon(
                size: iconSize,
                color: color,
              ),
            ),
            Center(
              child: Icon(
                Bootstrap.arrow_up_short,
                color: color,
                size: iconSize * 0.7,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.checking => const CircularProgressIndicator.adaptive(
          strokeWidth: 2,
        ),
    };
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
}
