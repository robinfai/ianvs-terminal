import 'dart:io';

/// A test-only description of the Dart files owned by one architecture budget.
final class DartLibraryGraph {
  const DartLibraryGraph({
    required this.files,
    required this.lineCounts,
    required this.cycles,
  });

  /// Canonical paths for every file reachable inside the owned boundary.
  final Set<String> files;

  /// Physical line count keyed by canonical file path.
  final Map<String, int> lineCounts;

  /// Import/export/part cycles encountered while walking the graph.
  ///
  /// Dart library cycles are legal, so they are reported rather than rejected.
  /// Every member of a cycle is still counted exactly once.
  final List<List<String>> cycles;

  int get aggregateLineCount =>
      lineCounts.values.fold(0, (total, lines) => total + lines);
}

/// Thrown when a local Dart library graph cannot be budgeted unambiguously.
final class DartLibraryGraphException implements Exception {
  const DartLibraryGraphException(this.message);

  final String message;

  @override
  String toString() => 'DartLibraryGraphException: $message';
}

/// Recursively scans the local directives of an explicitly owned Dart module.
///
/// Relative URIs and URIs for [packageName] are resolved. Local dependencies
/// inside [ownedDirectory] are always traversed and budgeted, regardless of
/// filename. Dependencies outside that directory must be named explicitly in
/// [allowedExternalFiles]; they are existence-checked but not traversed. Every
/// conditional import/export alternative is treated independently.
final class DartLibraryGraphScanner {
  DartLibraryGraphScanner({
    required this.entrypoint,
    required this.packageName,
    required this.packageLibDirectory,
    required this.ownedDirectory,
    required this.orphanProtectedFiles,
    this.allowedExternalFiles = const <File>[],
  });

  final File entrypoint;
  final String packageName;
  final Directory packageLibDirectory;
  final Directory ownedDirectory;
  final Iterable<File> orphanProtectedFiles;
  final Iterable<File> allowedExternalFiles;

