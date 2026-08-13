// Shared API types mirroring backend/openapi.yaml. Dates are RFC 3339 strings.

export type Mode = 'local' | 'remote'

export interface Health {
  status: 'ok'
  mode: Mode
  server_id: string
  time: string
}

export interface User {
  id: string
  username: string
  key_configured: boolean
  key_contract_version: number
  key_rotation_supported: boolean
}

export interface PreparedAuthOperation {
  operation_id: string
  expires_at: string
  kind: 'login' | 'register'
}

export interface AuthSession {
  token: string
  expires_at: string
  user: User
}

export interface Resource {
  id: string
  kind: string
  data: unknown
  sensitive?: unknown
  has_sensitive: boolean
  revision: number
  source_id: string
  source_revision: number
  source_updated_at: string
  deleted: boolean
  created_at: string
  updated_at: string
}

export interface ResourcePage {
  resources: Resource[]
  next_cursor?: string
}

export interface ResourceWrite {
  data: unknown
  sensitive?: unknown
  clear_sensitive?: boolean
  expected_revision?: number
}

export interface VerifyKeyResult {
  verified: true
  basis: 'account_key_verifier'
  key_contract_version: number
  key_rotation_supported: false
}

export interface ErrorBody {
  error: { code: string; message: string }
}
