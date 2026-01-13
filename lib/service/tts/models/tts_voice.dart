class TtsVoice {
  /// Unique identifier or short name used for API calls
  final String shortName;

  /// Display name primarily for user interface
  final String name;

  /// Locale code (e.g., en-US)
  final String locale;

  /// Gender (Male, Female, or other/unknown)
  final String gender;

  /// Optional raw data for extra properties
  final Map<String, dynamic>? rawData;

  const TtsVoice({
    required this.shortName,
    required this.name,
    required this.locale,
    this.gender = '',
    this.rawData,
  });

  factory TtsVoice.fromMap(Map<String, dynamic> map) {
    return TtsVoice(
      shortName: map['ShortName'] ?? '',
      name: map['FriendlyName'] ?? map['Name'] ?? map['ShortName'] ?? '',
      locale: map['Locale'] ?? map['locale'] ?? '',
      gender: map['Gender'] ?? '',
      rawData: map,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ShortName': shortName,
      'FriendlyName': name,
      'Locale': locale,
      'Gender': gender,
      ...rawData ?? {},
    };
  }
}