  DartLibraryGraph scan() {
    if (!entrypoint.existsSync()) {
      throw DartLibraryGraphException(
        'Entrypoint does not exist: ${entrypoint.path}',
      );
    }

    if (!ownedDirectory.existsSync()) {
      throw DartLibraryGraphException(
        'Owned directory does not exist: ${ownedDirectory.path}',
      );
    }
    final canonicalEntrypoint = _canonicalExisting(entrypoint);
    final canonicalOwnedDirectory = ownedDirectory.resolveSymbolicLinksSync();
    if (!_isWithinDirectory(canonicalEntrypoint, canonicalOwnedDirectory)) {
      throw DartLibraryGraphException(
        'Entrypoint is outside the owned directory: $canonicalEntrypoint',
      );
    }

    final orphanProtectedPaths = <String>{};
    for (final file in orphanProtectedFiles) {
      if (!file.existsSync()) {
        throw DartLibraryGraphException(
          'Orphan-protected Dart file does not exist: ${file.path}',
        );
      }
      final canonicalPath = _canonicalExisting(file);
      if (!orphanProtectedPaths.add(canonicalPath)) {
        throw DartLibraryGraphException(
          'Duplicate orphan-protected Dart file registration: $canonicalPath',
        );
      }
      if (!_isWithinDirectory(canonicalPath, canonicalOwnedDirectory)) {
        throw DartLibraryGraphException(
          'Orphan-protected file is outside the owned directory: '
          '$canonicalPath',
        );
      }
    }

    final allowedExternalPaths = <String>{};
    for (final file in allowedExternalFiles) {
      if (!file.existsSync()) {
        throw DartLibraryGraphException(
          'Allowlisted external Dart file does not exist: ${file.path}',
        );
      }
      final canonicalPath = _canonicalExisting(file);
      if (!allowedExternalPaths.add(canonicalPath)) {
        throw DartLibraryGraphException(
          'Duplicate external allowlist entry: $canonicalPath',
        );
      }
      if (_isWithinDirectory(canonicalPath, canonicalOwnedDirectory)) {
        throw DartLibraryGraphException(
          'Owned files must not be excluded through the external allowlist: '
          '$canonicalPath',
        );
      }
    }

    final parsedByPath = <String, _ParsedDartFile>{};
    final lineCounts = <String, int>{};
    final visited = <String>{};
    final visiting = <String>{};
    final traversalStack = <String>[];
    final cycles = <List<String>>[];
    final incomingKinds = <String, Set<_DirectiveKind>>{};
    final partOwners = <String, Set<String>>{};

    void visit(String sourcePath) {
      if (visited.contains(sourcePath)) {
        return;
      }
      if (visiting.contains(sourcePath)) {
        final cycleStart = traversalStack.indexOf(sourcePath);
        cycles.add(<String>[...traversalStack.sublist(cycleStart), sourcePath]);
        return;
      }

      visiting.add(sourcePath);
      traversalStack.add(sourcePath);
      final sourceFile = File(sourcePath);
      final source = sourceFile.readAsStringSync();
      final parsed = _DirectiveParser(sourceFile, source).parse();
      parsedByPath[sourcePath] = parsed;
      lineCounts[sourcePath] = _physicalLineCount(source);

      final targetsFromSource = <String>{};
      for (final directive in parsed.outgoing) {
        final targetFile = _resolveLocalDirective(
          sourceFile: sourceFile,
          uriText: directive.uri,
          packageName: packageName,
          packageLibDirectory: packageLibDirectory,
        );
        if (targetFile == null) {
          continue;
        }
        if (!targetFile.existsSync()) {
          throw DartLibraryGraphException(
            '${directive.kind.label} directive at ${sourceFile.path}:'
            '${directive.line} references missing local file ${targetFile.path}',
          );
        }

        final targetPath = _canonicalExisting(targetFile);
        if (!targetsFromSource.add(targetPath)) {
          throw DartLibraryGraphException(
            'Duplicate local directive target at ${sourceFile.path}:'
            '${directive.line}: $targetPath',
          );
        }

        final targetIsOwned = _isWithinDirectory(
          targetPath,
          canonicalOwnedDirectory,
        );
        if (directive.kind == _DirectiveKind.part && !targetIsOwned) {
          throw DartLibraryGraphException(
            'Part directive escapes the owned boundary at '
            '${sourceFile.path}:${directive.line}: $targetPath',
          );
        }
        if (!targetIsOwned) {
          if (!allowedExternalPaths.contains(targetPath)) {
            throw DartLibraryGraphException(
              'Local dependency leaves the owned directory without an '
              'explicit allowlist entry at ${sourceFile.path}:'
              '${directive.line}: $targetPath',
            );
          }
          continue;
        }

        incomingKinds
            .putIfAbsent(targetPath, () => <_DirectiveKind>{})
            .add(directive.kind);
        if (directive.kind == _DirectiveKind.part) {
          partOwners.putIfAbsent(targetPath, () => <String>{}).add(sourcePath);
        }
        visit(targetPath);
      }

      traversalStack.removeLast();
      visiting.remove(sourcePath);
      visited.add(sourcePath);
    }

    visit(canonicalEntrypoint);

    final orphans = orphanProtectedPaths.where(
      (path) => !visited.contains(path),
    );
    if (orphans.isNotEmpty) {
      throw DartLibraryGraphException(
        'Owned Dart files are orphaned from the entrypoint: '
        '${orphans.toList()..sort()}',
      );
    }

    _validatePartOwnership(
      parsedByPath: parsedByPath,
      partOwners: partOwners,
      incomingKinds: incomingKinds,
      packageName: packageName,
      packageLibDirectory: packageLibDirectory,
    );

    return DartLibraryGraph(
      files: Set<String>.unmodifiable(visited),
      lineCounts: Map<String, int>.unmodifiable(lineCounts),
      cycles: List<List<String>>.unmodifiable(
        cycles.map(List<String>.unmodifiable),
      ),
    );
  }
}

