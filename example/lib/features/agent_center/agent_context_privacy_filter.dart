class AgentContextPrivacyFilter {
  const AgentContextPrivacyFilter({this.redactionLabel = '[REDACTED]'});

  final String redactionLabel;

  String redactText(String text) {
    var redacted = text;
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----',
        caseSensitive: false,
        dotAll: true,
      ),
      (_) => redactionLabel,
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'''\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASS|AUTH|CREDENTIAL)[A-Z0-9_]*\s*=\s*)([^\s'"]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b(token|api[_-]?key|access[_-]?key|secret[_-]?key|secret|password|passphrase|auth[_-]?token|credential)=([^&\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b((?:aws[_-]?)?access[_-]?key(?:[_-]?id)?|api[_-]?key|auth[_-]?token)\s+([^\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)} $redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'(--?(?:api[-_]?key|access[-_]?key|secret[-_]?key|auth[-_]?token|token|secret|password|passphrase|pass)\s+)([^\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b(authorization:\s*(?:bearer|basic)\s+)[A-Za-z0-9._~+/=-]{8,}',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'\b(bearer\s+)[A-Za-z0-9._~+/=-]{12,}', caseSensitive: false),
      (match) => '${match.group(1)}$redactionLabel',
    );
    return redacted;
  }
}
