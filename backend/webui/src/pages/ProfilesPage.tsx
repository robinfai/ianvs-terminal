import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { useSession } from '../state/SessionContext'
import {
  Badge,
  Button,
  CheckboxField,
  Dialog,
  EmptyState,
  Notice,
  SelectField,
  Spinner,
  TextField,
} from '../components/ui'
import {
  createCanonicalSshProfile,
  emptySshConnection,
  extractSecrets,
  isSshProfile,
  mergeProfilesDocument,
  newProfileId,
  splitProfilesDocument,
  type ProfileSecrets,
  type ProfilesDocument,
  type SshAuthMethod,
  type SshConnection,
  type SshProfile,
} from '../lib/profileDoc'
import type { ResourceWrite } from '../types'

const AUTH_LABELS: Record<SshAuthMethod, string> = {
  auto: 'Auto',
  password: 'Password',
  public_key: 'Public key',
  keyboard_interactive: 'Keyboard interactive',
}

const AUTH_OPTIONS: SshAuthMethod[] = ['auto', 'password', 'public_key', 'keyboard_interactive']

interface FormValues {
  name: string
  host: string
  user: string
  port: string
  auth: SshAuthMethod
  privateKeys: string
  password: string
  clearPassword: boolean
  privateKeyPassphrase: string
  clearPrivateKeyPassphrase: boolean
}

interface ViewState {
  profile: SshProfile
  secrets: ProfileSecrets | null
}

