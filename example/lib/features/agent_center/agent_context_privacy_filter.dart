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
        r'''\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASS)[A-Z0-9_]*\s*=\s*)([^\s'"]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b(token|api[_-]?key|secret|password)=([^&\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=$redactionLabel',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'(--?(?:api[-_]?key|token|secret|password|pass)\s+)([^\s]+)',
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
