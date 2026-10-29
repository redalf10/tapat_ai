import 'dart:convert';

import 'engines.dart';

class LocalTextService {
  const LocalTextService(this.llm);
  final LlmEngine llm;
  static const maxPromptBytes = 1600;

  Future<String> generateDocument(String prompt) => generate(
    prompt,
    systemPrompt: 'Write the content requested by the user for an editable document. '
        'Support explanations, summaries, tutorials and study notes. Return only the document text, '
        'not commentary about creating or saving it. Do not claim to read files or use tools. '
        'Do not invent citations.',
    params: const GenParams(maxTokens: 768, temperature: .4),
  );

  Future<String> generate(String prompt, {required String systemPrompt, GenParams params = const GenParams()}) async {
    prompt = prompt.trim();
    if (prompt.isEmpty) throw const FormatException('Describe what you want the local AI to generate.');
    if (utf8.encode(prompt).length > maxPromptBytes) {
      throw const FormatException('This prompt is too long for the local model. Shorten it to about 1,600 UTF-8 bytes.');
    }
    final output = StringBuffer();
    await for (final token in llm.generate(prompt, systemPrompt: systemPrompt, params: params)) {
      output.write(token);
    }
    final text = output.toString().trim();
    if (text.isEmpty) throw StateError('The local model returned no text. Try another prompt.');
    return text;
  }

  static String truncateUtf8(String text, int maxBytes) {
    final output = StringBuffer();
    var bytes = 0;
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final length = utf8.encode(character).length;
      if (bytes + length > maxBytes) break;
      output.write(character);
      bytes += length;
    }
    return output.toString();
  }
}
