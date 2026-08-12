import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all production features have one resolved runtime subscription', () async {
    final lib = _exampleLibDirectory();
    final coordinator = File(
      '${lib.path}/features/sessions/terminal_event_coordinator.dart',
    ).absolute;
    final sessionController = File(
      '${lib.path}/features/sessions/session_controller.dart',
    ).absolute;
    final productionFiles = _dartFiles(lib)
        .where(
          (file) =>
              file.path == coordinator.path ||
              file.path == sessionController.path ||
              _mayReferenceRuntimeStreams(file),
        )
        .toList(growable: false);
    final violations = <String>[];
    var coordinatorListenCount = 0;
    var coordinatorSignalReferenceCount = 0;
    var compositionReferenceCount = 0;
    final sdkPath = _resolvedDartSdkPath();
    final collection = AnalysisContextCollection(
      includedPaths: <String>[lib.parent.path],
      sdkPath: sdkPath,
    );

    try {
      for (final file in productionFiles) {
        final someResult = await collection
            .contextFor(file.path)
            .currentSession
            .getResolvedUnit(file.path);
        if (someResult is! ResolvedUnitResult) {
          violations.add('${file.path} did not resolve: $someResult');
          continue;
        }
        if (someResult.diagnostics.isNotEmpty) {
          violations.add(
            '${file.path} has analyzer diagnostics: ${someResult.diagnostics}',
          );
          continue;
        }
        final visitor = _ResolvedRuntimeStreamVisitor();
        someResult.unit.accept(visitor);
        for (final reference in visitor.runtimeStreamGetterReferences) {
          final location =
              '${file.path}:'
              '${someResult.lineInfo.getLocation(reference.offset).lineNumber}';
          if (file.path == sessionController.path &&
              reference.name == 'runtimeSignals' &&
              _isCoordinatorCompositionReference(reference)) {
            compositionReferenceCount += 1;
          } else {
            violations.add(
              '$location references TerminalRuntimeController.'
              '${reference.name}',
            );
          }
        }
        for (final reference in visitor.dynamicRuntimeStreamAccesses) {
          final location =
              '${file.path}:'
              '${someResult.lineInfo.getLocation(reference.offset).lineNumber}';
          violations.add(
            '$location dynamically accesses .${reference.name}; runtime '
            'stream ownership must remain statically auditable.',
          );
        }
        if (file.path == coordinator.path) {
          coordinatorListenCount += visitor.listenInvocations.length;
          coordinatorSignalReferenceCount +=
              visitor.coordinatorSignalReferences.length;
          for (final reference in visitor.coordinatorSignalReferences) {
            final parent = reference.parent;
            if (parent is! MethodInvocation ||
                parent.target != reference ||
                parent.methodName.name != 'listen') {
              final location =
                  '${file.path}:'
                  '${someResult.lineInfo.getLocation(reference.offset).lineNumber}';
              violations.add(
                '$location forwards or aliases the coordinator signal stream.',
              );
            }
          }
        }
      }
    } finally {
      await collection.dispose();
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
    expect(
      compositionReferenceCount,
      1,
      reason: 'Only the provider composition may read runtimeSignals.',
    );
    expect(
      coordinatorListenCount,
      1,
      reason: 'The coordinator library must contain exactly one listen call.',
    );
    expect(
      coordinatorSignalReferenceCount,
      1,
      reason: 'The coordinator signal parameter may only be directly listened.',
    );
  });

  test(
    'resolved gate catches alias, tear-off, helper and directory escape',
    () async {
      final fixture = File(
        '${_exampleLibDirectory().parent.path}/test/fixtures/architecture/'
        'terminal_event_subscription_escape.dart',
      ).absolute;
      final sdkPath = _resolvedDartSdkPath();
      final collection = AnalysisContextCollection(
        includedPaths: <String>[_exampleLibDirectory().parent.path],
        sdkPath: sdkPath,
      );
      try {
        final someResult = await collection
            .contextFor(fixture.path)
            .currentSession
            .getResolvedUnit(fixture.path);
        expect(someResult, isA<ResolvedUnitResult>());
        final result = someResult as ResolvedUnitResult;
        expect(result.diagnostics, isEmpty);
        final visitor = _ResolvedRuntimeStreamVisitor();
        result.unit.accept(visitor);
        expect(
          visitor.runtimeStreamGetterReferences
              .map((node) => node.name)
              .toSet(),
          <String>{'runtimeSignals'},
        );
        expect(
          visitor.dynamicRuntimeStreamAccesses.map((node) => node.name).toSet(),
          <String>{'events', 'zmodemEvents', 'zmodemDeferredWriteFailures'},
        );
        expect(visitor.listenInvocations, hasLength(5));
        expect(visitor.coordinatorSignalReferences, hasLength(2));
        expect(
          visitor.coordinatorSignalReferences.any(
            (reference) => reference.parent is! MethodInvocation,
          ),
          isTrue,
        );
      } finally {
        await collection.dispose();
      }
    },
  );
}

