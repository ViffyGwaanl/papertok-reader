/// Configuration item type enumeration.
/// Defines the UI component type for a configuration field.
enum ConfigItemType {
  text('text input'),
  password('password input'),
  number('number input'),
  select('select'),
  radio('radio'),
  checkbox('checkbox'),
  toggle('toggle'),
  tip('tip');

  const ConfigItemType(this.label);
  final String label;
}

/// Configuration item model.
/// Represents a single configurable field for a service provider.
class ConfigItem {
  final String key;
  final String label;
  final String? description;
  final ConfigItemType type;
  final dynamic defaultValue;
  final List<Map<String, dynamic>>? options;
  final String? link;

  ConfigItem({
    required this.key,
    required this.label,
    this.description,
    required this.type,
    this.defaultValue,
    this.options,
    this.link,
  });

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'description': description,
      'type': type.name,
      'defaultValue': defaultValue,
      'options': options,
      'link': link,
    };
  }
}
