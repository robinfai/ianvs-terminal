/// A repository value bound to the exact optimistic-concurrency revision that
/// authorized it. `revision == null` is reserved for repositories that do not
/// expose server revisions (for example local JSON); Data API snapshots use
/// `0` for a missing resource and a positive value for an existing resource.
final class VersionedDocument<T> {
  const VersionedDocument({required this.value, required this.revision});

  const VersionedDocument.local(T value) : this(value: value, revision: null);

  final T value;
  final int? revision;

  VersionedDocument<R> withValue<R>(R next) {
    return VersionedDocument<R>(value: next, revision: revision);
  }

  VersionedDocument<T> withRevision(int? nextRevision) {
    return VersionedDocument<T>(value: value, revision: nextRevision);
  }
}

int requireDataApiRevision<T>(VersionedDocument<T> document) {
  final revision = document.revision;
  if (revision == null || revision < 0) {
    throw StateError(
      'A Data API write requires the revision token returned with its source '
      'document. Use revision 0 only for an observed missing resource.',
    );
  }
  return revision;
}
