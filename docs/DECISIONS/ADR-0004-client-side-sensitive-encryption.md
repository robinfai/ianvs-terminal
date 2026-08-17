# ADR-0004: Client-side sensitive resource encryption

## Context

Authentication and data encryption are separate trust boundaries. Supplying a
master key during registration, login, or resource requests lets the service
verify or use material that should remain exclusively on the client. It also
turns a local decryption mismatch into a misleading HTTP 401.

## Decision

- Registration and login accept only account credentials and authentication
  operation capabilities.
- The server never receives, derives, verifies, stores, encrypts with, or
  decrypts with a client master key.
- The `sensitive` resource field is an opaque client-generated AES-256-GCM
  envelope. HKDF and AEAD associated data bind it to the authenticated user ID,
  resource kind, and resource ID.
- Flutter keeps one portable master key in synchronized Apple Keychain. The Web
  console keeps an explicitly entered key only in page memory.
- Wrong keys, corrupt envelopes, and transplanted ciphertext are local
  authentication failures. HTTP 401 is reserved for account or bearer-token
  authentication.
- Migration decrypts source envelopes and re-encrypts destination envelopes in
  client memory. The service only exports and merges opaque JSON.

## Consequences

The service cannot validate key correctness before a sensitive resource is
read, and cannot recover lost keys. Server-side curl pipelines cannot migrate
sensitive data between account contexts. Key rotation, if added later, is a
client workflow that rewrites every sensitive envelope; it requires no server
key-verifier protocol.

The project is unreleased, so the old verifier columns, setup/verify endpoints,
server ciphertext format, and compatibility readers are removed. Existing test
databases must be cleared when the schema contract changes.
