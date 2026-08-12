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
construct API adapters or discover non-current persistence. Recording and
replay persistence are also outside this boundary.

## Remote authentication

Remote account login requires HTTPS, except for an explicit loopback HTTP
development endpoint. Authentication is a two-step transaction: the app
begins authentication, durably records the prepared credential slot and
transaction intent, and only then completes the server exchange. Passwords
are never persisted. The returned token, expiry, and user-supplied encryption
key live in an immutable, generation-qualified platform credential slot. The
ordinary `configuration.json` contains only non-secret deployment state,
normalized base URL, credential-slot reference, generation, and transaction
identity.

Before committing remote configuration, the client validates both `/v1/me`
and the bounded `POST /v1/auth/verify-key` account-key verifier. A missing, expired,
wrong-origin, or wrong-key session leaves the prior configuration unchanged.
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
`expected_revision: 0` (create-if-absent); updates and deletes use the revision
returned by the preceding read. Terminal-config transforms are pure and may be
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
Authorization and encryption headers therefore cannot be redirected to
another origin.