void _validatePartOwnership({
  required Map<String, _ParsedDartFile> parsedByPath,
  required Map<String, Set<String>> partOwners,
  required Map<String, Set<_DirectiveKind>> incomingKinds,
  required String packageName,
  required Directory packageLibDirectory,
}) {
  for (final entry in partOwners.entries) {
    final targetPath = entry.key;
    final owners = entry.value;
    if (owners.length != 1) {
      throw DartLibraryGraphException(
        'Part file has multiple declaring libraries: $targetPath -> $owners',
      );
    }
    final kinds = incomingKinds[targetPath] ?? const <_DirectiveKind>{};
    if (kinds.length != 1 || !kinds.contains(_DirectiveKind.part)) {
      throw DartLibraryGraphException(
        'Part file is also reached through a non-part directive: $targetPath',
      );
    }

    final parsedPart = parsedByPath[targetPath]!;
    final partOf = parsedPart.partOf;
    if (partOf == null) {
      throw DartLibraryGraphException(
        'Part file has no part-of directive: $targetPath',
      );
    }
    final ownerPath = owners.single;
    final parsedOwner = parsedByPath[ownerPath]!;
    if (partOf.uri case final ownerUri?) {
      final resolvedOwner = _resolveLocalDirective(
        sourceFile: parsedPart.file,
        uriText: ownerUri,
        packageName: packageName,
        packageLibDirectory: packageLibDirectory,
      );
      if (resolvedOwner == null ||
          _canonicalOrNormalized(resolvedOwner) != ownerPath) {
        throw DartLibraryGraphException(
          'Part-of directive in $targetPath does not name its declaring '
          'library $ownerPath',
        );
      }
    } else if (partOf.libraryName != parsedOwner.libraryName ||
        partOf.libraryName == null) {
      throw DartLibraryGraphException(
        'Named part-of directive in $targetPath does not match the library '
        'name declared by $ownerPath',
      );
    }
  }

  for (final entry in parsedByPath.entries) {
    if (entry.value.partOf != null && !partOwners.containsKey(entry.key)) {
      throw DartLibraryGraphException(
        'Part-of file is reachable without a matching part directive: '
        '${entry.key}',
      );
    }
  }
}

File? _resolveLocalDirective({
  required File sourceFile,
  required String uriText,
  required String packageName,
  required Directory packageLibDirectory,
}) {
  final uri = Uri.parse(uriText);
  if (!uri.hasScheme) {
    return File.fromUri(sourceFile.parent.uri.resolveUri(uri));
  }
  if (uri.scheme == 'file') {
    return File.fromUri(uri);
  }
  if (uri.scheme != 'package') {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.isEmpty || segments.first != packageName) {
    return null;
  }
  return File.fromUri(
    packageLibDirectory.uri.resolve(segments.skip(1).join('/')),
  );
}

String _canonicalExisting(File file) => file.resolveSymbolicLinksSync();

String _canonicalOrNormalized(File file) => file.existsSync()
    ? _canonicalExisting(file)
    : File.fromUri(file.absolute.uri).path;

bool _isWithinDirectory(String filePath, String directoryPath) =>
    filePath == directoryPath ||
    filePath.startsWith('$directoryPath${Platform.pathSeparator}');

int _physicalLineCount(String source) {
  if (source.isEmpty) {
    return 0;
  }
  var separators = 0;
  var offset = 0;
  while (offset < source.length) {
    final width = _lineBreakWidthAt(source, offset);
    if (width == 0) {
      offset += 1;
      continue;
    }
    separators += 1;
    offset += width;
  }
  final endsWithLineBreak = source.endsWith('\n') || source.endsWith('\r');
  return endsWithLineBreak ? separators : separators + 1;
}

enum _DirectiveKind {
  import('import'),
  export('export'),
  part('part');

  const _DirectiveKind(this.label);

  final String label;
}

final class _OutgoingDirective {
  const _OutgoingDirective({
    required this.kind,
    required this.uri,
    required this.line,
  });

