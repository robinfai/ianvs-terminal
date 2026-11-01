export interface Price { version?: string; input_nano_usd_per_token: number; cached_input_nano_usd_per_token: number; output_nano_usd_per_token: number }
export interface Provider { name: string; type: string; endpoint: string; api_key?: string; has_key: boolean; disabled: boolean }
export interface Model { provider_id: string; model: string; disabled: boolean; max_output_tokens: number; pricing: Price }
export interface Policy { disabled?: boolean; daily_budget_nano_usd?: number | null; daily_requests?: number | null; allowed_models: string[] | null; pricing_overrides?: Record<string, Price> }
export interface Gateway { revision: number; providers: Record<string, Provider>; models: Record<string, Model>; default_model: string; daily_quota_points: number; daily_requests: number; users: Record<string, Policy> }
export interface User { id: string; username: string; created_at: string; ai_disabled: boolean; is_admin: boolean }
export interface Usage { spent_nano_usd: number; reserved_nano_usd: number; input_tokens: number; cached_input_tokens: number; output_tokens: number; settled_requests: number; pending_requests: number }
export interface UserDetail { id: string; username: string; revision: number; policy: Policy; daily_budget_nano_usd: number; daily_remaining_nano_usd: number; daily_requests: number; requests_today: number; wallet: { balance_nano_usd: number; reserved_nano_usd: number; spent_nano_usd: number }; usage: Usage; reset_at: string }
export interface Entry { provider_id?: string; id: string; model: string; provider: string; upstream_model: string; pricing_snapshot: Price; reserved_nano_usd: number; status: string; usage: Usage; created_at: string; settled_at?: string }
export interface RecordRow { user_id: string; username: string; entry: Entry }
export interface Summary { requests: number; spent_nano_usd: number; pending_reserved_nano_usd: number; input_tokens: number; cached_input_tokens: number; output_tokens: number }
export interface Records { data: RecordRow[]; next_cursor: string; summary: Summary }
export interface Audit { id: string; actor_id: string; action: string; target: string; reason: string; created_at: string; details?: unknown }
export interface Page<T> { data: T[]; next_cursor: string }
export const points = (nano: number) => new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 3 }).format(nano / 2000)
export const number = (n: number) => new Intl.NumberFormat('zh-CN').format(n)
export const date = (value: string) => new Date(value).toLocaleString('zh-CN', { hour12: false })
