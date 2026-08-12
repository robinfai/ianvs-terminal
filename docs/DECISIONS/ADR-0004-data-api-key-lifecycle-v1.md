# ADR-0004: Data API key lifecycle v1

## Context

The Data API encrypts user-sensitive resource fields with a client-owned key. The
service persists only an Argon2id verifier and therefore cannot recover the key.
Changing that key is not equivalent to changing an account password: every
encrypted resource must be decrypted with the old key and encrypted with the new
one without leaving a mixed-key account.

The initial API accepted a key during local setup or remote registration but did
not define whether a later setup request was verification or rotation. It also
used one unversioned Argon2 parameter set, which would make a future cost change
ambiguous for existing accounts.

## Decision

Key contract version 1 has these rules:

- A key is created once during local setup or remote registration.
- Repeating setup with the same key verifies it. A different key is rejected and
  never mutates the verifier or encrypted resources.
- There is no server-side recovery or rotation endpoint.
- User-provided key material is 16 through 1024 bytes.
- The stored derivation identifier is `argon2id-v1`. Its salt, verifier shape,
  memory, iteration, and parallelism parameters are immutable. A future cost
  change requires a new derivation identifier while retaining readers for v1.
- API user and verify-key responses expose key contract version 1 and
  `key_rotation_supported: false` so clients do not infer rotation support.

## Consequences

Losing the client-owned key makes existing sensitive fields unrecoverable. A user
who needs a different key must currently create a new account or clear and
recreate local data through an explicit migration workflow.

The service can safely verify concurrent first-time local setup: one conditional
write wins and all losers reload and verify the stored result. Bounded Argon2 and
password-hash admissions may return a retryable HTTP 429 instead of allowing
unbounded CPU and memory concurrency.

## Future rotation roadmap

Rotation remains a separate product and protocol milestone. It must require both
the old and new key, verify the old key first, and execute as a resumable or
transactional all-resource operation. Every sensitive resource must be decrypted
and authenticated with the old key, re-encrypted with the new key, and validated
before the verifier changes. Any failure must leave the old verifier and all old
ciphertexts authoritative; a partially rotated account is not an accepted state.

For large accounts, the design must define locking, bounded batches, durable
progress, rollback/recovery, concurrent write behavior, and cross-database crash
semantics before an endpoint is added. A new derivation cost or format must also
receive a new version and retain compatibility with existing `argon2id-v1`
records.

## Alternatives considered

- **Overwrite the verifier on repeated setup.** Rejected because existing
  ciphertext immediately becomes unreadable.
- **Rotate only the verifier and lazily re-encrypt on read.** Rejected because it
  creates a mixed-key account and cannot recover resources that are never read.
- **Store or escrow the raw key server-side.** Rejected because it changes the
  client-owned-key threat model and creates a new recovery secret boundary.