  final _DirectiveKind kind;
  final String uri;
  final int line;
}

final class _PartOfDirective {
  const _PartOfDirective.uri(this.uri) : libraryName = null;

  const _PartOfDirective.library(this.libraryName) : uri = null;

  final String? uri;
  final String? libraryName;
}

final class _ParsedDartFile {
  const _ParsedDartFile({
    required this.file,
    required this.outgoing,
    required this.libraryName,
    required this.partOf,
  });

  final File file;
  final List<_OutgoingDirective> outgoing;
  final String? libraryName;
  final _PartOfDirective? partOf;
}

final class _DirectiveParser {
  const _DirectiveParser(this.file, this.source);

  final File file;
  final String source;

  _ParsedDartFile parse() {
    final tokens = _DartLexer(file, source).scan();
    final outgoing = <_OutgoingDirective>[];
    String? libraryName;
    _PartOfDirective? partOf;

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != _TokenKind.identifier) {
        continue;
      }
      final keyword = token.lexeme;
      if (keyword != 'library' &&
          keyword != 'import' &&
          keyword != 'export' &&
          keyword != 'part') {
        continue;
      }

      final end = _directiveEnd(tokens, index, token);
      final body = tokens.sublist(index + 1, end);
      if (keyword == 'library') {
        if (libraryName != null) {
          throw DartLibraryGraphException(
            'Duplicate library directive at ${file.path}:${token.line}',
          );
        }
        libraryName = _qualifiedName(body);
      } else if (keyword == 'part' &&
          body.isNotEmpty &&
          body.first.kind == _TokenKind.identifier &&
          body.first.lexeme == 'of') {
        if (partOf != null) {
          throw DartLibraryGraphException(
            'Duplicate part-of directive at ${file.path}:${token.line}',
          );
        }
        final ownerTokens = body.sublist(1);
        final ownerUris = ownerTokens
            .where((candidate) => candidate.kind == _TokenKind.string)
            .toList(growable: false);
        if (ownerUris.length == 1 && ownerTokens.length == 1) {
          partOf = _PartOfDirective.uri(ownerUris.single.lexeme);
        } else if (ownerUris.isEmpty) {
          partOf = _PartOfDirective.library(_qualifiedName(ownerTokens));
        } else {
          throw DartLibraryGraphException(
            'Invalid part-of directive at ${file.path}:${token.line}',
          );
        }
      } else {
        final kind = switch (keyword) {
          'import' => _DirectiveKind.import,
          'export' => _DirectiveKind.export,
          'part' => _DirectiveKind.part,
          _ => throw StateError('Unreachable directive kind: $keyword'),
        };
        final uris = body
            .where((candidate) => candidate.kind == _TokenKind.string)
            .toList(growable: false);
        if (uris.isEmpty) {
          throw DartLibraryGraphException(
            '$keyword directive has no URI at ${file.path}:${token.line}',
          );
        }
        outgoing.addAll(
          uris.map(
            (uri) => _OutgoingDirective(
              kind: kind,
              uri: uri.lexeme,
              line: token.line,
            ),
          ),
        );
      }
      index = end;
    }

    return _ParsedDartFile(
      file: file,
      outgoing: outgoing,
      libraryName: libraryName,
      partOf: partOf,
    );
  }

  int _directiveEnd(List<_Token> tokens, int start, _Token directive) {
    for (var index = start + 1; index < tokens.length; index += 1) {
      if (tokens[index].kind == _TokenKind.symbol &&
          tokens[index].lexeme == ';') {
        return index;
      }
    }
    throw DartLibraryGraphException(
      'Unterminated ${directive.lexeme} directive at '
      '${file.path}:${directive.line}',
    );
  }

  String _qualifiedName(List<_Token> tokens) {
    final name = tokens.map((token) => token.lexeme).join();
    if (name.isEmpty) {
      throw DartLibraryGraphException(
        'Missing library name in directive at ${file.path}',
      );
    }
    return name;
  }
}