export function ProfilesPage() {
  const session = useSession()
  const [document, setDocument] = useState<ProfilesDocument | null>(null)
  const [hasSensitive, setHasSensitive] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [refreshToken, setRefreshToken] = useState(0)
  const [view, setView] = useState<ViewState | null>(null)
  const [decrypting, setDecrypting] = useState(false)
  const [editor, setEditor] = useState<{ mode: 'create' } | { mode: 'edit'; profile: SshProfile } | null>(null)
  const [deleting, setDeleting] = useState<SshProfile | null>(null)
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    if (!session.client) return
    setLoading(true)
    setError(null)
    try {
      const resource = await session.client.getResource('profile', 'default', false)
      setDocument(mergeProfilesDocument(asRecord(resource.data), null))
      setHasSensitive(resource.has_sensitive)
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        setDocument({ schemaVersion: 1, profiles: [] })
        setHasSensitive(false)
      } else {
        setError(err instanceof Error ? err.message : String(err))
        setDocument(null)
      }
    } finally {
      setLoading(false)
    }
  }, [session.client])

  useEffect(() => {
    load()
  }, [load, refreshToken])

  const mutate = useCallback(
    async (mutation: (current: ProfilesDocument) => ProfilesDocument | null): Promise<boolean> => {
      const token = session.token
      if (!token) return false
      const makeClient = (key?: string) =>
        new DataApiClient({ baseUrl: session.baseUrl, token, key })
      setSaving(true)
      setError(null)
      try {
        // Load the freshest state. A collection that already holds encrypted
        // secrets can only be rewritten with the key, so ask for it now — the
        // user triggers this encryption by their own edit action.
        let full: ProfilesDocument
        let revision: number | null
        let sensitive: boolean
        let keyValue: string | undefined = session.key ?? undefined
        let client = makeClient(keyValue)
        try {
          const plain = await client.getResource('profile', 'default', false)
          sensitive = plain.has_sensitive
          revision = plain.revision
          full = mergeProfilesDocument(asRecord(plain.data), null)
        } catch (err) {
          if (err instanceof ApiError && err.status === 404) {
            sensitive = false
            revision = null
            full = { schemaVersion: 1, profiles: [] }
          } else {
            throw err
          }
        }
        if (sensitive) {
          const key = await session.requestKey(
            'Modifying the SSH profile collection requires the encryption key to re-encrypt the existing secrets.',
          )
          if (!key) return false
          keyValue = key
          client = makeClient(key)
          const decrypted = await client.getResource('profile', 'default', true)
          full = mergeProfilesDocument(asRecord(decrypted.data), decrypted.sensitive as Record<string, unknown> | null | undefined)
          revision = decrypted.revision
        }
        const next = mutation(full)
        if (!next) return false

        const { data, sensitive: sensitiveEnvelope } = splitProfilesDocument(next)
        // Introducing secrets (e.g. the first profile with a password) also
        // requires the key — the server encrypts with the account key.
        if (sensitiveEnvelope && !keyValue) {
          const key = await session.requestKey(
            'Saving SSH profile secrets requires the encryption key.',
          )
          if (!key) return false
          keyValue = key
          client = makeClient(key)
        }
        const write: ResourceWrite = {
          data,
          sensitive: sensitiveEnvelope ?? undefined,
          clear_sensitive: !sensitiveEnvelope,
          expected_revision: revision ?? 0,
        }
        await client.putResource('profile', 'default', write)
        setRefreshToken((value) => value + 1)
        return true
      } catch (err) {
        if (err instanceof ApiError && err.code === 'invalid_encryption_key') {
          session.clearKey()
          setError('The encryption key is invalid. Enter the correct key and try again.')
        } else if (err instanceof ApiError && err.code === 'revision_conflict') {
          setError('The profile collection changed on the server. Reload and try again.')
        } else {
          setError(err instanceof Error ? err.message : String(err))
        }
        return false
      } finally {
        setSaving(false)
      }
    },
    [session],
  )

  const openCreate = () => setEditor({ mode: 'create' })

  const handleSave = async (values: FormValues) => {
    let ok = false
    if (editor?.mode === 'edit') {
      const original = editor.profile
      ok = await mutate((current) => {
        const target = current.profiles.find((profile) => profile.id === original.id)
        if (!target || !isSshProfile(target)) return null
        const updated: SshProfile = {
          ...target,
          name: values.name.trim(),
          connection: buildConnection(values, target.connection),
        }
        return {
          ...current,
          profiles: current.profiles.map((profile) =>
            profile.id === original.id ? updated : profile,
          ),
        }
      })
    } else {
      ok = await mutate((current) => {
        const profile = createCanonicalSshProfile({
          id: newProfileId(),
          name: values.name.trim(),
          connection: buildConnection(values, undefined),
        })
        return { ...current, profiles: [...current.profiles, profile] }
      })
    }
    if (ok) setEditor(null)
  }

  const handleDelete = async (profile: SshProfile) => {
    const ok = await mutate((current) => {
      if (!current.profiles.some((item) => item.id === profile.id)) return null
      return { ...current, profiles: current.profiles.filter((item) => item.id !== profile.id) }
    })
    if (ok) setDeleting(null)
  }

  const openView = (profile: SshProfile) => {
    setView({ profile, secrets: null })
  }

  const decryptSecrets = async () => {
    if (!view) return
    setDecrypting(true)
    setError(null)
    try {
      const key = await session.requestKey('Decrypt the SSH profile secrets for this collection.')
      if (!key) return
      const client = new DataApiClient({ baseUrl: session.baseUrl, token: session.token ?? '', key })
      const resource = await client.getResource('profile', 'default', true)
      const full = mergeProfilesDocument(asRecord(resource.data), resource.sensitive as Record<string, unknown> | null | undefined)
      const target = full.profiles.find((profile) => profile.id === view.profile.id)
      setView((current) =>
        current ? { ...current, secrets: target ? extractSecrets(target.connection) : {} } : current,
      )
    } catch (err) {
      if (err instanceof ApiError && err.code === 'invalid_encryption_key') {
        session.clearKey()
        setError('The encryption key is invalid. Enter the correct key and try again.')
      } else {
        setError(err instanceof Error ? err.message : String(err))
      }
    } finally {
      setDecrypting(false)
    }
  }

  const profiles = document?.profiles.filter(isSshProfile) ?? []

  return (
    <div className="page">
      <header className="page__header">
        <div>
          <h1 className="page__title">SSH Profiles</h1>
          <p className="page__subtitle">
            Manage the SSH profiles in this encrypted vault. Secrets stay locked until you choose
            to decrypt them.
          </p>
        </div>
        <div className="page__actions">
          <Badge tone={session.key ? 'success' : 'warning'}>
            {session.key ? 'Key ready' : 'Key asked on demand'}
          </Badge>
          <Button variant="primary" onClick={openCreate}>
            New profile
          </Button>
        </div>
      </header>

      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}

      {loading ? (
        <div className="row">
          <Spinner />
          <span className="secondary">Loading profiles…</span>
        </div>
      ) : profiles.length === 0 ? (
        <EmptyState
          title="No SSH profiles"
          description="Profiles are stored as one synced document. Create your first profile with the “New profile” button above."
        />
      ) : (
        <div className="table-wrapper card">
          <table className="table">
            <thead>
              <tr>
                <th scope="col">Name</th>
                <th scope="col">Target</th>
                <th scope="col">Auth</th>
                <th scope="col">Private key</th>
                <th scope="col">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {profiles.map((profile) => (
                <tr key={profile.id}>
                  <td>
                    <strong>{profile.name}</strong>
                  </td>
                  <td className="mono break-word">
                    {profile.connection.user || 'user'}@{profile.connection.host || 'host'}:
                    {profile.connection.port}
                  </td>
                  <td>
                    <Badge tone="info">{AUTH_LABELS[profile.connection.auth] ?? profile.connection.auth}</Badge>
                  </td>
                  <td className="mono break-word secondary">
                    {profile.connection.privateKeys?.length
                      ? profile.connection.privateKeys.join(', ')
                      : '—'}
                  </td>
                  <td>
                    <div className="row">
                      <Button onClick={() => openView(profile)}>View</Button>
                      <Button onClick={() => setEditor({ mode: 'edit', profile })}>Edit</Button>
                      <Button variant="danger" onClick={() => setDeleting(profile)}>
                        Delete
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {view ? (
        <ProfileViewDialog
          view={view}
          hasSensitive={hasSensitive}
          decrypting={decrypting}
          onDecrypt={decryptSecrets}
          onClose={() => setView(null)}
          onEdit={() => {
            setEditor({ mode: 'edit', profile: view.profile })
            setView(null)
          }}
        />
      ) : null}

      {editor ? (
        <ProfileEditor
          mode={editor.mode}
          profile={editor.mode === 'edit' ? editor.profile : undefined}
          saving={saving}
          onSave={handleSave}
          onClose={() => setEditor(null)}
        />
      ) : null}

      {deleting ? (
        <DeleteConfirm
          profile={deleting}
          saving={saving}
          onCancel={() => setDeleting(null)}
          onConfirm={() => handleDelete(deleting)}
        />
      ) : null}
    </div>
  )
}

function asRecord(value: unknown): Record<string, unknown> {
  return (value ?? {}) as Record<string, unknown>
}

function splitPaths(value: string): string[] {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
}

function buildConnection(values: FormValues, existing: SshConnection | undefined): SshConnection {
  const base = existing ? { ...existing } : emptySshConnection()
  const connection: SshConnection = {
    ...base,
    type: 'ssh',
    host: values.host.trim(),
    user: values.user.trim(),
    port: clampPort(values.port),
    auth: values.auth,
    privateKeys: splitPaths(values.privateKeys),
  }
  const password = values.password
  if (password !== '') {
    connection.password = password
  } else if (values.clearPassword) {
    delete connection.password
  }
  const passphrase = values.privateKeyPassphrase
  if (passphrase !== '') {
    connection.privateKeyPassphrase = passphrase
  } else if (values.clearPrivateKeyPassphrase) {
    delete connection.privateKeyPassphrase
  }
  return connection
}

function clampPort(raw: string): number {
  const parsed = Number(raw)
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) return 22
  return parsed
}

function ProfileViewDialog({
  view,
  hasSensitive,
  decrypting,
  onDecrypt,
  onClose,
  onEdit,
}: {
  view: ViewState
  hasSensitive: boolean
  decrypting: boolean
  onDecrypt: () => void
  onClose: () => void
  onEdit: () => void
}) {
  const { profile, secrets } = view
  const connection = profile.connection ?? emptySshConnection()
  return (
    <Dialog
      open
      title={profile.name}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onEdit}>
            Edit
          </Button>
          <Button onClick={onClose}>Close</Button>
        </>
      }
    >
      <dl className="kv-list">
        <div className="kv">
          <dt>Host</dt>
          <dd className="mono break-word">{connection.host || '—'}</dd>
        </div>
        <div className="kv">
          <dt>User</dt>
          <dd>{connection.user || '—'}</dd>
        </div>
        <div className="kv">
          <dt>Port</dt>
          <dd>{connection.port}</dd>
        </div>
        <div className="kv">
          <dt>Auth</dt>
          <dd>
            <Badge tone="info">{AUTH_LABELS[connection.auth] ?? connection.auth}</Badge>
          </dd>
        </div>
        <div className="kv">
          <dt>Private key</dt>
          <dd className="mono break-word">
            {connection.privateKeys?.length ? connection.privateKeys.join(', ') : '—'}
          </dd>
        </div>
      </dl>

      {secrets === null ? (
        <div className="stack">
          {hasSensitive ? (
            <div className="row">
              <Button onClick={onDecrypt} busy={decrypting}>
                Decrypt secrets
              </Button>
              <span className="muted profile-secret-hint">
                The collection holds encrypted secrets. You will be asked for the encryption key.
              </span>
            </div>
          ) : (
            <Notice tone="info">No encrypted secrets are stored for this collection.</Notice>
          )}
        </div>
      ) : (
        <dl className="kv-list">
          <div className="kv">
            <dt>Password</dt>
            <dd className="mono break-word">{secrets.password ?? '—'}</dd>
          </div>
          <div className="kv">
            <dt>Passphrase</dt>
            <dd className="mono break-word">{secrets.privateKeyPassphrase ?? '—'}</dd>
          </div>
          <div className="kv">
            <dt>X11 cookie</dt>
            <dd className="mono break-word">{secrets.x11AuthCookie ?? '—'}</dd>
          </div>
        </dl>
      )}
    </Dialog>
  )
}

