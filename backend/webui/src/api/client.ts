import type {
  AuthSession,
  Health,
  PreparedAuthOperation,
  Resource,
  ResourcePage,
  ResourceWrite,
  User,
} from '../types'
import { decryptSensitive, encryptSensitive } from '../crypto/sensitive'

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
 * the remote session token and the local sidecar access token. Sensitive JSON
 * is encrypted and decrypted here; the master key never enters an HTTP header
 * or request body.
 */
export class DataApiClient {
  baseUrl: string
  token?: string
  key?: string
  private ownerId?: Promise<string>

  constructor(options: ClientOptions) {
    this.baseUrl = options.baseUrl.replace(/\/+$/, '')
    this.token = options.token
    this.key = options.key
  }

  private headers(withBody: boolean): Record<string, string> {
    const headers: Record<string, string> = {}
    if (withBody) headers['Content-Type'] = 'application/json'
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`
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

  beginRegister(username: string, password: string): Promise<PreparedAuthOperation> {
    return this.request('POST', '/v1/auth/register/begin', {
      body: { username, password },
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

  async listResources(params: {
    kind?: string
    include_deleted?: boolean
    include_sensitive?: boolean
    limit?: number
    cursor?: string
  } = {}): Promise<ResourcePage> {
    const page = await this.request<ResourcePage>('GET', '/v1/resources', { query: { ...params } })
    if (!params.include_sensitive) return page
    return {
      ...page,
      resources: await Promise.all(page.resources.map((resource) => this.decryptResource(resource))),
    }
  }

  async getResource(kind: string, id: string, includeSensitive = false): Promise<Resource> {
    const resource = await this.request<Resource>('GET', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      query: { include_sensitive: includeSensitive },
    })
    return includeSensitive ? this.decryptResource(resource) : resource
  }

  async putResource(kind: string, id: string, write: ResourceWrite): Promise<Resource> {
    const sensitive = write.sensitive
    const body: ResourceWrite = {
      ...write,
      sensitive:
        sensitive === undefined
          ? undefined
          : await encryptSensitive(this.requireKey(), await this.requireOwnerId(), kind, id, sensitive),
    }
    const resource = await this.request<Resource>('PUT', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      body,
    })
    return sensitive === undefined ? resource : this.decryptResource(resource)
  }

  deleteResource(kind: string, id: string, expectedRevision?: number): Promise<void> {
    return this.request<void>('DELETE', `/v1/resources/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, {
      query: { expected_revision: expectedRevision },
    })
  }

  private requireKey(): string {
    if (!this.key) throw new Error('The local encryption key is required for sensitive data.')
    return this.key
  }

  private requireOwnerId(): Promise<string> {
    return (this.ownerId ??= this.loadOwnerId())
  }

  private async loadOwnerId(): Promise<string> {
    const { user } = await this.me()
    if (!user?.id) throw new Error('The authenticated user response is missing user.id.')
    return user.id
  }

  private async decryptResource(resource: Resource): Promise<Resource> {
    if (resource.sensitive === undefined) {
      if (resource.has_sensitive) {
        throw new Error('The API omitted its requested sensitive envelope.')
      }
      return resource
    }
    return {
      ...resource,
      sensitive: await decryptSensitive(
        this.requireKey(),
        await this.requireOwnerId(),
        resource.kind,
        resource.id,
        resource.sensitive,
      ),
    }
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