enum _TokenKind { identifier, string, symbol }

final class _Token {
  const _Token(this.kind, this.lexeme, this.line);

  final _TokenKind kind;
  final String lexeme;
  final int line;
}

final class _DartLexer {
  const _DartLexer(this.file, this.source);

  final File file;
  final String source;

  List<_Token> scan() {
    final tokens = <_Token>[];
    var offset = 0;
    var line = 1;
    var inDirective = false;

    bool acceptToken(_Token token) {
      if (!inDirective) {
        final startsDirective =
            token.kind == _TokenKind.identifier &&
            (token.lexeme == 'library' ||
                token.lexeme == 'import' ||
                token.lexeme == 'export' ||
                token.lexeme == 'part');
        if (!startsDirective) {
          return false;
        }
        inDirective = true;
      }
      tokens.add(token);
      if (token.kind == _TokenKind.symbol && token.lexeme == ';') {
        inDirective = false;
      }
      return true;
    }

    while (offset < source.length) {
      final codeUnit = source.codeUnitAt(offset);
      final lineBreakWidth = _lineBreakWidthAt(source, offset);
      if (lineBreakWidth > 0) {
        line += 1;
        offset += lineBreakWidth;
        continue;
      }
      if (_isWhitespace(codeUnit)) {
        offset += 1;
        continue;
      }

      if (codeUnit == 0x2F && offset + 1 < source.length) {
        final next = source.codeUnitAt(offset + 1);
        if (next == 0x2F) {
          offset += 2;
          while (offset < source.length &&
              _lineBreakWidthAt(source, offset) == 0) {
            offset += 1;
          }
          continue;
        }
        if (next == 0x2A) {
          final commentLine = line;
          offset += 2;
          var depth = 1;
          while (offset < source.length && depth > 0) {
            final commentLineBreakWidth = _lineBreakWidthAt(source, offset);
            if (commentLineBreakWidth > 0) {
              line += 1;
              offset += commentLineBreakWidth;
            } else if (offset + 1 < source.length &&
                source.codeUnitAt(offset) == 0x2F &&
                source.codeUnitAt(offset + 1) == 0x2A) {
              depth += 1;
              offset += 2;
            } else if (offset + 1 < source.length &&
                source.codeUnitAt(offset) == 0x2A &&
                source.codeUnitAt(offset + 1) == 0x2F) {
              depth -= 1;
              offset += 2;
            } else {
              offset += 1;
            }
          }
          if (depth != 0) {
            throw DartLibraryGraphException(
              'Unterminated block comment at ${file.path}:$commentLine',
            );
          }
          continue;
        }
      }

      if (!inDirective && codeUnit == 0x40) {
        final result = _skipMetadata(offset: offset, line: line);
        offset = result.offset;
        line = result.line;
        continue;
      }

      final isRawString =
          (codeUnit == 0x72 || codeUnit == 0x52) &&
          offset + 1 < source.length &&
          _isQuote(source.codeUnitAt(offset + 1));
      if (_isQuote(codeUnit) || isRawString) {
        final stringLine = line;
        final result = _scanString(
          offset: offset,
          line: line,
          raw: isRawString,
        );
        if (!acceptToken(_Token(_TokenKind.string, result.value, stringLine))) {
          return tokens;
        }
        offset = result.offset;
        line = result.line;
        continue;
      }

      if (_isIdentifierStart(codeUnit)) {
        final start = offset;
        offset += 1;
        while (offset < source.length &&
            _isIdentifierPart(source.codeUnitAt(offset))) {
          offset += 1;
        }
        if (!acceptToken(
          _Token(_TokenKind.identifier, source.substring(start, offset), line),
        )) {
          return tokens;
        }
        continue;
      }

      if (!acceptToken(_Token(_TokenKind.symbol, source[offset], line))) {
        return tokens;
      }
      offset += 1;
    }

    return tokens;
  }

