import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:http/http.dart' as http;

import 'base_tool.dart';

class FetchUrlTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  FetchUrlTool()
      : super(
          name: 'fetch_url',
          description:
              'Fetch remote HTTP/HTTPS content and return a truncated preview. Use this tool to retrieve web page text/HTML/JSON when the user provides a URL.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'Required. HTTP/HTTPS URL to fetch.',
              },
              'mode': {
                'type': 'string',
                'description': 'Optional. How to interpret the response body.',
                'enum': ['text', 'html', 'json'],
              },
              'maxBytes': {
                'type': 'number',
                'description':
                    'Optional. Maximum response bytes to read (truncated). Default 200000. Max 1000000.',
              },
            },
            'required': ['url'],
          },
          timeout: const Duration(seconds: 25),
        );

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  bool _isForbiddenHost(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return true;

    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
      return true;
    }
    if (host == '[::1]' || host == '::1') {
      return true;
    }

    // Block literal private IPs to reduce SSRF risk.
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    if (ip.type == InternetAddressType.IPv4) {
      final parts = host.split('.').map(int.tryParse).toList();
      if (parts.length == 4 && parts.every((e) => e != null)) {
        final a = parts[0]!;
        final b = parts[1]!;
        // 10.0.0.0/8
        if (a == 10) return true;
        // 127.0.0.0/8
        if (a == 127) return true;
        // 192.168.0.0/16
        if (a == 192 && b == 168) return true;
        // 172.16.0.0/12
        if (a == 172 && b >= 16 && b <= 31) return true;
        // 169.254.0.0/16 (link-local)
        if (a == 169 && b == 254) return true;
      }
    }

    return false;
  }

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final urlRaw = input['url']?.toString().trim() ?? '';
    if (urlRaw.isEmpty) {
      throw ArgumentError('url is required');
    }

    final uri = Uri.tryParse(urlRaw);
    if (uri == null) {
      throw ArgumentError('Invalid URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('Only http/https URLs are allowed');
    }
    if (_isForbiddenHost(uri)) {
      throw ArgumentError('Forbidden host');
    }

    final mode = (input['mode']?.toString().trim().toLowerCase()).toString();
    final effectiveMode = switch (mode) {
      'html' => 'html',
      'json' => 'json',
      _ => 'text',
    };

    int maxBytes = 200000;
    final mb = input['maxBytes'];
    if (mb is num) {
      maxBytes = mb.toInt();
    } else if (mb is String) {
      maxBytes = int.tryParse(mb) ?? maxBytes;
    }
    maxBytes = maxBytes.clamp(1024, 1000000);

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'PaperReader/1.0 (+MCP/tools)';
      request.headers['Accept'] =
          effectiveMode == 'json' ? 'application/json,*/*' : '*/*';

      final streamed =
          await client.send(request).timeout(const Duration(seconds: 15));

      final status = streamed.statusCode;
      final contentType = streamed.headers['content-type'] ?? '';

      final bytes = <int>[];
      var truncated = false;
      await for (final chunk in streamed.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          final remain = maxBytes - bytes.length;
          if (remain > 0) {
            bytes.addAll(chunk.take(remain));
          }
          truncated = true;
          break;
        }
        bytes.addAll(chunk);
      }

      // Decode as UTF-8 best-effort.
      final text = utf8.decode(bytes, allowMalformed: true);

      String bodyPreview;
      if (effectiveMode == 'json') {
        try {
          final decoded = jsonDecode(text);
          bodyPreview = const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          bodyPreview = text;
        }
      } else {
        bodyPreview = text;
      }

      // Secondary truncation (chars) to avoid blowing up prompt.
      const maxChars = 12000;
      var previewTruncated = truncated;
      if (bodyPreview.length > maxChars) {
        bodyPreview = bodyPreview.substring(0, maxChars);
        previewTruncated = true;
      }

      return {
        'url': uri.toString(),
        'mode': effectiveMode,
        'statusCode': status,
        'contentType': contentType,
        'truncated': previewTruncated,
        'content': bodyPreview,
      };
    } finally {
      client.close();
    }
  }

  @override
  Map<String, dynamic> serializeSuccess(Map<String, dynamic> output) {
    // Keep the observation compact (caller can inspect fields).
    return {
      'status': 'ok',
      'name': name,
      'data': output,
    };
  }
}

final AiToolDefinition fetchUrlToolDefinition = AiToolDefinition(
  id: 'fetch_url',
  displayNameBuilder: (L10n l10n) => l10n.aiToolFetchUrlName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolFetchUrlDescription,
  build: (context) => FetchUrlTool().tool,
);
