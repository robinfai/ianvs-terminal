import '../services/data_api_client.dart';

DataApiResource requireDataApiResourceIdentity(
  DataApiResource resource, {
  required String kind,
  required String id,
}) {
  if (resource.kind != kind || resource.id != id || resource.deleted) {
    throw FormatException(
      'Data API resource must be the live $kind/$id document.',
    );
  }
  return resource;
}

Map<String, Object?> dataApiObject(
  Object? value, {
  required String documentName,
}) {
  if (value is! Map) {
    throw FormatException('$documentName must be a JSON object.');
  }
  return value.map(
    (key, entryValue) => MapEntry(key.toString(), entryValue as Object?),
  );
}

Map<String, Object?> mergeDataApiObjects(
  Map<String, Object?> data,
  Object? sensitive,
) {
  final result = deepCopyDataApiObject(data);
  if (sensitive is Map) {
    _mergeInto(
      result,
      dataApiObject(sensitive, documentName: 'Sensitive data'),
    );
  }
  return result;
}

Map<String, Object?> deepCopyDataApiObject(Map<String, Object?> source) {
  return source.map((key, value) => MapEntry(key, _deepCopyValue(value)));
}

Map<String, Object?> dataApiJsonDifference(
  Map<String, Object?> complete,
  Map<String, Object?> plain,
) {
  final result = <String, Object?>{};
  for (final entry in complete.entries) {
    final difference = _differenceValue(
      entry.value,
      plain[entry.key],
      plainContainsValue: plain.containsKey(entry.key),
    );
    if (!identical(difference, _noDifference)) {
      result[entry.key] = difference;
    }
  }
  return result;
}

const Object _noDifference = Object();

Object? _differenceValue(
  Object? complete,
  Object? plain, {
  required bool plainContainsValue,
}) {
  if (!plainContainsValue) {
    return _deepCopyValue(complete);
  }
  if (complete is Map && plain is Map) {
    final nested = dataApiJsonDifference(
      dataApiObject(complete, documentName: 'JSON value'),
      dataApiObject(plain, documentName: 'JSON value'),
    );
    return nested.isEmpty ? _noDifference : nested;
  }
  if (complete is List && plain is List && complete.length == plain.length) {
    final differences = <Object?>[];
    var hasDifference = false;
    for (var index = 0; index < complete.length; index += 1) {
      final difference = _differenceValue(
        complete[index],
        plain[index],
        plainContainsValue: true,
      );
      if (identical(difference, _noDifference)) {
        differences.add(
          complete[index] is Map ? const <String, Object?>{} : null,
        );
      } else {
        hasDifference = true;
        differences.add(difference);
      }
    }
    return hasDifference ? differences : _noDifference;
  }
  return complete == plain ? _noDifference : _deepCopyValue(complete);
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return dataApiObject(
      value,
      documentName: 'JSON value',
    ).map((key, entryValue) => MapEntry(key, _deepCopyValue(entryValue)));
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList(growable: false);
  }
  return value;
}

bool dataApiJsonEquivalent(Object? left, Object? right) {
  if (left is num && right is num) {
    return left == right;
  }
  if (left is Map && right is Map) {
    final leftObject = dataApiObject(left, documentName: 'JSON value');
    final rightObject = dataApiObject(right, documentName: 'JSON value');
    if (leftObject.length != rightObject.length) {
      return false;
    }
    for (final entry in leftObject.entries) {
      if (!rightObject.containsKey(entry.key) ||
          !dataApiJsonEquivalent(entry.value, rightObject[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!dataApiJsonEquivalent(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

void _mergeInto(Map<String, Object?> destination, Map<String, Object?> source) {
  for (final entry in source.entries) {
    final destinationValue = destination[entry.key];
    if (destinationValue is Map && entry.value is Map) {
      final nested = dataApiObject(destinationValue, documentName: entry.key);
      destination[entry.key] = nested;
      _mergeInto(nested, dataApiObject(entry.value, documentName: entry.key));
    } else if (destinationValue is List && entry.value is List) {
      destination[entry.key] = _mergeLists(
        destinationValue.cast<Object?>(),
        (entry.value! as List).cast<Object?>(),
      );
    } else {
      destination[entry.key] = _deepCopyValue(entry.value);
    }
  }
}

List<Object?> _mergeLists(List<Object?> destination, List<Object?> source) {
  if (destination.length != source.length) {
    return source.map(_deepCopyValue).toList(growable: false);
  }
  return List<Object?>.generate(destination.length, (index) {
    final destinationValue = destination[index];
    final sourceValue = source[index];
    if (destinationValue is Map && sourceValue is Map) {
      final merged = dataApiObject(
        destinationValue,
        documentName: 'JSON list entry',
      );
      _mergeInto(
        merged,
        dataApiObject(sourceValue, documentName: 'JSON list entry'),
      );
      return merged;
    }
    return sourceValue ?? _deepCopyValue(destinationValue);
  }, growable: false);
}