  _StringScanResult _scanString({
    required int offset,
    required int line,
    required bool raw,
  }) {
    var currentLine = line;
    var cursor = raw ? offset + 1 : offset;
    final quote = source.codeUnitAt(cursor);
    final triple =
        cursor + 2 < source.length &&
        source.codeUnitAt(cursor + 1) == quote &&
        source.codeUnitAt(cursor + 2) == quote;
    cursor += triple ? 3 : 1;
    final value = StringBuffer();

    while (cursor < source.length) {
      final codeUnit = source.codeUnitAt(cursor);
      final lineBreakWidth = _lineBreakWidthAt(source, cursor);
      if (lineBreakWidth > 0) {
        if (!triple) {
          throw DartLibraryGraphException(
            'Unterminated string literal at ${file.path}:$currentLine',
          );
        }
        value.write(source.substring(cursor, cursor + lineBreakWidth));
        currentLine += 1;
        cursor += lineBreakWidth;
        continue;
      }
      if (codeUnit == quote) {
        if (!triple) {
          return _StringScanResult(value.toString(), cursor + 1, currentLine);
        }
        if (cursor + 2 < source.length &&
            source.codeUnitAt(cursor + 1) == quote &&
            source.codeUnitAt(cursor + 2) == quote) {
          return _StringScanResult(value.toString(), cursor + 3, currentLine);
        }
      }
      if (!raw && codeUnit == 0x5C) {
        if (cursor + 1 >= source.length) {
          break;
        }
        cursor += 1;
        value.writeCharCode(source.codeUnitAt(cursor));
        cursor += 1;
        continue;
      }
      value.writeCharCode(codeUnit);
      cursor += 1;
    }

    throw DartLibraryGraphException(
      'Unterminated string literal at ${file.path}:$currentLine',
    );
  }

  _ScanPosition _skipMetadata({required int offset, required int line}) {
    var cursor = offset + 1;
    var currentLine = line;
    var position = _skipTrivia(offset: cursor, line: currentLine);
    cursor = position.offset;
    currentLine = position.line;
    if (cursor >= source.length ||
        !_isIdentifierStart(source.codeUnitAt(cursor))) {
      throw DartLibraryGraphException(
        'Invalid metadata annotation at ${file.path}:$line',
      );
    }

    while (true) {
      while (cursor < source.length &&
          _isIdentifierPart(source.codeUnitAt(cursor))) {
        cursor += 1;
      }
      position = _skipTrivia(offset: cursor, line: currentLine);
      cursor = position.offset;
      currentLine = position.line;
      while (cursor < source.length && source.codeUnitAt(cursor) == 0x3C) {
        position = _skipBalanced(
          offset: cursor,
          line: currentLine,
          openingCodeUnit: 0x3C,
          closingCodeUnit: 0x3E,
        );
        cursor = position.offset;
        currentLine = position.line;
        position = _skipTrivia(offset: cursor, line: currentLine);
        cursor = position.offset;
        currentLine = position.line;
      }
      if (cursor >= source.length || source.codeUnitAt(cursor) != 0x2E) {
        break;
      }

      cursor += 1;
      position = _skipTrivia(offset: cursor, line: currentLine);
      cursor = position.offset;
      currentLine = position.line;
      if (cursor >= source.length ||
          !_isIdentifierStart(source.codeUnitAt(cursor))) {
        throw DartLibraryGraphException(
          'Invalid qualified metadata annotation at ${file.path}:$line',
        );
      }
    }

    if (cursor < source.length && source.codeUnitAt(cursor) == 0x28) {
      position = _skipBalanced(
        offset: cursor,
        line: currentLine,
        openingCodeUnit: 0x28,
        closingCodeUnit: 0x29,
      );
      cursor = position.offset;
      currentLine = position.line;
    }
    return _ScanPosition(cursor, currentLine);
  }