function ProfileEditor({
  mode,
  profile,
  saving,
  onSave,
  onClose,
}: {
  mode: 'create' | 'edit'
  profile?: SshProfile
  saving: boolean
  onSave: (values: FormValues) => void
  onClose: () => void
}) {
  const connection = profile?.connection ?? emptySshConnection()
  const [values, setValues] = useState<FormValues>(() => ({
    name: profile?.name ?? '',
    host: connection.host ?? '',
    user: connection.user ?? '',
    port: String(connection.port ?? 22),
    auth: (connection.auth as SshAuthMethod) ?? 'auto',
    privateKeys: connection.privateKeys?.join(', ') ?? '',
    password: '',
    clearPassword: false,
    privateKeyPassphrase: '',
    clearPrivateKeyPassphrase: false,
  }))
  const [error, setError] = useState<string | null>(null)

  const update = <K extends keyof FormValues>(key: K, value: FormValues[K]) => {
    setValues((current) => ({ ...current, [key]: value }))
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    if (!values.name.trim()) {
      setError('Enter a profile name.')
      return
    }
    if (!values.host.trim()) {
      setError('Enter the SSH host.')
      return
    }
    if (!values.user.trim()) {
      setError('Enter the SSH user.')
      return
    }
    onSave(values)
  }

  const isEdit = mode === 'edit'

  return (
    <Dialog
      open
      title={isEdit ? `Edit profile — ${profile?.name}` : 'New SSH profile'}
      onClose={onClose}
      footer={
        <>
          <Button type="submit" variant="primary" form="profile-editor-form" busy={saving}>
            Save
          </Button>
          <Button type="button" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
        </>
      }
    >
      <form id="profile-editor-form" className="stack" onSubmit={submit}>
        <div className="form-grid">
          <TextField
            label="Name"
            value={values.name}
            onChange={(event) => update('name', event.target.value)}
            placeholder="Production"
            required
          />
          <TextField
            label="Host"
            value={values.host}
            onChange={(event) => update('host', event.target.value)}
            placeholder="prod.example.com"
            required
          />
          <TextField
            label="User"
            value={values.user}
            onChange={(event) => update('user', event.target.value)}
            placeholder="root"
            required
          />
          <TextField
            label="Port"
            type="number"
            value={values.port}
            onChange={(event) => update('port', event.target.value)}
            placeholder="22"
            required
          />
        </div>
        <SelectField
          label="Auth method"
          value={values.auth}
          onChange={(event) => update('auth', event.target.value as SshAuthMethod)}
        >
          {AUTH_OPTIONS.map((option) => (
            <option key={option} value={option}>
              {AUTH_LABELS[option]}
            </option>
          ))}
        </SelectField>
        <TextField
          label="Private key paths"
          value={values.privateKeys}
          onChange={(event) => update('privateKeys', event.target.value)}
          placeholder="~/.ssh/id_ed25519"
          hint="One or more paths, comma separated."
        />
        <div className="form-grid">
          <TextField
            label="Password"
            type="password"
            value={values.password}
            onChange={(event) => update('password', event.target.value)}
            autoComplete="new-password"
            hint={
              isEdit
                ? 'Leave blank to keep the stored value; tick “Clear” to remove it.'
                : 'Optional. Encrypted with your data key.'
            }
          />
          <TextField
            label="Key passphrase"
            type="password"
            value={values.privateKeyPassphrase}
            onChange={(event) => update('privateKeyPassphrase', event.target.value)}
            autoComplete="new-password"
            hint={
              isEdit
                ? 'Leave blank to keep the stored value; tick “Clear” to remove it.'
                : 'Optional. Encrypted with your data key.'
            }
          />
        </div>
        {isEdit ? (
          <div className="form-grid">
            <CheckboxField
              label="Clear stored password"
              checked={values.clearPassword}
              onChange={(value) => update('clearPassword', value)}
            />
            <CheckboxField
              label="Clear stored passphrase"
              checked={values.clearPrivateKeyPassphrase}
              onChange={(value) => update('clearPrivateKeyPassphrase', value)}
            />
          </div>
        ) : null}
        {error ? (
          <Notice tone="error" role="alert">
            {error}
          </Notice>
        ) : null}
      </form>
    </Dialog>
  )
}

function DeleteConfirm({
  profile,
  saving,
  onCancel,
  onConfirm,
}: {
  profile: SshProfile
  saving: boolean
  onCancel: () => void
  onConfirm: () => void
}) {
  return (
    <Dialog
      open
      title="Delete profile"
      onClose={onCancel}
      footer={
        <>
          <Button variant="danger" onClick={onConfirm} busy={saving}>
            Delete
          </Button>
          <Button onClick={onCancel} disabled={saving}>
            Cancel
          </Button>
        </>
      }
    >
      <p>
        Delete SSH profile <strong>{profile.name}</strong>? Any encrypted secrets it holds are
        removed with it.
      </p>
    </Dialog>
  )
}
