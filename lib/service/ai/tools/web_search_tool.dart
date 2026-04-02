import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/input/web_search_input.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

import 'base_tool.dart';

/// Web search tool with dual strategy:
/// 1. If a Serper API key is configured, uses Serper.dev JSON API.
/// 2. Otherwise falls back to DuckDuckGo Lite HTML parsing (no key needed).
class WebSearchTool extends RepositoryTool<WebSearchInput, Map<String, dynamic>> {
  WebSearchTool()
      : super(
          name: 'web_search',
          description:
              'Search the web for information. Returns a list of search results '
              'with title, URL, and snippet. Use for finding recent information, '
              'academic references, or answering factual questions.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description':
                    'Required. The search query string.',
              },
              'maxResults': {
                'type': 'integer',
                'description':
                    'Optional. Maximum results to return (1-10). Default 5.',
              },
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 20),
        );

  static const _userAgent = 'PaperReader/1.0 (+MCP/tools)';

  @override
  WebSearchInput parseInput(Map<String, dynamic> json) =>
      WebSearchInput.fromJson(json);

  @override
  Future<Map<String, dynamic>> run(WebSearchInput input) async {
    final query = input.query.trim();
    if (query.isEmpty) {
      return {'status': 'error', 'message': 'Empty search query'};
    }

    final maxResults = input.maxResults.clamp(1, 10);

    try {
      final serperKey = _getSerperApiKey();
      final results = serperKey != null
          ? await _serperSearch(query, maxResults, serperKey)
          : await _ddgSearch(query, maxResults);

      return {
        'query': query,
        'resultCount': results.length,
        'results': results,
      };
    } catch (e) {
      AnxLog.warning('WebSearchTool: search failed: $e');
      return {
        'status': 'error',
        'message': 'Search failed: $e',
      };
    }
  }

  String? _getSerperApiKey() {
    try {
      final config = Prefs().getAiConfig(Prefs().selectedAiService);
      return config['webSearchApiKey']?.trim();
    } catch (_) {
      return null;
    }
  }

  /// Serper.dev Google Search API (requires API key).
  Future<List<Map<String, dynamic>>> _serperSearch(
    String query,
    int maxResults,
    String apiKey,
  ) async {
    final response = await http.post(
      Uri.parse('https://google.serper.dev/search'),
      headers: {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'q': query,
        'num': maxResults,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Serper API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final organic = data['organic'] as List<dynamic>? ?? [];

    return organic.take(maxResults).map((item) {
      final m = item as Map<String, dynamic>;
      return <String, dynamic>{
        'title': m['title'] ?? '',
        'url': m['link'] ?? '',
        'snippet': m['snippet'] ?? '',
        'position': m['position'] ?? 0,
      };
    }).toList(growable: false);
  }

  /// DuckDuckGo Lite HTML scraping fallback (no API key needed).
  Future<List<Map<String, dynamic>>> _ddgSearch(
    String query,
    int maxResults,
  ) async {
    final uri = Uri.https('lite.duckduckgo.com', '/lite/', {'q': query});
    final response = await http.get(uri, headers: {
      'User-Agent': _userAgent,
      'Accept': 'text/html',
    });

    if (response.statusCode != 200) {
      throw Exception('DuckDuckGo error: ${response.statusCode}');
    }

    return _parseDdgLiteHtml(response.body, maxResults);
  }

  /// Parses DuckDuckGo Lite HTML to extract search results.
  ///
  /// DDG Lite uses a table-based layout:
  /// - Result links are in <a class="result-link"> or <a> inside <td>
  /// - Snippets are in <td class="result-snippet">
  List<Map<String, dynamic>> _parseDdgLiteHtml(String html, int maxResults) {
    final results = <Map<String, dynamic>>[];

    // Extract result links: <a rel="nofollow" href="...">title</a>
    final linkPattern = RegExp(
      r'<a\s+rel="nofollow"\s+href="([^"]+)"[^>]*>\s*(.*?)\s*</a>',
      caseSensitive: false,
      dotAll: true,
    );
    // Extract snippets: <td class="result-snippet">...</td>
    final snippetPattern = RegExp(
      r'<td\s+class="result-snippet"[^>]*>\s*(.*?)\s*</td>',
      caseSensitive: false,
      dotAll: true,
    );

    final links = linkPattern.allMatches(html).toList();
    final snippets = snippetPattern.allMatches(html).toList();

    for (var i = 0; i < links.length && results.length < maxResults; i++) {
      final url = links[i].group(1) ?? '';
      final title = _stripHtml(links[i].group(2) ?? '');

      // Skip DuckDuckGo internal links
      if (url.isEmpty || url.startsWith('/') || url.contains('duckduckgo.com')) {
        continue;
      }

      final snippet =
          i < snippets.length ? _stripHtml(snippets[i].group(1) ?? '') : '';

      results.add({
        'title': title,
        'url': url,
        'snippet': snippet,
        'position': results.length + 1,
      });
    }

    return results;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

AiToolDefinition createWebSearchToolDefinition() {
  return AiToolDefinition(
    id: 'web_search',
    displayNameBuilder: (_) => 'Web Search',
    descriptionBuilder: (_) => 'Search the web for information',
    build: (context) => WebSearchTool().tool,
  );
}
