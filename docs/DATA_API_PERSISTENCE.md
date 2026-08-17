# Data API persistence boundary

The Flutter application selects persistence adapters once in
`example/lib/persistence_repository_composition.dart`. A running Data API uses
API adapters exclusively; disabled mode uses the existing local JSON adapters.
If a configured local or remote API cannot start, composition enters an
explicit persistence-unavailable mode. It does not silently read or write the
local JSON repositories.

## Initial startup gate

On macOS, an absent `data-api/configuration.json` pauses the first startup at
the remote HTTP API connection form. The user may authenticate immediately or
explicitly skip. Skipping persists the current Disabled configuration so the
prompt is not repeated, starts no API sidecar, exposes local terminal profiles,
and keeps `~/.ssh/config` discovery available. Custom SSH profile documents are
not available in this local-terminal-only mode.

On iOS, any non-remote configuration pauses startup at the same form without a
skip action. The terminal runtime is not composed until the remote URL and
credentials have been validated and committed. An existing authenticated
remote configuration proceeds normally; expired or missing secure credentials
continue through the typed recovery flow for that same origin.

## Three deployment modes

| Mode | API process/runtime | Custom SSH profiles | Persistence | Cross-device sync |
| --- | --- | --- | --- | --- |
| Local terminal (`disabled`) | None | No; `~/.ssh/config` remains available | Current local terminal repositories | No |
| Bundled local API (`local`, macOS) | Bundled sidecar and local SQLite | Yes | Data API resources, offline | No |
| Remote API (`remote`) | Authenticated HTTP API | Yes | Data API resources | Yes |

The custom-SSH capability depends on persistent API storage, not on cloud
connectivity. The synchronization capability is separate and becomes true only
when the active runtime has a configured remote HTTP API URL.

Each bundled sidecar start receives a fresh 32-byte random Bearer token that
remains process-local; the token is never written to Keychain or a persistent
file, and its private runtime configuration is deleted immediately after the
backend reports READY. One portable master key remains in synchronized Apple
Keychain and is shared automatically by macOS and iOS. Sensitive resource JSON
is encrypted and authenticated by the Flutter client before either local or
remote API upload. The server stores only opaque envelopes.

## Explicit local-to-remote migration

Changing a running bundled local API to Remote in **Defaults & appearance →
Data service** is labelled **Migrate to remote API**. After remote
authentication, the app exports bounded pages from
`GET /v1/migrations/export`, decrypts sensitive envelopes locally under the
source account context, re-encrypts them under the destination account context, and submits each page to
`POST /v1/migrations/merge` with `preserve_destination` and no delete
propagation. Only a complete, conflict-free merge permits the non-secret
deployment configuration to commit as Remote.

Authentication, export, merge, report-identity, cursor, or conflict failures
leave the current Local configuration and sidecar ownership intact. Source
data is never deleted. A partial remote merge can be retried safely because
the server source identity and source revisions make the operation idempotent.
Startup recovery does not offer an implicit Local-to-Remote switch; migration
must be initiated while the local API is running.

## Explicit remote-to-local migration

Changing an authenticated Remote API to **Bundled local API** is labelled
**Migrate to local API**. The app starts an isolated temporary local sidecar,
exports the remote current resources, and merges them with `source_wins` while
keeping `propagate_deletes` disabled. This makes the explicitly selected remote
source authoritative for matching local resources without deleting unrelated
local data. The remote API and its data are never deleted.

Only after every page and merge result succeeds does the app commit the Local
deployment configuration and close the temporary sidecar. Authentication,
export, merge, temporary-runtime cleanup, or configuration-commit failures keep
the Remote deployment active and can be retried safely. The next startup opens
the same local SQLite store through the ordinary bundled-sidecar path.

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
construct API adapters or discover non-current persistence. Recording and
replay persistence are also outside this boundary.

## Remote authentication

Remote account login requires HTTPS, except for an explicit loopback HTTP
development endpoint. Authentication is a two-step transaction: the app
begins authentication, durably records the prepared credential slot and
transaction intent, and only then completes the server exchange. Passwords
are never persisted. The returned token and expiry live in an encrypted,
generation-qualified local credential vault. The independently synchronized
master key unlocks that vault and resource envelopes but is never part of the
authentication request or response. The
ordinary `configuration.json` contains only non-secret deployment state,
normalized base URL, credential-slot reference, generation, and transaction
identity.

Before committing remote configuration, the client validates `/v1/me`. A
missing, expired, or wrong-origin session leaves the prior configuration
unchanged. Key mismatch and corrupt-resource failures are local AEAD/MAC
errors raised only when sensitive data is decrypted.
The same URL can be reconnected explicitly after token loss or expiry.
Switching to local or disabled mode commits the new non-secret configuration
and queues the old immutable credential slot for bounded revocation and
cleanup. Revocation and interrupted-authentication cancellation queues are
durable and replayed on startup; a network failure does not silently erase the
pending work. Configuration, saga journal, and credential slots use
generation/digest compare-and-swap checks under the repository's OS lock, so
another process cannot replace the snapshot being committed. The UI exposes
typed pending-cleanup warnings while startup and settings retry the same
current transaction.

## Concurrency and current API persistence

There is no product-time importer for historical JSON repositories. API-backed
deployments read and write only the current API resource contract; local JSON
adapters remain an explicitly selected disabled-mode backend and are never
silently imported, deleted, or used as fallback data.

API adapters retain server revisions. Initial writes use
`expected_revision: 0` (create-if-absent, including one-winner recreation of a
logically absent tombstone); updates and deletes use the revision returned by
the preceding read. Terminal-config transforms are pure and may be
replayed up to three times after a typed revision conflict. Ordinary save
conflicts remain typed and visible to the caller.

## HTTP client boundary

The client independently validates the base URL, disables redirects, applies
connection and whole-request deadlines, and limits JSON response bodies to the
server contract's 12 MiB maximum envelope. Resource listing exposes only a
bounded cursor page (`limit` is at most 100); callers must explicitly request
the opaque `next_cursor` rather than materializing an unbounded account-wide
list. Malformed JSON, oversized responses, invalid cursors, timeouts,
authentication failures, and revision conflicts are exposed as typed errors.
Authorization headers therefore cannot be redirected to
another origin.
