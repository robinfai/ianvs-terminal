import 'dart:convert';

/// Decodes one Data API JSON object while rejecting duplicate keys at every
/// nesting level.
///
/// Dart's standard JSON decoder applies last-key-wins semantics. Durable Data
/// API documents are security- and recovery-sensitive, so accepting two
/// conflicting values would make their canonical meaning ambiguous.
Map<String, Object?> decodeDataApiJsonObject(
  String source, {
  required String documentName,
}) {
  final decoded = _DataApiJsonParser(
    source,
    documentName: documentName,
  ).decode();
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$documentName must contain a JSON object.');
  }
  return decoded;
}

final class DataApiJsonDuplicateKeyException implements Exception {
  const DataApiJsonDuplicateKeyException({
    required this.documentName,
    required this.key,
  });

  final String documentName;
  final String key;

  @override
  String toString() {
    return '$documentName contains the duplicate JSON key ${jsonEncode(key)}. '
        'The original durable evidence was preserved.';
  }
}

final class _DataApiJsonParser {
  _DataApiJsonParser(this._source, {required this.documentName});

  final String _source;
  final String documentName;
  var _offset = 0;

  Object? decode() {
    _skipWhitespace();
    final value = _parseValue();
    _skipWhitespace();
    if (_offset != _source.length) {
      _invalid('contains trailing data');
    }
    return value;
  }

  Object? _parseValue() {
    if (_offset >= _source.length) {
      _invalid('ends before a JSON value');
    }
    return switch (_source.codeUnitAt(_offset)) {
      0x7b => _parseObject(),
      0x5b => _parseArray(),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6e => _parseLiteral('null', null),
      _ => _parseNumber(),
    };
  }

  Map<String, Object?> _parseObject() {
    _offset += 1;
    _skipWhitespace();
    final result = <String, Object?>{};
    if (_consume(0x7d)) {
      return result;
    }
    while (true) {
      if (_offset >= _source.length || _source.codeUnitAt(_offset) != 0x22) {
        _invalid('contains an object key that is not a string');
      }
      final key = _parseString();
      if (result.containsKey(key)) {
        throw DataApiJsonDuplicateKeyException(
          documentName: documentName,
          key: key,
        );
      }
      _skipWhitespace();
      _expect(0x3a, 'is missing a colon after an object key');
      _skipWhitespace();
      result[key] = _parseValue();
      _skipWhitespace();
      if (_consume(0x7d)) {
        return result;
      }
      _expect(0x2c, 'is missing a comma between object entries');
      _skipWhitespace();
    }
  }

  List<Object?> _parseArray() {
    _offset += 1;
    _skipWhitespace();
    final result = <Object?>[];
    if (_consume(0x5d)) {
      return result;
    }
    while (true) {
      result.add(_parseValue());
      _skipWhitespace();
      if (_consume(0x5d)) {
        return result;
      }
      _expect(0x2c, 'is missing a comma between array entries');
      _skipWhitespace();
    }
  }

  String _parseString() {
    final start = _offset;
    _offset += 1;
    while (_offset < _source.length) {
      final codeUnit = _source.codeUnitAt(_offset++);
      if (codeUnit == 0x22) {
        try {
          return jsonDecode(_source.substring(start, _offset)) as String;
        } on Object {
          _invalid('contains an invalid JSON string');
        }
      }
      if (codeUnit < 0x20) {
        _invalid('contains an unescaped control character');
      }
      if (codeUnit != 0x5c) {
        continue;
      }
      if (_offset >= _source.length) {
        _invalid('ends within a string escape');
      }
      final escape = _source.codeUnitAt(_offset++);
      if (escape == 0x75) {
        if (_offset + 4 > _source.length) {
          _invalid('ends within a Unicode escape');
        }
        for (var index = 0; index < 4; index += 1) {
          if (!_isHex(_source.codeUnitAt(_offset + index))) {
            _invalid('contains an invalid Unicode escape');
          }
        }
        _offset += 4;
      } else if (!_simpleEscapes.contains(escape)) {
        _invalid('contains an invalid string escape');
      }
    }
    _invalid('ends within a JSON string');
  }

  Object? _parseLiteral(String token, Object? value) {
    if (!_source.startsWith(token, _offset)) {
      _invalid('contains an invalid JSON value');
    }
    _offset += token.length;
    return value;
  }

  num _parseNumber() {
    final match = _jsonNumber.matchAsPrefix(_source, _offset);
    if (match == null) {
      _invalid('contains an invalid JSON value');
    }
    _offset = match.end;
    try {
      return jsonDecode(match.group(0)!) as num;
    } on Object {
      _invalid('contains an invalid JSON number');
    }
  }

  void _skipWhitespace() {
    while (_offset < _source.length &&
        _jsonWhitespace.contains(_source.codeUnitAt(_offset))) {
      _offset += 1;
    }
  }

  bool _consume(int codeUnit) {
    if (_offset < _source.length && _source.codeUnitAt(_offset) == codeUnit) {
      _offset += 1;
      return true;
    }
    return false;
  }

  void _expect(int codeUnit, String message) {
    if (!_consume(codeUnit)) {
      _invalid(message);
    }
  }

  Never _invalid(String message) {
    throw FormatException('$documentName $message at character $_offset.');
  }

  static final RegExp _jsonNumber = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  static const Set<int> _jsonWhitespace = <int>{0x20, 0x09, 0x0a, 0x0d};
  static const Set<int> _simpleEscapes = <int>{
    0x22,
    0x5c,
    0x2f,
    0x62,
    0x66,
    0x6e,
    0x72,
    0x74,
  };
}

bool _isHex(int codeUnit) {
  return codeUnit >= 0x30 && codeUnit <= 0x39 ||
      codeUnit >= 0x41 && codeUnit <= 0x46 ||
      codeUnit >= 0x61 && codeUnit <= 0x66;
}
