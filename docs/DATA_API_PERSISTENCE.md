# Data API persistence and synchronization boundary

The current application is local-first. `example/lib/persistence_repository_composition.dart`
constructs the same local repositories in every deployment mode. An optional
Data API synchronizes selected configuration documents; it does not replace
local persistence or become a prerequisite for saving SSH profiles.

## Module ownership

- `example/lib/data/configuration/` owns deployment configuration, credential
  references, authentication transactions, recovery journals, and cleanup.
- `example/lib/data/services/` owns bounded HTTP transport, client-side
  encryption, credential storage, sidecar lifecycle, and explicit API migration.
- `example/lib/data/sync/` owns local repository decorators, encrypted
  checkpoints, three-way merge, scheduling, conflict resolution, and sync status.
- Feature repositories own their document formats and local storage. Data API
  adapters encode those same documents for API operations and contract tests.
- `backend/` owns authentication, revisioned opaque resources, pagination,
  migration export/merge, SQLite/MySQL persistence, and the embedded Web console.

## Startup and deployment modes

On macOS, an absent `data-api/configuration.json` opens an optional connection
form. On iOS, it opens the mobile welcome screen without credential fields;
users continue locally and configure optional API sync later in Settings.
Skipping setup persists Disabled and continues with local repositories.
Existing configuration is recovered before
starting its transport. Recoverable API configuration, credential, and transport
failures leave local data available with an API synchronization warning.
Unconfirmed sidecar termination and failures that prevent safe recovery remain
startup failures; local-first does not bypass lifecycle or key-integrity checks.

| Mode | API runtime | Application persistence | Synchronization |
| --- | --- | --- | --- |
| Disabled | None | Local repositories, including encrypted SSH profile secrets | Off |
| Local (macOS) | Bundled sidecar with SQLite | Same local repositories | Selected documents synchronized to bundled API |
| Remote | Authenticated HTTP API | Same local repositories | Selected documents synchronized to remote account |

Custom SSH profiles do not require API enablement. The local API remains a
supported explicit deployment, and iOS cannot launch the macOS sidecar.
Changing the active sync transport reuses the local repositories and live
application graph.

## Production sync scope

| Feature | API resource | Sensitive payload | Current production behavior |
| --- | --- | --- | --- |
| Profiles | `profile/default` | SSH and other profile secrets | Bidirectional sync of one atomic document |
| App preferences | `config/preferences` | None | Bidirectional sync |
| Terminal config | `config/local-terminal` | None | Bidirectional sync |
| Terminal layout | None | Local document | Local only |
| Paste history | None | Local document | Local only |

Recording/replay, theme, layout-template, and recent-item repositories are not
bound to this coordinator. The generic server and explicit API adapters can
represent additional resource kinds, but that does not make them production
sync bindings. Profile export is an explicit local copy, not another source.

Local writes commit before scheduling synchronization. The coordinator runs
on start, every 30 seconds, after a 400 ms local-edit debounce, on foreground
resume, and on explicit retry. It compares local and remote documents against
the last acknowledged checkpoint. Independent edits merge; conflicting edits
remain visible until the user chooses local or remote values. Profile arrays
merge by stable profile ID. A whole aggregate resource disappearing remotely
requires a visible choice rather than silently deleting every local profile.

Remote writes use the observed server revision, including `expected_revision: 0`
for create-if-absent. Revision conflicts and concurrent local edits retry at
most three times. Local mutation locks are not held during network I/O. The
checkpoint advances only after the corresponding local commit; checkpoints
are authenticated ciphertext scoped to destination identity and resource.
Remote account identities survive token renewal; different accounts use
separate checkpoints. Network failures and HTTP 401 affect synchronization,
not the ability to read or save local documents.

## Client-only encryption and authentication

One portable master key is stored in synchronized Apple Keychain in production.
Development uses its separate, non-synchronized key namespace. Profile secrets,
credential vault contents, and sync checkpoints use client-side encryption;
sensitive API payloads use AES-256-GCM with account/resource-bound key derivation
and authentication data. The server stores only opaque envelopes and never
receives the master key. See [ADR-0004](DECISIONS/ADR-0004-client-side-sensitive-encryption.md).

