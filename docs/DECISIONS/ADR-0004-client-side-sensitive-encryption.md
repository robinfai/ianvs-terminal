# ADR-0004: Client-side sensitive resource encryption

## Context

Status: accepted; describes the current client-only encryption boundary.

Authentication and data encryption are separate trust boundaries. Supplying a
master key during registration, login, or resource requests lets the service
verify or use material that should remain exclusively on the client. It also
turns a local decryption mismatch into a misleading HTTP 401.

## Decision

- Registration and login accept only account credentials and authentication
  operation capabilities, with optional non-secret device labels and
  explicit session-replacement intent. No authentication operation accepts a
  data encryption key.
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
server ciphertext format, and server compatibility readers are removed.
Unsupported database contracts are rejected; disposable test databases must be
recreated when that contract changes.

Client-side Keychain and encrypted-vault migrations remain separate from this
removal. They preserve the ability to decrypt existing local data, verify
migrated credentials before retiring predecessor items, and use completion
markers to prevent ongoing legacy reads. Production uses one synchronized
master key; development uses an isolated non-synchronized namespace. These
paths must not be removed as if they were server encryption fallback readers.
See [DATA_API_PERSISTENCE.md](../DATA_API_PERSISTENCE.md) for the current
local-first sync scope and retained migration boundaries.
