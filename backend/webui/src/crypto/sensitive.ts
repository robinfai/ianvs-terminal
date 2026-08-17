const ENVELOPE_VERSION = 1
const CIPHER = 'aes-256-gcm'
const DERIVATION_SALT = 'ianvs-portable-master-key-v1'
const PURPOSE = 'data-api-sensitive-v1'
const TAG_BYTES = 16

export interface SensitiveEnvelope {
  version: 1
  cipher: 'aes-256-gcm'
  nonce: string
  ciphertext: string
  mac: string
}

export class SensitiveDataAuthenticationError extends Error {
  readonly kind: string
  readonly id: string

  constructor(kind: string, id: string) {
    super(`Sensitive data for ${kind}/${id} could not be authenticated with this local key.`)
    this.name = 'SensitiveDataAuthenticationError'
    this.kind = kind
    this.id = id
  }
}

export async function encryptSensitive(
  masterKey: string,
  ownerId: string,
  kind: string,
  id: string,
  cleartext: unknown,
): Promise<SensitiveEnvelope> {
  requireIdentity(masterKey, ownerId, kind, id)
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      {
        name: 'AES-GCM',
        iv: nonce,
        additionalData: associatedData(ownerId, kind, id),
        tagLength: TAG_BYTES * 8,
      },
      await deriveKey(masterKey, ownerId, kind, id),
      new TextEncoder().encode(JSON.stringify(cleartext)),
    ),
  )
  const ciphertext = sealed.subarray(0, sealed.length - TAG_BYTES)
  const mac = sealed.subarray(sealed.length - TAG_BYTES)
  return {
    version: ENVELOPE_VERSION,
    cipher: CIPHER,
    nonce: toBase64(nonce),
    ciphertext: toBase64(ciphertext),
    mac: toBase64(mac),
  }
}

export async function decryptSensitive(
  masterKey: string,
  ownerId: string,
  kind: string,
  id: string,
  rawEnvelope: unknown,
): Promise<unknown> {
  requireIdentity(masterKey, ownerId, kind, id)
  const envelope = parseEnvelope(rawEnvelope)
  const ciphertext = fromBase64(envelope.ciphertext)
  const mac = fromBase64(envelope.mac)
  const sealed = new Uint8Array(ciphertext.length + mac.length)
  sealed.set(ciphertext)
  sealed.set(mac, ciphertext.length)
  try {
    const cleartext = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: fromBase64(envelope.nonce),
        additionalData: associatedData(ownerId, kind, id),
        tagLength: TAG_BYTES * 8,
      },
      await deriveKey(masterKey, ownerId, kind, id),
      sealed,
    )
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(cleartext))
  } catch (error) {
    if (error instanceof DOMException && error.name === 'OperationError') {
      throw new SensitiveDataAuthenticationError(kind, id)
    }
    throw error
  }
}

async function deriveKey(
  masterKey: string,
  ownerId: string,
  kind: string,
  id: string,
): Promise<CryptoKey> {
  const encoder = new TextEncoder()
  const material = await crypto.subtle.importKey(
    'raw',
    encoder.encode(masterKey),
    'HKDF',
    false,
    ['deriveKey'],
  )
  return crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: encoder.encode(DERIVATION_SALT),
      info: encoder.encode(`${PURPOSE}:${ownerId}:${kind}:${id}`),
    },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  )
}

function associatedData(ownerId: string, kind: string, id: string): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(`ianvs:${PURPOSE}:${ownerId}:${kind}:${id}`)
}

function parseEnvelope(value: unknown): SensitiveEnvelope {
  if (!isObject(value)) throw new TypeError('Sensitive data envelope must be an object.')
  const fields = Object.keys(value)
  if (
    fields.length !== 5 ||
    fields.some((field) => !['version', 'cipher', 'nonce', 'ciphertext', 'mac'].includes(field)) ||
    value.version !== ENVELOPE_VERSION ||
    value.cipher !== CIPHER ||
    typeof value.nonce !== 'string' ||
    typeof value.ciphertext !== 'string' ||
    typeof value.mac !== 'string' ||
    fromBase64(value.nonce).length !== 12 ||
    fromBase64(value.mac).length !== TAG_BYTES
  ) {
    throw new TypeError('Sensitive data envelope is invalid.')
  }
  return value as unknown as SensitiveEnvelope
}

function toBase64(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

function fromBase64(value: string): Uint8Array<ArrayBuffer> {
  try {
    const binary = atob(value)
    return Uint8Array.from(binary, (character) => character.charCodeAt(0))
  } catch {
    throw new TypeError('Sensitive data envelope is invalid.')
  }
}

function requireIdentity(masterKey: string, ownerId: string, kind: string, id: string): void {
  if (!masterKey || !ownerId || !kind || !id) {
    throw new TypeError('Sensitive data key and identity must not be empty.')
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
