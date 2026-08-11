# Data API persistence boundary

The Flutter application selects persistence adapters once in
`example/lib/persistence_repository_composition.dart`. A running Data API uses
API adapters exclusively; disabled mode uses the existing local JSON adapters.
If a configured local or remote API cannot start, composition enters an
explicit persistence-unavailable mode. It does not silently read or write the
local JSON repositories.

## Production-wired resources

| Feature-owned port | Data API resource | Sensitive payload |
| --- | --- | --- |
| Profiles | `profile/default` | SSH and other profile secrets |
| App preferences | `config/preferences` | No |
| Terminal config | `config/local-terminal` | No |
| Terminal layout | `session/layout` | Entire document |
| Paste history | `paste_history/default` | Entire document |

Profiles are one versioned resource rather than one request per profile. This
preserves the local repository's atomic-document behavior and prevents a
conflict from leaving a partially updated profile collection. Profile export
remains an explicit local copy through an injected export-directory resolver;
it is not another persistence source.

Theme, layout-template, and recent-item repositories are deliberately deferred.
They have no production provider/consumer path, so this composition does not
construct API adapters or migrate their legacy files. Recording and replay
persistence are also outside this boundary.

## Remote authentication

Remote account login requires HTTPS, except for an explicit loopback HTTP
development endpoint. The settings flow sends username/password to
`POST /v1/auth/login`; the password is not persisted. The returned token,
expiry, and user-supplied encryption key are stored only in the platform
credential vault. The ordinary `configuration.json` contains only deployment
mode and normalized base URL.

Before committing remote configuration, the client validates both `/v1/me`
and the bounded `POST /v1/auth/verify-key` account-key verifier. A missing, expired,
wrong-origin, or wrong-key session leaves the prior configuration unchanged.
The same URL can be reconnected explicitly after token loss or expiry.
Switching to local or disabled mode commits the new non-secret configuration,
clears the remote session locally, and then performs a bounded best-effort
`POST /v1/auth/logout`. A network failure does not block this escape path: the
UI reports a typed revocation-pending warning and the server token expires on
its normal schedule. There is currently no persistent revocation retry queue.
If credential-vault cleanup itself fails, the UI accurately reports that the
mode was saved but the old local credential remains; restart still uses the
new mode.

## Concurrency and migration

Adapters retain server revisions. Initial writes use
`expected_revision: 0` (create-if-absent); updates and deletes use the revision
returned by the preceding read. Terminal-config transforms are pure and may be
replayed up to three times after a typed revision conflict. Ordinary save
conflicts remain typed and visible to the caller.

Each installation persists a random UUID under the application-support
`data-api` directory. Legacy import uses that UUID for both its source identity
and its per-installation completion marker, rather than an account-global
constant. It submits all production-wired resources to the backend's
transactional `/v1/migrations/merge` endpoint with `preserve_destination`.
Each legacy document is a separate bounded merge transaction so the combined
payload cannot exceed the 12 MiB request contract. A stable installation
source ID and a per-resource monotonic revision journal make completed batches
idempotently skip after a mid-sequence restart. The journal keys revisions by
the SHA-256 of each source file's raw bytes, so a same-size, same-mtime rewrite
still receives a higher source revision. Migration holds both a process-local
guard and an operating-system file lock scoped to the installation. Before it
writes the marker it re-hashes every source that existed at startup and checks
that every source that was absent is still absent.

Only a conflict-free merge writes the normal completion marker. A network or
marker-write failure remains idempotently retryable. Existing remote resources
are never overwritten: a conflict keeps composition in
`persistence-unavailable`, writes no marker, and is shown on the startup
surface. The user may explicitly confirm **Keep remote data**, which writes an
acknowledged marker for that installation while leaving every local JSON file
unchanged. Either a successful retry or that explicit decision requires a
restart before API repositories are unlocked; the locked process never seeds
defaults or falls back to local adapters.

## HTTP client boundary

The client independently validates the base URL, disables redirects, applies
connection and whole-request deadlines, and limits JSON response bodies to the
server contract's 12 MiB maximum envelope. Resource listing exposes only a
bounded cursor page (`limit` is at most 100); callers must explicitly request
the opaque `next_cursor` rather than materializing an unbounded account-wide
list. Malformed JSON, oversized responses, invalid cursors, timeouts,
authentication failures, and revision conflicts are exposed as typed errors.
Authorization and encryption headers therefore cannot be redirected to
another origin.