Remote login requires HTTPS, except loopback HTTP development endpoints. The
client begins authentication, durably records the prepared credential slot and
transaction intent, and then completes the exchange. Passwords are never
persisted. Tokens and expiry live in an encrypted local credential vault;
`configuration.json` stores only non-secret deployment state, normalized base
URL, credential reference, generation, and transaction identity.

Before configuration commit, `validateSession()` verifies `/v1/me` bearer
access. Key mismatch is detected locally when sensitive data is decrypted.
Configuration and credential transactions use generation/digest compare-and-swap
checks under an OS lock. Cancellation and revocation queues survive restarts;
cleanup failure remains visible and is retried without discarding pending work.

Each bundled sidecar start gets a fresh 32-byte random Bearer token. The token
is process-local; its private startup configuration is removed after READY.
The independent portable master key remains durable so resource envelopes can
be decrypted after restart.

## Explicit API-to-API migration

`DataApiMigrationService` and the authenticated configuration repository retain
bounded, explicit migration between current API stores. This is separate from
normal local-first synchronization and does not import historical JSON files.

Local-to-remote uses `preserve_destination`; remote-to-local uses `source_wins`
against a temporary local runtime. Both disable delete propagation. Each page
comes from `GET /v1/migrations/export` and is submitted to
`POST /v1/migrations/merge`; sensitive data is decrypted and re-encrypted in
client memory for the destination account. Source data is not deleted.

Configuration commits only after every page and report is accepted, with
required temporary-runtime cleanup completed. Source identity, source revisions,
report identity, and cursor checks make interrupted work safely retryable.
The explicit remote fallback mirror also uses staged API storage and activation;
it is not the local repository source used during ordinary sync outages.

## Retained compatibility and removal boundaries

Current configuration, server schema, and sensitive envelopes reject unsupported
versions. Removed server key-verification endpoints and server-side encryption
formats have no fallback readers. Historical feature JSON is not silently
imported into API storage.

The following narrow compatibility paths remain because they protect existing
credentials or encrypted data:

- Predecessor macOS master keys and local API keys are adopted only through
  their guarded migration paths. A mismatched synchronized key is replaced
  only after the candidate authenticates the existing encrypted vault.
- Predecessor per-slot Keychain credentials are copied into the encrypted file
  vault, read back, and retired. Completion markers stop further legacy reads;
  new production writes target the file vault.
- Remote sessions without a saved username retain token-isolated checkpoint
  identities until the next successful login supplies a stable account identity.
- The former project API URL is normalized to the current project URL. The
  configured project transport alias remains a narrowly scoped TLS-handshake
  recovery route; it is not a JSON schema or persistence fallback.

Removing these paths requires evidence that the affected stored data is no
longer supported or a separate explicit migration, not simply absence of new
writes in the old format.

## HTTP boundary

The client validates base URLs, disables redirects, applies connection and
whole-request deadlines, and bounds request/response JSON to 12 MiB. Resource
lists and migration exports use explicit cursor pages of at most 100 resources.
Malformed JSON, invalid cursors, oversized bodies, timeouts, authentication
failures, and revision conflicts remain typed errors.

Redirects cannot forward Authorization to another origin. A TLS handshake
failure may retry once through the explicitly configured fallback transport;
the project default has a fixed HTTPS alias. This occurs before HTTP dispatch,
preserves the configured logical account identity, and never bypasses certificate
validation. Arbitrary server redirects do not select that fallback.

## Verification

From the repository root:

```bash
(cd example && flutter test test/data)
(cd backend && go test ./... && go vet ./...)
(cd backend/webui && pnpm typecheck && pnpm test:unit)
./tools/verify_local_first_sync_http.sh
```

The real HTTP gate uses disposable loopback services and two clients. GUI
startup, settings changes, Keychain prompts, and cross-device synchronization
remain separate acceptance checks in [TESTING.md](TESTING.md).