bool _isCoordinatorCompositionReference(SimpleIdentifier reference) {
  final named = reference.thisOrAncestorOfType<NamedExpression>();
  final creation = reference.thisOrAncestorOfType<InstanceCreationExpression>();
  return named?.name.label.name == 'signals' &&
      creation?.constructorName.type.name.lexeme == 'TerminalEventCoordinator';
}

const Set<String> _runtimeStreamGetterNames = <String>{
  'events',
  'zmodemEvents',
  'zmodemDeferredWriteFailures',
  'runtimeSignals',
};

final class _ResolvedRuntimeStreamVisitor extends RecursiveAstVisitor<void> {
  final List<SimpleIdentifier> runtimeStreamGetterReferences =
      <SimpleIdentifier>[];
  final List<MethodInvocation> listenInvocations = <MethodInvocation>[];
  final List<SimpleIdentifier> dynamicRuntimeStreamAccesses =
      <SimpleIdentifier>[];
  final List<SimpleIdentifier> coordinatorSignalReferences =
      <SimpleIdentifier>[];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is GetterElement &&
        _runtimeStreamGetterNames.contains(element.name) &&
        element.enclosingElement.name == 'TerminalRuntimeController') {
      runtimeStreamGetterReferences.add(node);
    }
    final parent = node.parent;
    final isDynamicPropertyReference = switch (parent) {
      PropertyAccess(:final propertyName, :final target)
          when propertyName == node =>
        target?.staticType is DynamicType,
      PrefixedIdentifier(:final identifier, :final prefix)
          when identifier == node =>
        prefix.staticType is DynamicType,
      _ => false,
    };
    if (_runtimeStreamGetterNames.contains(node.name) &&
        isDynamicPropertyReference) {
      dynamicRuntimeStreamAccesses.add(node);
    }
    if (node.name == 'signals' && element is FormalParameterElement) {
      coordinatorSignalReferences.add(node);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'listen') {
      listenInvocations.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

Iterable<File> _dartFiles(Directory directory) sync* {
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity.absolute;
    }
  }
}

bool _mayReferenceRuntimeStreams(File file) {
  final source = file.readAsStringSync();
  return const <String>{
    'runtimeSignals',
    'zmodemDeferredWriteFailures',
    'zmodemEvents',
    'events',
  }.any((name) => RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(source));
}

Directory _exampleLibDirectory() {
  final fromWorkspace = Directory('example/lib');
  return (fromWorkspace.existsSync() ? fromWorkspace : Directory('lib'))
      .absolute;
}

String _resolvedDartSdkPath() {
  var ancestor = File(Platform.resolvedExecutable).parent;
  while (true) {
    for (final sdk in <Directory>[
      ancestor,
      Directory('${ancestor.path}/dart-sdk'),
    ]) {
      final libraries = File('${sdk.path}/lib/libraries.json');
      if (libraries.existsSync()) {
        return sdk.path;
      }
    }
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) {
      break;
    }
    ancestor = parent;
  }
  throw StateError(
    'Unable to locate a Dart SDK with lib/libraries.json from '
    '${Platform.resolvedExecutable}.',
  );
}