  _ScanPosition _skipBalanced({
    required int offset,
    required int line,
    required int openingCodeUnit,
    required int closingCodeUnit,
  }) {
    var cursor = offset + 1;
    var currentLine = line;
    var depth = 1;
    while (cursor < source.length) {
      final position = _skipTrivia(offset: cursor, line: currentLine);
      cursor = position.offset;
      currentLine = position.line;
      if (cursor >= source.length) {
        break;
      }

      final codeUnit = source.codeUnitAt(cursor);
      final isRawString =
          (codeUnit == 0x72 || codeUnit == 0x52) &&
          cursor + 1 < source.length &&
          _isQuote(source.codeUnitAt(cursor + 1));
      if (_isQuote(codeUnit) || isRawString) {
        final result = _scanString(
          offset: cursor,
          line: currentLine,
          raw: isRawString,
        );
        cursor = result.offset;
        currentLine = result.line;
        continue;
      }
      if (codeUnit == openingCodeUnit) {
        depth += 1;
      } else if (codeUnit == closingCodeUnit) {
        depth -= 1;
        if (depth == 0) {
          return _ScanPosition(cursor + 1, currentLine);
        }
      }
      cursor += 1;
    }
    throw DartLibraryGraphException(
      'Unterminated metadata annotation at ${file.path}:$line',
    );
  }

  _ScanPosition _skipTrivia({required int offset, required int line}) {
    var cursor = offset;
    var currentLine = line;
    while (cursor < source.length) {
      final lineBreakWidth = _lineBreakWidthAt(source, cursor);
      if (lineBreakWidth > 0) {
        currentLine += 1;
        cursor += lineBreakWidth;
        continue;
      }
      final codeUnit = source.codeUnitAt(cursor);
      if (_isWhitespace(codeUnit)) {
        cursor += 1;
        continue;
      }
      if (codeUnit != 0x2F || cursor + 1 >= source.length) {
        break;
      }
      final next = source.codeUnitAt(cursor + 1);
      if (next == 0x2F) {
        cursor += 2;
        while (cursor < source.length &&
            _lineBreakWidthAt(source, cursor) == 0) {
          cursor += 1;
        }
        continue;
      }
      if (next != 0x2A) {
        break;
      }
      cursor += 2;
      var depth = 1;
      while (cursor < source.length && depth > 0) {
        final commentLineBreakWidth = _lineBreakWidthAt(source, cursor);
        if (commentLineBreakWidth > 0) {
          currentLine += 1;
          cursor += commentLineBreakWidth;
        } else if (cursor + 1 < source.length &&
            source.codeUnitAt(cursor) == 0x2F &&
            source.codeUnitAt(cursor + 1) == 0x2A) {
          depth += 1;
          cursor += 2;
        } else if (cursor + 1 < source.length &&
            source.codeUnitAt(cursor) == 0x2A &&
            source.codeUnitAt(cursor + 1) == 0x2F) {
          depth -= 1;
          cursor += 2;
        } else {
          cursor += 1;
        }
      }
      if (depth != 0) {
        throw DartLibraryGraphException(
          'Unterminated block comment at ${file.path}:$line',
        );
      }
    }
    return _ScanPosition(cursor, currentLine);
  }
}

final class _StringScanResult {
  const _StringScanResult(this.value, this.offset, this.line);

  final String value;
  final int offset;
  final int line;
}

final class _ScanPosition {
  const _ScanPosition(this.offset, this.line);

  final int offset;
  final int line;
}

int _lineBreakWidthAt(String source, int offset) {
  final codeUnit = source.codeUnitAt(offset);
  if (codeUnit == 0x0A) {
    return 1;
  }
  if (codeUnit != 0x0D) {
    return 0;
  }
  return offset + 1 < source.length && source.codeUnitAt(offset + 1) == 0x0A
      ? 2
      : 1;
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D ||
    codeUnit == 0x0C;

bool _isQuote(int codeUnit) => codeUnit == 0x27 || codeUnit == 0x22;

bool _isIdentifierStart(int codeUnit) =>
    codeUnit == 0x24 ||
    codeUnit == 0x5F ||
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) || (codeUnit >= 0x30 && codeUnit <= 0x39);
