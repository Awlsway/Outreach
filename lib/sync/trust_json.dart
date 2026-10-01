import 'dart:convert';

/// Strict bounded JSON for new trust messages only; existing wire readers stay
/// unchanged. Preserve lexical integer rules and reject duplicate escaped keys.
Map<String, dynamic> decodeTrustJson(String text) {
  if (utf8.encode(text).length > 32768) {
    throw const FormatException('Trust response too large');
  }
  final parser = _TrustJson(text);
  final result = parser.value(0);
  parser.space();
  if (parser.i != text.length || result is! Map<String, dynamic>) {
    throw const FormatException('Invalid trust JSON');
  }
  return result;
}

class _TrustJson {
  _TrustJson(this.text);
  final String text;
  int i = 0;
  Never bad() => throw const FormatException('Invalid trust JSON');
  void space() {
    while (i < text.length && ' \t\r\n'.contains(text[i])) {
      i++;
    }
  }

  String string() {
    final start = i++;
    while (i < text.length) {
      if (text[i] == '\\') {
        i += 2;
        continue;
      }
      if (text[i++] == '"') {
        return jsonDecode(text.substring(start, i)) as String;
      }
    }
    bad();
  }

  Object? value(int depth) {
    if (depth > 8) bad();
    space();
    if (i >= text.length) bad();
    if (text[i] == '"') return string();
    if (text[i] == '{') {
      i++;
      space();
      final map = <String, dynamic>{};
      if (i < text.length && text[i] == '}') {
        i++;
        return map;
      }
      while (true) {
        space();
        if (i >= text.length || text[i] != '"') bad();
        final key = string();
        if (map.containsKey(key)) bad();
        space();
        if (i >= text.length || text[i++] != ':') bad();
        map[key] = value(depth + 1);
        space();
        if (i >= text.length) bad();
        final next = text[i++];
        if (next == '}') return map;
        if (next != ',') bad();
      }
    }
    if (text[i] == '[') {
      i++;
      space();
      final values = <Object?>[];
      if (i < text.length && text[i] == ']') {
        i++;
        return values;
      }
      while (true) {
        values.add(value(depth + 1));
        space();
        if (i >= text.length) bad();
        final next = text[i++];
        if (next == ']') return values;
        if (next != ',') bad();
      }
    }
    for (final literal in ['true', 'false', 'null']) {
      if (text.startsWith(literal, i)) {
        i += literal.length;
        return jsonDecode(literal);
      }
    }
    final match = RegExp(r'-?(0|[1-9][0-9]*)').matchAsPrefix(text, i);
    if (match == null) bad();
    i = match.end;
    if (i < text.length && '.eE0123456789'.contains(text[i])) bad();
    return int.parse(match[0]!);
  }
}
