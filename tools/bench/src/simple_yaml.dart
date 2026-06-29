final class SimpleYaml {
  const SimpleYaml._();

  static Map<String, Object?> parseMap(String source) {
    final lines = source.split('\n');
    final root = <String, Object?>{};
    final stack = <_YamlLevel>[_YamlLevel(-1, root)];

    for (var index = 0; index < lines.length; index += 1) {
      final rawLine = _stripComment(lines[index]);
      if (rawLine.trim().isEmpty) {
        continue;
      }
      final indent = _leadingSpaces(rawLine);
      final line = rawLine.trimRight();
      final trimmed = line.trimLeft();

      while (stack.length > 1 && indent <= stack.last.indent) {
        stack.removeLast();
      }
      final parent = stack.last.value;

      if (trimmed.startsWith('- ')) {
        if (parent is! List<Object?>) {
          throw const FormatException('YAML list item without list parent');
        }
        parent.add(_parseScalar(trimmed.substring(2).trim()));
        continue;
      }

      final separator = trimmed.indexOf(':');
      if (separator <= 0) {
        throw FormatException('Invalid YAML line: ${lines[index]}');
      }
      if (parent is! Map<String, Object?>) {
        throw const FormatException('YAML key/value without map parent');
      }

      final key = trimmed.substring(0, separator).trim();
      final valueText = trimmed.substring(separator + 1).trim();
      if (valueText.isEmpty) {
        final value = _nextContentLineStartsList(lines, index, indent)
            ? <Object?>[]
            : <String, Object?>{};
        parent[key] = value;
        stack.add(_YamlLevel(indent, value));
      } else {
        parent[key] = _parseScalar(valueText);
      }
    }

    return root;
  }

  static String encodeMap(Map<String, Object?> value) {
    final buffer = StringBuffer();
    _writeMap(buffer, value, 0);
    return buffer.toString();
  }

  static void _writeMap(
    StringBuffer buffer,
    Map<String, Object?> value,
    int indent,
  ) {
    final prefix = ' ' * indent;
    for (final entry in value.entries) {
      final child = entry.value;
      if (child is Map<String, Object?>) {
        buffer.writeln('$prefix${entry.key}:');
        _writeMap(buffer, child, indent + 2);
      } else if (child is List) {
        buffer.writeln('$prefix${entry.key}:');
        for (final item in child) {
          buffer.writeln('$prefix  - ${_formatScalar(item)}');
        }
      } else {
        buffer.writeln('$prefix${entry.key}: ${_formatScalar(child)}');
      }
    }
  }
}

final class _YamlLevel {
  const _YamlLevel(this.indent, this.value);

  final int indent;
  final Object value;
}

String _stripComment(String line) {
  final index = line.indexOf('#');
  if (index < 0) {
    return line;
  }
  return line.substring(0, index);
}

int _leadingSpaces(String value) {
  var count = 0;
  while (count < value.length && value.codeUnitAt(count) == 0x20) {
    count += 1;
  }
  return count;
}

bool _nextContentLineStartsList(List<String> lines, int index, int indent) {
  for (var i = index + 1; i < lines.length; i += 1) {
    final line = _stripComment(lines[i]);
    if (line.trim().isEmpty) {
      continue;
    }
    return _leadingSpaces(line) > indent && line.trimLeft().startsWith('- ');
  }
  return false;
}

Object? _parseScalar(String value) {
  if (value == 'null' || value == '~') {
    return null;
  }
  if (value == 'true') {
    return true;
  }
  if (value == 'false') {
    return false;
  }
  final intValue = int.tryParse(value);
  if (intValue != null) {
    return intValue;
  }
  final doubleValue = double.tryParse(value);
  if (doubleValue != null) {
    return doubleValue;
  }
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _formatScalar(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  return value.toString();
}
