import 'package:flutter/material.dart';

abstract class AbstractSettingsTile extends StatelessWidget {
  const AbstractSettingsTile({super.key});
}

enum SettingsTileType { simpleTile, switchTile, navigationTile }

class SettingsTile extends AbstractSettingsTile {
  SettingsTile({
    this.leading,
    this.trailing,
    this.value,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    onToggle = null;
    initialValue = null;
    activeSwitchColor = null;
    tileType = SettingsTileType.simpleTile;
  }

  SettingsTile.navigation({
    this.leading,
    this.trailing,
    this.value,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    onToggle = null;
    initialValue = null;
    activeSwitchColor = null;
    tileType = SettingsTileType.navigationTile;
  }

  SettingsTile.switchTile({
    required this.initialValue,
    required this.onToggle,
    this.activeSwitchColor,
    this.leading,
    this.trailing,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    value = null;
    tileType = SettingsTileType.switchTile;
  }

  /// The widget at the beginning of the tile
  final Widget? leading;

  /// The Widget at the end of the tile
  final Widget? trailing;

  /// The widget at the center of the tile
  final Widget title;

  /// The widget at the bottom of the [title]
  final Widget? description;

  /// A function that is called by tap on a tile
  final Function(BuildContext context)? onPressed;

  late final Color? activeSwitchColor;
  late final Widget? value;
  late final Function(bool value)? onToggle;
  late final SettingsTileType tileType;
  late final bool? initialValue;
  late final bool enabled;

  @override
  Widget build(BuildContext context) {
    final subtitle = value ?? description;

    switch (tileType) {
      case SettingsTileType.switchTile:
        final v = initialValue ?? false;
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle,
          enabled: enabled,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 8),
              ],
              Switch.adaptive(
                value: v,
                onChanged: enabled ? onToggle : null,
                activeColor: activeSwitchColor,
              ),
            ],
          ),
          onTap: enabled ? () => onToggle?.call(!v) : null,
        );

      case SettingsTileType.navigationTile:
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle,
          enabled: enabled,
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: enabled ? () => onPressed?.call(context) : null,
        );

      case SettingsTileType.simpleTile:
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle,
          enabled: enabled,
          trailing: trailing,
          onTap: enabled ? () => onPressed?.call(context) : null,
        );
    }
  }
}

class CustomSettingsTile extends AbstractSettingsTile {
  const CustomSettingsTile({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
