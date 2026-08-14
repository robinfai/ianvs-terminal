// SSH profile document helpers.
//
// The Flutter client stores every terminal profile in one canonical resource:
// kind `profile`, id `default`. The web console only exposes SSH profiles, but
// it must preserve local profiles and use the exact same recursive
// data/sensitive split as the Dart DataApiProfileRepository.

export type SshAuthMethod = 'auto' | 'password' | 'public_key' | 'keyboard_interactive'

export type SshHostKeyPolicy = 'strict' | 'accept_new' | 'insecure'

const SECRET_TEXT_CONNECTION_KEYS = ['password', 'privateKeyPassphrase', 'x11AuthCookie'] as const

export const SECRET_CONNECTION_KEYS = [...SECRET_TEXT_CONNECTION_KEYS, 'privateKeys'] as const

const SECRET_JUMP_KEYS = ['password', 'privateKeyPassphrase'] as const

export interface SshConnection {
  type: 'ssh'
  host: string
  user: string
  port: number
  auth: SshAuthMethod
  password?: string
  privateKeys: string[]
  privateKeyPassphrase?: string
  hostKeyPolicy: SshHostKeyPolicy
  knownHostsFile?: string
  connectTimeoutSeconds: number
  keepaliveSeconds: number
  keepaliveCountMax: number
  proxyCommand?: string
  proxyJump?: string
  proxyJumpProfiles: unknown[]
  portForwards: unknown[]
  agentForwarding: boolean
  agentSocket?: string
  x11Forwarding: boolean
  x11TargetHost?: string
  x11TargetPort: number
  x11AuthProtocol: string
  x11AuthCookie?: string
  x11ScreenNumber: number
}

export interface OtherTerminalConnection {
  type: string
  [key: string]: unknown
}

export type TerminalConnection = SshConnection | OtherTerminalConnection

export interface TerminalProfile {
  id: string
  name: string
  connection: TerminalConnection
  tags?: string[]
  [key: string]: unknown
}

export interface SshProfile extends TerminalProfile {
  connection: SshConnection
}

export interface ProfilesDocument {
  schemaVersion: number
  profiles: TerminalProfile[]
}

export interface ProfileSecrets {
  password?: string
  privateKeys?: string[]
  privateKeyPassphrase?: string
  x11AuthCookie?: string
}

export function isSshProfile(profile: TerminalProfile): profile is SshProfile {
  return isRecord(profile.connection) && profile.connection.type === 'ssh'
}

export function extractSecrets(connection: SshConnection | Record<string, unknown>): ProfileSecrets {
  const secrets: ProfileSecrets = {}
  for (const key of SECRET_TEXT_CONNECTION_KEYS) {
    const value = (connection as Record<string, unknown>)[key]
    if (typeof value === 'string' && value.length > 0) {
      secrets[key] = value
    }
  }
  const privateKeys = (connection as Record<string, unknown>).privateKeys
  if (Array.isArray(privateKeys)) {
    const values = privateKeys.filter(
      (value): value is string => typeof value === 'string' && value.length > 0,
    )
    if (values.length > 0) secrets.privateKeys = values
  }
  return secrets
}

function redactProfileSecrets(profile: TerminalProfile): Record<string, unknown> {
  const copy = cloneJson(profile) as Record<string, unknown>
  const connection = copy.connection
  if (!isRecord(connection) || connection.type !== 'ssh') return copy

  for (const key of SECRET_CONNECTION_KEYS) delete connection[key]
  const jumpProfiles = connection.proxyJumpProfiles
  if (Array.isArray(jumpProfiles)) {
    for (const jump of jumpProfiles) {
      if (!isRecord(jump)) continue
      for (const key of SECRET_JUMP_KEYS) delete jump[key]
    }
  }
  return copy
}

export interface SplitProfilesResult {
  data: Record<string, unknown>
  /** Non-null only when at least one profile carries a secret. */
  sensitive: Record<string, unknown> | null
}

export function splitProfilesDocument(document: ProfilesDocument): SplitProfilesResult {
  const complete: Record<string, unknown> = {
    schemaVersion: document.schemaVersion,
    profiles: document.profiles.map(normalizeCompleteProfile),
  }
  const data: Record<string, unknown> = {
    schemaVersion: document.schemaVersion,
    profiles: document.profiles.map(redactProfileSecrets),
  }
  const difference = jsonDifference(complete, data)
  return {
    data,
    sensitive: Object.keys(difference).length > 0 ? difference : null,
  }
}

function normalizeCompleteProfile(profile: TerminalProfile): Record<string, unknown> {
  const copy = cloneJson(profile) as Record<string, unknown>
  const connection = copy.connection
  if (!isRecord(connection) || connection.type !== 'ssh') return copy

  // An empty key list carries no secret and must not force an otherwise plain
  // profile collection to allocate an encrypted envelope.
  if (Array.isArray(connection.privateKeys) && connection.privateKeys.length === 0) {
    delete connection.privateKeys
  }
  return copy
}

/** Recombine the plain document with the decrypted sensitive envelope. */
export function mergeProfilesDocument(
  data: Record<string, unknown>,
  sensitive: Record<string, unknown> | null | undefined,
): ProfilesDocument {
  const merged = sensitive ? mergeJsonObjects(data, sensitive) : cloneJson(data)
  return merged as unknown as ProfilesDocument
}

