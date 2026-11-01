import { useCallback, useEffect, useState, type ChangeEvent, type FormEvent } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { SensitiveDataAuthenticationError } from '../crypto/sensitive'
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
  auto: '自动',
  password: '密码',
  public_key: '公钥',
  keyboard_interactive: '键盘交互',
}

const AUTH_OPTIONS: SshAuthMethod[] = ['auto', 'password', 'public_key', 'keyboard_interactive']
const MAX_PRIVATE_KEY_BYTES = 64 * 1024

interface FormValues {
  name: string
  host: string
  user: string
  port: string
  auth: SshAuthMethod
  privateKeyContents: string | null
  privateKeyFileName: string | null
  clearPrivateKeys: boolean
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
  const [feedback, setFeedback] = useState<string | null>(null)

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
      setFeedback(null)
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
            '修改配置集合需要数据密钥，以重新加密并保留已有敏感字段。密钥不会发送到服务器。',
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
        // requires the key so this client can encrypt before upload.
        if (sensitiveEnvelope && !keyValue) {
          const key = await session.requestKey(
            '保存敏感字段需要数据密钥，仅在当前浏览器中用于加密。',
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
        if (err instanceof SensitiveDataAuthenticationError) {
          session.clearKey()
          setError('无法解密：密钥不匹配或数据已损坏。请确认密钥后重试，原数据未修改。')
        } else if (err instanceof ApiError && err.code === 'revision_conflict') {
          setError('服务器配置已更新，本次修改尚未保存。请保留当前输入，关闭编辑后刷新并核对最新版本。')
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

  const openCreate = () => { setError(null); setEditor({ mode: 'create' }) }

  const handleSave = async (values: FormValues) => {
    let ok = false
    if (editor?.mode === 'edit') {
      const original = editor.profile
      ok = await mutate((current) => {
        const target = current.profiles.find((profile) => profile.id === original.id)
        if (!target || !isSshProfile(target)) throw new Error('此配置已被其他客户端删除，请关闭编辑并刷新列表。')
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
    if (ok) { setEditor(null); setFeedback('配置已保存。敏感字段仅以加密形式提交。') }
  }

  const handleDelete = async (profile: SshProfile) => {
    const ok = await mutate((current) => {
      if (!current.profiles.some((item) => item.id === profile.id)) throw new Error('此配置已不存在，请关闭确认框并刷新列表。')
      return { ...current, profiles: current.profiles.filter((item) => item.id !== profile.id) }
    })
    if (ok) { setDeleting(null); setFeedback('配置已删除。其他客户端将在同步后更新。') }
  }

  const openView = (profile: SshProfile) => {
    setError(null)
    setView({ profile, secrets: null })
  }

  const decryptSecrets = async () => {
    if (!view) return
    setDecrypting(true)
    setError(null)
    try {
      const key = await session.requestKey('在当前浏览器中解密此配置的敏感字段。数据密钥不会发送到服务器。')
      if (!key) return
      const client = new DataApiClient({ baseUrl: session.baseUrl, token: session.token ?? '', key })
      const resource = await client.getResource('profile', 'default', true)
      const full = mergeProfilesDocument(asRecord(resource.data), resource.sensitive as Record<string, unknown> | null | undefined)
      const target = full.profiles.find((profile) => profile.id === view.profile.id)
      setView((current) =>
        current ? { ...current, secrets: target ? extractSecrets(target.connection) : {} } : current,
      )
    } catch (err) {
      if (err instanceof SensitiveDataAuthenticationError) {
        session.clearKey()
        setError('无法解密：密钥不匹配或数据已损坏。请确认密钥后重试，原数据未修改。')
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
          <h1 className="page__title">SSH 配置</h1>
          <p className="page__subtitle">
            管理自己的 SSH 连接。名称、主机等普通字段可见；密码和私钥在浏览器中加密，按需解密。
          </p>
        </div>
        <div className="page__actions">
          <Badge tone={session.key ? 'success' : 'warning'}>
            {session.key ? '密钥已暂存 · 由实际解密验证' : '敏感操作时索取密钥'}
          </Badge>
          <Button onClick={() => void load()} disabled={loading || saving}>刷新</Button>
          <Button variant="primary" onClick={openCreate} disabled={loading || !document}>
            新建配置
          </Button>
        </div>
      </header>

      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}

      {feedback ? <Notice tone="success" role="status">{feedback}</Notice> : null}

      {loading ? (
        <div className="row">
          <Spinner />
          <span className="secondary">正在加载配置…</span>
        </div>
      ) : !document && error ? (
        <EmptyState title="无法加载配置" description="请检查连接后重试；不会覆盖已有数据。" action={<Button onClick={() => void load()}>重新加载</Button>} />
      ) : profiles.length === 0 ? (
        <EmptyState
          title="还没有 SSH 配置"
          description="配置保存在同一份同步文档中。点击「新建配置」添加第一台主机。"
        />
      ) : (
        <div className="table-wrapper card">
          <table className="table">
            <thead>
              <tr>
                <th scope="col">名称</th>
                <th scope="col">连接目标</th>
                <th scope="col">认证方式</th>
                <th scope="col">
                  <span className="sr-only">操作</span>
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
                  <td>
                    <div className="row">
                      <Button onClick={() => openView(profile)}>查看</Button>
                      <Button onClick={() => { setError(null); setEditor({ mode: 'edit', profile }) }}>编辑</Button>
                      <Button variant="danger" onClick={() => { setError(null); setDeleting(profile) }}>
                        删除
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
          error={error}
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
          requestError={error}
          mode={editor.mode}
          profile={editor.mode === 'edit' ? editor.profile : undefined}
          saving={saving}
          onSave={handleSave}
          onClose={() => setEditor(null)}
        />
      ) : null}

      {deleting ? (
        <DeleteConfirm
          error={error}
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

function buildConnection(values: FormValues, existing: SshConnection | undefined): SshConnection {
  const base = existing ? { ...existing } : emptySshConnection()
  const connection: SshConnection = {
    ...base,
    type: 'ssh',
    host: values.host.trim(),
    user: values.user.trim(),
    port: clampPort(values.port),
    auth: values.auth,
    privateKeys:
      values.privateKeyContents !== null
        ? [values.privateKeyContents]
        : values.clearPrivateKeys
          ? []
          : existing?.privateKeys ?? [],
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

function looksLikePrivateKeyContents(value: string): boolean {
  const trimmed = value.trimStart()
  return (
    /^-----BEGIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----/.test(trimmed) ||
    trimmed.startsWith('PuTTY-User-Key-File-')
  )
}

function ProfileViewDialog({
  error,
  view,
  hasSensitive,
  decrypting,
  onDecrypt,
  onClose,
  onEdit,
}: {
  error: string | null
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
            编辑
          </Button>
          <Button onClick={onClose}>关闭</Button>
        </>
      }
    >
      {error ? <Notice tone="error" role="alert">{error}</Notice> : null}
      <dl className="kv-list">
        <div className="kv">
          <dt>主机地址</dt>
          <dd className="mono break-word">{connection.host || '—'}</dd>
        </div>
        <div className="kv">
          <dt>SSH 用户名</dt>
          <dd>{connection.user || '—'}</dd>
        </div>
        <div className="kv">
          <dt>端口</dt>
          <dd>{connection.port}</dd>
        </div>
        <div className="kv">
          <dt>认证方式</dt>
          <dd>
            <Badge tone="info">{AUTH_LABELS[connection.auth] ?? connection.auth}</Badge>
          </dd>
        </div>
      </dl>

      {secrets === null ? (
        <div className="stack">
          {hasSensitive ? (
            <div className="row">
              <Button onClick={onDecrypt} busy={decrypting}>
                解密敏感字段
              </Button>
              <span className="muted profile-secret-hint">
                此集合含加密字段，查看时按需索取数据密钥。
              </span>
            </div>
          ) : (
            <Notice tone="info">此配置集合没有加密字段。</Notice>
          )}
        </div>
      ) : (
        <dl className="kv-list">
          <div className="kv">
            <dt>私钥</dt>
            <dd>
              {secrets.privateKeys?.length
                ? `已保存 ${secrets.privateKeys.length} 个私钥`
                : '—'}
            </dd>
          </div>
          <div className="kv">
            <dt>密码</dt>
            <dd className="mono break-word">{secrets.password ?? '—'}</dd>
          </div>
          <div className="kv">
            <dt>私钥口令</dt>
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
  requestError,
  mode,
  profile,
  saving,
  onSave,
  onClose,
}: {
  requestError: string | null
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
    privateKeyContents: null,
    privateKeyFileName: null,
    clearPrivateKeys: false,
    password: '',
    clearPassword: false,
    privateKeyPassphrase: '',
    clearPrivateKeyPassphrase: false,
  }))
  const [error, setError] = useState<string | null>(null)

  const update = <K extends keyof FormValues>(key: K, value: FormValues[K]) => {
    setValues((current) => ({ ...current, [key]: value }))
  }

  const selectPrivateKey = async (event: ChangeEvent<HTMLInputElement>) => {
    const input = event.currentTarget
    const file = input.files?.[0]
    if (!file) return

    setError(null)
    if (file.size > MAX_PRIVATE_KEY_BYTES) {
      setError('私钥文件不能超过 64 KB。')
      input.value = ''
      return
    }
    try {
      const contents = (await file.text()).trim()
      if (!looksLikePrivateKeyContents(contents)) {
        setError('请选择支持的 SSH 私钥文件，不是公钥文件。')
        input.value = ''
        return
      }
      setValues((current) => ({
        ...current,
        privateKeyContents: contents,
        privateKeyFileName: file.name,
        clearPrivateKeys: false,
      }))
    } catch {
      setError('无法读取所选私钥，请重新选择文件。')
      input.value = ''
    }
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    if (!values.name.trim()) {
      setError('请输入配置名称。')
      return
    }
    if (!values.host.trim()) {
      setError('请输入 SSH 主机地址。')
      return
    }
    if (!values.user.trim()) {
      setError('请输入 SSH 用户名。')
      return
    }
    if (
      values.auth === 'public_key' &&
      values.privateKeyContents === null &&
      (mode === 'create' || values.clearPrivateKeys)
    ) {
      setError('使用公钥认证时，请选择私钥文件。')
      return
    }
    if (saving) return
    const port = Number(values.port)
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      setError('端口必须是 1–65535 之间的整数。')
      return
    }
    onSave(values)
  }

  const isEdit = mode === 'edit'

  return (
    <Dialog
      open
      title={isEdit ? `编辑配置 · ${profile?.name}` : '新建 SSH 配置'}
      onClose={() => { if (!saving) onClose() }}
      footer={
        <>
          <Button type="submit" variant="primary" form="profile-editor-form" busy={saving}>
            保存
          </Button>
          <Button type="button" onClick={onClose} disabled={saving}>
            取消
          </Button>
        </>
      }
    >
      <form id="profile-editor-form" className="stack" onSubmit={submit}>
        {requestError ? <Notice tone="error" role="alert">{requestError}</Notice> : null}
        <div className="form-grid">
          <TextField
            label="名称"
            value={values.name}
            onChange={(event) => update('name', event.target.value)}
            placeholder="Production"
            required
          />
          <TextField
            label="主机地址"
            value={values.host}
            onChange={(event) => update('host', event.target.value)}
            placeholder="prod.example.com"
            required
          />
          <TextField
            label="SSH 用户名"
            value={values.user}
            onChange={(event) => update('user', event.target.value)}
            placeholder="root"
            required
          />
          <TextField
            label="端口"
            type="number"
            min={1}
            max={65535}
            step={1}
            value={values.port}
            onChange={(event) => update('port', event.target.value)}
            placeholder="22"
            required
          />
        </div>
        <SelectField
          label="认证方式"
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
          key={`${values.privateKeyFileName ?? 'none'}-${values.clearPrivateKeys}`}
          label="私钥文件"
          type="file"
          onChange={selectPrivateKey}
          disabled={saving}
          hint={
            values.privateKeyFileName
              ? `已选择：${values.privateKeyFileName}。内容将在本机加密后保存。`
              : isEdit
                ? '选择文件会替换已有私钥；不选择则保留已有加密私钥。'
                : '浏览器只显示文件名，不读取路径。私钥内容在本机加密后保存。'
          }
        />
        <div className="form-grid">
          <TextField
            label="密码"
            type="password"
            value={values.password}
            onChange={(event) => setValues(current => ({ ...current, password: event.target.value, clearPassword: false }))}
            autoComplete="new-password"
            hint={
              isEdit
                ? '留空保留原值；勾选下方清除选项才会删除。'
                : '选填，使用你的数据密钥加密。'
            }
          />
          <TextField
            label="私钥口令"
            type="password"
            value={values.privateKeyPassphrase}
            onChange={(event) => setValues(current => ({ ...current, privateKeyPassphrase: event.target.value, clearPrivateKeyPassphrase: false }))}
            autoComplete="new-password"
            hint={
              isEdit
                ? '留空保留原值；勾选下方清除选项才会删除。'
                : '选填，使用你的数据密钥加密。'
            }
          />
        </div>
        {isEdit ? (
          <div className="form-grid">
            <CheckboxField
              label="清除已存密码"
              checked={values.clearPassword}
              onChange={(value) => setValues(current => ({ ...current, clearPassword: value, password: value ? '' : current.password }))}
            />
            <CheckboxField
              label="清除已存私钥口令"
              checked={values.clearPrivateKeyPassphrase}
              onChange={(value) => setValues(current => ({ ...current, clearPrivateKeyPassphrase: value, privateKeyPassphrase: value ? '' : current.privateKeyPassphrase }))}
            />
            <CheckboxField
              label="清除已存私钥"
              hint="除非选择替换文件或明确清除，否则保留已有私钥。"
              checked={values.clearPrivateKeys}
              onChange={(value) => {
                setValues((current) => ({
                  ...current,
                  clearPrivateKeys: value,
                  privateKeyContents: value ? null : current.privateKeyContents,
                  privateKeyFileName: value ? null : current.privateKeyFileName,
                }))
              }}
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
  error,
  profile,
  saving,
  onCancel,
  onConfirm,
}: {
  error: string | null
  profile: SshProfile
  saving: boolean
  onCancel: () => void
  onConfirm: () => void
}) {
  return (
    <Dialog
      open
      title="删除配置"
      onClose={() => { if (!saving) onCancel() }}
      footer={
        <>
          <Button variant="danger" onClick={onConfirm} busy={saving}>
            删除
          </Button>
          <Button data-dialog-initial-focus onClick={onCancel} disabled={saving}>
            取消
          </Button>
        </>
      }
    >
      {error ? <Notice tone="error" role="alert">{error}</Notice> : null}
      <p>
        确定删除 SSH 配置 <strong>{profile.name}</strong>？该配置的加密字段也会删除，并随同步传播。此操作无法在控制台撤销。
      </p>
    </Dialog>
  )
}
