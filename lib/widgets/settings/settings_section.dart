import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

abstract class AbstractSettingsSection extends StatelessWidget {
  const AbstractSettingsSection({super.key});
}

class SettingsSection extends AbstractSettingsSection {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.margin,
    this.title,
  });

  final List<AbstractSettingsTile> tiles;
  final EdgeInsetsDirectional? margin;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return buildSectionBody(context);
  }

  Widget buildSectionBody(BuildContext context) {
    final theme = Theme.of(context);
    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: buildTileChildren(context),
      ),
    );

    return Padding(
      padding: margin ??
          const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8, top: 8),
              child: DefaultTextStyle(
                style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ) ??
                    const TextStyle(),
                child: Builder(
                  builder: (_) {
                    final t = title!;
                    if (t is Text && t.data != null) {
                      return Text(t.data!.toUpperCase());
                    }
                    return t;
                  },
                ),
              ),
            ),
          card,
        ],
      ),
    );
  }

  List<Widget> buildTileChildren(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i != tiles.length - 1) {
        children.add(Divider(
          height: 1,
          thickness: 0.5,
          color: Theme.of(context).dividerColor,
          indent: 16,
        ));
      }
    }
    return children;
  }

}

class CustomSettingsSection extends AbstractSettingsSection {
  const CustomSettingsSection({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