/** The canonical SSH connection used by TerminalConnectionConfig.toJson(). */
export function emptySshConnection(partial: Partial<SshConnection> = {}): SshConnection {
  return {
    host: '',
    user: '',
    port: 22,
    auth: 'auto',
    privateKeys: [],
    hostKeyPolicy: 'accept_new',
    connectTimeoutSeconds: 10,
    keepaliveSeconds: 0,
    keepaliveCountMax: 3,
    proxyJumpProfiles: [],
    portForwards: [],
    agentForwarding: false,
    x11Forwarding: false,
    x11TargetPort: 0,
    x11AuthProtocol: 'MIT-MAGIC-COOKIE-1',
    x11ScreenNumber: 0,
    ...partial,
    type: 'ssh',
  }
}

/**
 * Builds the same current-schema profile emitted by TerminalProfile.toJson().
 * Keep this fixture in lock-step with TerminalSessionConfig.toJson() in the
 * Dart package; the cross-client contract test rejects any drift.
 */
export function createCanonicalSshProfile({
  id,
  name,
  connection,
}: {
  id: string
  name: string
  connection: SshConnection
}): SshProfile {
  const emptyAnsi = {
    black: null,
    red: null,
    green: null,
    yellow: null,
    blue: null,
    magenta: null,
    cyan: null,
    white: null,
  }
  return {
    id,
    name,
    launch: {
      program: '',
      args: [],
      env: {},
      cwd: null,
    },
    connection,
    terminal: {
      emulation: 'xterm256',
      scrollbackLines: 8000,
      graphics: {
        enabled: true,
        advertise: 'kitty',
        maxImageBytes: 104857600,
        maxTotalBytes: 268435456,
      },
      dragDropEnabled: false,
    },
    shellIntegration: { enabled: true },
    appearance: {
      font: {
        family: 'JetBrainsMono Nerd Font Mono',
        fallback: [
          'Menlo',
          'JetBrainsMono Nerd Font',
          'SF Mono',
          'Monaco',
          'Apple Symbols',
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Noto Color Emoji',
        ],
        size: 14,
        lineHeight: 1.6,
      },
      colors: {
        special: {
          foreground: null,
          background: null,
          cursor: null,
          selection: null,
          tab: null,
        },
        normal: { ...emptyAnsi },
        bright: { ...emptyAnsi },
      },
      cursor: { shape: 'block', blink: true },
    },
    interaction: {
      copyOnSelect: false,
      optionDragMode: 'block_selection',
    },
  }
}

export function newProfileId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

const noDifference = Symbol('no-difference')

function jsonDifference(
  complete: Record<string, unknown>,
  plain: Record<string, unknown>,
): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, completeValue] of Object.entries(complete)) {
    const difference = differenceValue(
      completeValue,
      plain[key],
      Object.prototype.hasOwnProperty.call(plain, key),
    )
    if (difference !== noDifference) result[key] = difference
  }
  return result
}

function differenceValue(
  complete: unknown,
  plain: unknown,
  plainContainsValue: boolean,
): unknown | typeof noDifference {
  if (!plainContainsValue) return cloneJson(complete)
  if (isRecord(complete) && isRecord(plain)) {
    const nested = jsonDifference(complete, plain)
    return Object.keys(nested).length === 0 ? noDifference : nested
  }
  if (Array.isArray(complete) && Array.isArray(plain) && complete.length === plain.length) {
    const differences: unknown[] = []
    let hasDifference = false
    for (let index = 0; index < complete.length; index += 1) {
      const difference = differenceValue(complete[index], plain[index], true)
      if (difference === noDifference) {
        differences.push(isRecord(complete[index]) ? {} : null)
      } else {
        hasDifference = true
        differences.push(difference)
      }
    }
    return hasDifference ? differences : noDifference
  }
  return Object.is(complete, plain) ? noDifference : cloneJson(complete)
}

function mergeJsonObjects(
  destination: Record<string, unknown>,
  source: Record<string, unknown>,
): Record<string, unknown> {
  const result = cloneJson(destination)
  for (const [key, sourceValue] of Object.entries(source)) {
    const destinationValue = result[key]
    if (isRecord(destinationValue) && isRecord(sourceValue)) {
      result[key] = mergeJsonObjects(destinationValue, sourceValue)
    } else if (Array.isArray(destinationValue) && Array.isArray(sourceValue)) {
      result[key] = mergeJsonArrays(destinationValue, sourceValue)
    } else {
      result[key] = cloneJson(sourceValue)
    }
  }
  return result
}

function mergeJsonArrays(destination: unknown[], source: unknown[]): unknown[] {
  if (destination.length !== source.length) return cloneJson(source)
  return destination.map((destinationValue, index) => {
    const sourceValue = source[index]
    if (isRecord(destinationValue) && isRecord(sourceValue)) {
      return mergeJsonObjects(destinationValue, sourceValue)
    }
    return sourceValue === null ? cloneJson(destinationValue) : cloneJson(sourceValue)
  })
}

function cloneJson<T>(value: T): T {
  if (value === undefined) return value
  return JSON.parse(JSON.stringify(value)) as T
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
