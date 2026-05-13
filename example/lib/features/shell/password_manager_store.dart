class PasswordManagerEntry {
  const PasswordManagerEntry({
    required this.id,
    required this.label,
    required this.password,
  });

  final String id;
  final String label;
  final String password;
}

class PasswordManagerStore {
  final List<PasswordManagerEntry> _entries = <PasswordManagerEntry>[];
  int _nextId = 0;

  List<PasswordManagerEntry> get entries =>
      List<PasswordManagerEntry>.unmodifiable(_entries);

  PasswordManagerEntry add({required String label, required String password}) {
    final entry = PasswordManagerEntry(
      id: 'password-${_nextId++}',
      label: label.trim().isEmpty ? 'Password $_nextId' : label.trim(),
      password: password,
    );
    _entries.insert(0, entry);
    return entry;
  }

  void remove(String id) {
    _entries.removeWhere((entry) => entry.id == id);
  }

  void clear() {
    _entries.clear();
  }
}
