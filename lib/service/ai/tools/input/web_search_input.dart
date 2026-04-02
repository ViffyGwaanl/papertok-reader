class WebSearchInput {
  const WebSearchInput({
    required this.query,
    this.maxResults = 5,
  });

  final String query;
  final int maxResults;

  factory WebSearchInput.fromJson(Map<String, dynamic> json) {
    return WebSearchInput(
      query: json['query'] as String,
      maxResults: (json['maxResults'] as int?) ?? 5,
    );
  }
}
