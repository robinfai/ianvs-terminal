import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const composerCatalogRevision = 'ianvs-20260929-v1';

/// Immutable identity shared by the query, response, and acceptance check.
@immutable
final class CompletionQuery {
  const CompletionQuery({
    required this.sessionEpoch,
    required this.targetId,
    required this.contextRevision,
    required this.editorRevision,
    required this.selectionRevision,
    required this.value,
    this.policyRevision = 0,
    this.dialect = 'generic',
  });

  final int sessionEpoch;
  final String targetId;
  final int contextRevision;
  final int editorRevision;
  final int selectionRevision;
  final int policyRevision;
  final String dialect;
  final TextEditingValue value;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sessionEpoch': sessionEpoch,
    'targetId': targetId,
    'contextRevision': contextRevision,
    'editorRevision': editorRevision,
    'selectionRevision': selectionRevision,
    'catalogRevision': composerCatalogRevision,
    'policyRevision': policyRevision,
    'text': value.text,
    'cursorUtf16': value.selection.extentOffset,
    'dialect': dialect,
  };

  bool matches(CompletionQuery other) => mapEquals(toJson(), other.toJson());

  bool get canComplete =>
      value.selection.isValid &&
      value.selection.isCollapsed &&
      value.selection.end <= value.text.length &&
      value.composing.isCollapsed &&
      utf8.encode(value.text).length <= 65536;
}

/// A provider edit always refers to its immutable query, never the live text.
@immutable
final class CompletionEdit {
  const CompletionEdit({
    required this.itemId,
    required this.label,
    required this.detail,
    required this.kind,
    required this.source,
    required this.start,
    required this.end,
    required this.newText,
    required this.cursor,
    this.riskHint = false,
  });

  factory CompletionEdit.fromJson(Map<String, Object?> json) {
    const keys = {
      'itemId',
      'label',
      'detail',
      'kind',
      'source',
      'replaceStartUtf16',
      'replaceEndUtf16',
      'newText',
      'finalCursorUtf16',
      'riskHint',
    };
    if (!setEquals(json.keys.toSet(), keys) ||
        ![
          'itemId',
          'label',
          'detail',
          'kind',
          'source',
          'newText',
        ].every((key) => json[key] is String) ||
        ![
          'replaceStartUtf16',
          'replaceEndUtf16',
          'finalCursorUtf16',
        ].every((key) => json[key] is int) ||
        json['riskHint'] is! bool) {
      throw const FormatException('Invalid completion edit');
    }
    return CompletionEdit(
      itemId: json['itemId']! as String,
      label: json['label']! as String,
      detail: json['detail']! as String,
      kind: json['kind']! as String,
      source: json['source']! as String,
      start: json['replaceStartUtf16']! as int,
      end: json['replaceEndUtf16']! as int,
      newText: json['newText']! as String,
      cursor: json['finalCursorUtf16']! as int,
      riskHint: json['riskHint']! as bool,
    );
  }

  final String itemId;
  final String label;
  final String detail;
  final String kind;
  final String source;
  final int start;
  final int end;
  final String newText;
  final int cursor;
  final bool riskHint;
}

@immutable
final class CompletionBatch {
  const CompletionBatch(this.query, this.items, {this.status = 'ok'});

  factory CompletionBatch.fromJson(
    CompletionQuery query,
    Map<String, Object?> json,
  ) {
    if (!setEquals(json.keys.toSet(), {
          'schemaVersion',
          'query',
          'status',
          'items',
        }) ||
        json['schemaVersion'] != 1 ||
        json['query'] is! Map<String, Object?> ||
        !mapEquals(json['query']! as Map<String, Object?>, query.toJson()) ||
        !{'ok', 'unsupported_context'}.contains(json['status']) ||
        json['items'] is! List ||
        (json['items']! as List).length > 100 ||
        utf8.encode(jsonEncode(json)).length > 262144) {
      throw const FormatException('Invalid or stale completion batch');
    }
    return CompletionBatch(
      query,
      List.unmodifiable(
        (json['items']! as List).map(
          (item) =>
              CompletionEdit.fromJson((item! as Map).cast<String, Object?>()),
        ),
      ),
      status: json['status']! as String,
    );
  }

  final CompletionQuery query;
  final List<CompletionEdit> items;
  final String status;
}

/// Cooperative cancellation is separate from refusing stale UI responses.
final class CompletionCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef CompletionProvider =
    Future<CompletionBatch> Function(
      CompletionQuery query,
      CompletionCancellation cancellation,
    );
