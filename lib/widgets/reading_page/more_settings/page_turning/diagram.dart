import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/theme/morandi_palette.dart';
import 'package:flutter/material.dart';

enum PageTurningType {
  none,
  next,
  prev,
  menu,
}

Widget getPageTurningDiagram(
  BuildContext context,
  List<PageTurningType> types,
  List<int> iconPosition,
  bool selected,
  Function() onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 100,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? ClaudePalette.accent(context)
              : ClaudePalette.divider(context),
          width: 1,
        ),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        itemBuilder: (context, index) {
          return Container(
            color: types[index] == PageTurningType.next
                ? MorandiPalette.error(context).withValues(alpha: 0.4)
                : types[index] == PageTurningType.prev
                    ? MorandiPalette.info(context).withValues(alpha: 0.4)
                    : types[index] == PageTurningType.menu
                        ? MorandiPalette.success(context).withValues(alpha: 0.4)
                        : types[index] == PageTurningType.none
                            ? ClaudePalette.divider(context)
                            : ClaudePalette.card(context),
            child: Center(
              child: iconPosition.contains(index)
                  ? Icon(
                      index == iconPosition[0]
                          ? Icons.arrow_forward
                          : index == iconPosition[1]
                              ? Icons.arrow_back
                              : index == iconPosition[2]
                                  ? Icons.menu
                                  : null,
                      size: 10,
                    )
                  : null,
            ),
          );
        },
        itemCount: 9,
      ),
    ),
  );
}
