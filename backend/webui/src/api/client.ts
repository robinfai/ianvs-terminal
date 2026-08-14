import type {
  AuthSession,
  Health,
  PreparedAuthOperation,
  Resource,
  ResourcePage,
  ResourceWrite,
  User,
  VerifyKeyResult,
} from '../types'

export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

export interface ClientOptions {
  baseUrl: string
  token?: string
  key?: string
}

interface RequestOptions {
  body?: unknown
  query?: Record<string, string | number | boolean | undefined>
}

/**
 * Thin typed client for the Ianvs Data API. The bearer token is used both as
 * the remote session token and the local sidecar access token; the encryption
 * key travels in `X-Ianvs-Encryption-Key` and is only honored by endpoints
 * that require it.
 */
export class DataApiClient {
  baseUrl: string
  token?: string
  key?: string

  constructor(options: ClientOptions) {
    this.baseUrl = options.baseUrl.replace(/\/+$/, '')
    this.token = options.token
    this.key = options.key
  }

  private headers(withBody: boolean): Record<string, string> {
    const headers: Record<string, string> = {}
    if (withBody) headers['Content-Type'] = 'application/json'
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`
    if (this.key) headers['X-Ianvs-Encryption-Key'] = this.key
    return headers
  }

  private async request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
    const url = new URL(this.baseUrl + path)
    if (options.query) {
      for (const [name, value] of Object.entries(options.query)) {
        if (value !== undefined && value !== '') url.searchParams.set(name, String(value))
      }
    }
    const response = await fetch(url.toString(), {
      method,
      headers: this.headers(options.body !== undefined),
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    })

    if (response.status === 204) {
      return undefined as T
    }

    const text = await response.text()
    let payload: unknown = undefined
    if (text) {
      try {
        payload = JSON.parse(text)
      } catch {
        payload = undefined
      }
    }

    if (!response.ok) {
      const message = readErrorMessage(payload) ?? `Request failed with status ${response.status}.`
      const code = readErrorCode(payload) ?? 'unknown_error'
      throw new ApiError(response.status, code, message)
    }

    return payload as T
  }

  health(): Promise<Health> {
    return this.request<Health>('GET', '/healthz')
  }

  setupLocal(encryptionKey: string): Promise<{ user: User; initialized: boolean }> {
    return this.request('POST', '/v1/auth/setup', { body: { encryption_key: encryptionKey } })
  }

  beginRegister(username: string, password: string, encryptionKey: string): Promise<PreparedAuthOperation> {
    return this.request('POST', '/v1/auth/register/begin', {
      body: { username, password, encryption_key: encryptionKey },
    })
  }

  completeRegister(operationId: string): Promise<AuthSession> {
    return this.request('POST', '/v1/auth/register/complete', { body: { operation_id: operationId } })
  }

  beginLogin(username: string, password: string): Promise<PreparedAuthOperation> {
    return this.request('POST', '/v1/auth/login/begin', { body: { username, password } })
  }

  completeLogin(operationId: string): Promise<AuthSession> {
    return this.request('POST', '/v1/auth/login/complete', { body: { operation_id: operationId } })
  }

  cancelOperation(operationId: string): Promise<void> {
    return this.request<void>('POST', '/v1/auth/cancel-operation', { body: { operation_id: operationId } })
  }

  logout(): Promise<void> {
    return this.request<void>('POST', '/v1/auth/logout')
  }

  me(): Promise<{ user: User }> {
    return this.request('GET', '/v1/me')
  }

  verifyKey(): Promise<VerifyKeyResult> {
    return this.request('POST', '/v1/auth/verify-key')
  }

  listResources(params: {
    kind?: string
    include_deleted?: boolean
    include_sensitive?: boolean
    limit?: number
    cursor?: string
  } = {}): Promise<ResourcePage> {
    return this.request<ResourcePage>('GET', '/v1/resources', { query: { ...params } })
  }

  getResource(kind: string, id: string, includeSensitive = false): Promise<Resource> {
    return this.request<Resource>('GET', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      query: { include_sensitive: includeSensitive },
    })
  }

  putResource(kind: string, id: string, write: ResourceWrite): Promise<Resource> {
    return this.request<Resource>('PUT', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      body: write,
    })
  }

  deleteResource(kind: string, id: string, expectedRevision?: number): Promise<void> {
    return this.request<void>('DELETE', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      query: { expected_revision: expectedRevision },
    })
  }

}

function readErrorCode(payload: unknown): string | undefined {
  if (!isObject(payload)) return undefined
  const error = (payload as { error?: unknown }).error
  if (!isObject(error)) return undefined
  const code = (error as { code?: unknown }).code
  return typeof code === 'string' ? code : undefined
}

function readErrorMessage(payload: unknown): string | undefined {
  if (!isObject(payload)) return undefined
  const error = (payload as { error?: unknown }).error
  if (!isObject(error)) return undefined
  const message = (error as { message?: unknown }).message
  return typeof message === 'string' ? message : undefined
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
