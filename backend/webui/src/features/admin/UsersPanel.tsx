import { useEffect, useRef, useState } from 'react'
import { ApiError, type DataApiClient } from '../../api/client'
import { Button, Card, Dialog, EmptyState, Notice, TextField } from '../../components/ui'
import type { Gateway, Page, User, UserDetail } from './types'
import { date, number, points } from './types'

export const adminError = (e: unknown) => e instanceof ApiError && e.code === 'revision_conflict' ? '配置已被其他操作修改，请刷新详情后重试。' : e instanceof ApiError && e.status === 403 ? '当前账号没有管理权限。' : '操作未完成。请检查输入、原因及余额；若刚调整额度时网络中断，请使用相同内容重试，不会重复到账。'
export function UsersPanel({ client, gateway, viewRecords }: { client: DataApiClient; gateway: Gateway; viewRecords: (id: string) => void }) {
  const [query, setQuery] = useState(''); const [search, setSearch] = useState('')
  const [users, setUsers] = useState<User[]>([]); const [next, setNext] = useState('')
  const [detail, setDetail] = useState<UserDetail | null>(null); const [error, setError] = useState('')
  const [loading, setLoading] = useState(false); const [selected, setSelected] = useState('')
  const sequence = useRef(0)
  const list = async (after = '') => {
    setLoading(true); setError('')
    try { const page = await client.admin<Page<User>>('users', { query: { q: search, after } }); setUsers(old => after ? [...old, ...page.data] : page.data); setNext(page.next_cursor) } catch (e) { setError(adminError(e)) } finally { setLoading(false) }
  }
  useEffect(() => { void list() }, [search])
  const open = async (id: string) => {
    const current = ++sequence.current; setSelected(id); setDetail(null); setError('')
    try { const value = await client.admin<UserDetail>(`users/${id}`); if (current === sequence.current) setDetail(value) } catch (e) { if (current === sequence.current) setError(adminError(e)) }
  }
  return <div className="stack"><form className="row wrap" onSubmit={e => { e.preventDefault(); setSearch(query) }}><TextField label="搜索用户名" value={query} onChange={e => setQuery(e.target.value)} /><Button type="submit">搜索</Button><Button onClick={() => void list()} disabled={loading}>刷新用户</Button></form>{error && <Notice tone="error" role="alert">{error}</Notice>}<div className="admin-columns"><Card title="用户"><div className="stack">{users.map(u => <Button key={u.id} aria-pressed={selected === u.id} variant={selected === u.id ? 'primary' : 'secondary'} onClick={() => void open(u.id)}>{u.username} · {u.ai_disabled ? 'AI 已禁用' : 'AI 可用'}{u.is_admin ? ' · 管理员' : ''}</Button>)}{!users.length && !loading && <EmptyState title="没有匹配用户" />}{loading && <p role="status">加载中…</p>}{next && <Button disabled={loading} onClick={() => void list(next)}>加载更多用户</Button>}</div></Card><div>{detail ? <UserEditor key={`${detail.id}-${detail.revision}`} value={detail} gateway={gateway} client={client} updated={setDetail} refresh={() => void open(detail.id)} viewRecords={() => viewRecords(detail.id)} /> : <EmptyState title={selected ? '正在加载用户详情…' : '选择一个用户管理额度'} />}</div></div></div>
}
function UserEditor({ value, gateway, client, updated, refresh, viewRecords }: { value: UserDetail; gateway: Gateway; client: DataApiClient; updated: (u: UserDetail) => void; refresh: () => void; viewRecords: () => void }) {
  const rateFields = [['requests_per_second', '每秒请求数', 1], ['requests_per_minute', '每分钟请求数', 10], ['requests_per_hour', '每小时请求数', 100], ['tokens_per_minute', '每分钟 token 数', 100000], ['tokens_per_hour', '每小时 token 数', 1000000]] as const
  const [rates, setRates] = useState<Record<string, string>>(() => Object.fromEntries(rateFields.map(([key]) => [key, value.policy[key] == null ? '' : String(value.policy[key])])))
  const invalidRates = rateFields.some(([key]) => rates[key] !== '' && (!Number.isSafeInteger(Number(rates[key])) || Number(rates[key]) < 1 || Number(rates[key]) > (key.startsWith('tokens') ? 1000000000 : 10000)))
  const [daily, setDaily] = useState(value.policy.daily_budget_nano_usd == null ? '' : String(value.policy.daily_budget_nano_usd / 2000))
  const [requests, setRequests] = useState(value.policy.daily_requests == null ? '' : String(value.policy.daily_requests))
  const [disabled, setDisabled] = useState(value.policy.disabled ?? false)
  const [restricted, setRestricted] = useState(value.policy.allowed_models != null)
  const [allowed, setAllowed] = useState(value.policy.allowed_models ?? [])
  const [reason, setReason] = useState(''); const [amount, setAmount] = useState(''); const [creditReason, setCreditReason] = useState('')
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [success, setSuccess] = useState(''); const [confirm, setConfirm] = useState(false)
  const creditOperation = useRef<{ signature: string; id: string } | null>(null)
  const save = async () => {
    setBusy(true); setError(''); setSuccess('')
    try { const response = await client.admin<UserDetail>(`users/${value.id}/policy`, { method: 'PUT', body: { revision: value.revision, reason, policy: { ...value.policy, ...Object.fromEntries(rateFields.map(([key]) => [key, rates[key] === '' ? null : Number(rates[key])])), disabled, daily_budget_nano_usd: daily === '' ? null : Math.round(Number(daily) * 2000), daily_requests: requests === '' ? null : Number(requests), allowed_models: restricted ? allowed : null } } }); updated(response); setSuccess('额度策略已保存。') } catch (e) { setError(adminError(e)) } finally { setBusy(false) }
  }
  const credit = async () => {
    setBusy(true); setError(''); setSuccess(''); setConfirm(false)
    const signature = `${value.id}:${amount}:${creditReason}`
    if (creditOperation.current?.signature !== signature) creditOperation.current = { signature, id: crypto.randomUUID() }
    try {
      await client.admin(`users/${value.id}/credits`, { method: 'POST', body: { operation_id: creditOperation.current.id, points: Number(amount), reason: creditReason } })
      setSuccess('额度调整已到账并记录审计。'); setAmount(''); setCreditReason('')
      const current = await client.admin<UserDetail>(`users/${value.id}`); updated(current)
    } catch (e) { setError(adminError(e)) } finally { setBusy(false) }
  }
  return <div className="stack"><Card title={value.username}><div className="stack"><p className="secondary break-word">{value.id}</p><div className="metric-grid"><div><p className="secondary">每日剩余 / 总额</p><strong>{points(value.daily_remaining_nano_usd)} / {points(value.daily_budget_nano_usd)} 点</strong></div><div><p className="secondary">长期额度余额 / 预占</p><strong>{points(value.wallet.balance_nano_usd)} / {points(value.wallet.reserved_nano_usd)} 点</strong></div><div><p className="secondary">今日请求 / 上限</p><strong>{number(value.requests_today)} / {number(value.daily_requests)}</strong></div><div><p className="secondary">今日已扣 / 预占</p><strong>{points(value.usage.spent_nano_usd)} / {points(value.usage.reserved_nano_usd)} 点</strong></div></div><p className="secondary">每日额度重置：{date(value.reset_at)}（本地时间）。购买及人工调整的长期额度不随每日重置。</p><div className="row"><Button onClick={refresh}>刷新详情</Button><Button onClick={viewRecords}>查看使用记录</Button></div></div></Card>
    <Card title="用户额度策略"><div className="stack"><label className="row"><input type="checkbox" checked={disabled} onChange={e => setDisabled(e.target.checked)} />禁用此用户 AI（已有进行中请求继续结算）</label><div className="admin-form-grid"><TextField label="每日免费额度（点）" type="number" min="0" max="1000000000" value={daily} placeholder="留空继承默认值" onChange={e => setDaily(e.target.value)} /><TextField label="每日请求上限" type="number" min="0" value={requests} placeholder="留空继承默认值" onChange={e => setRequests(e.target.value)} /></div><label className="row"><input type="checkbox" checked={restricted} onChange={e => setRestricted(e.target.checked)} />限制可用模型</label>{restricted && <div className="row wrap">{Object.keys(gateway.models).map(id => <label className="row" key={id}><input type="checkbox" checked={allowed.includes(id)} onChange={e => setAllowed(old => e.target.checked ? [...old, id] : old.filter(x => x !== id))} />{id}</label>)}<p className="secondary">未选择任何模型时禁止所有模型。</p></div>}<p className="secondary">请求与 token 限制叠加，按用户跨模型共享滚动窗口。留空继承默认值；计数仅存内存，服务重启清零。Token 按输入加输出预占，收到实际用量后修正。</p><div className="admin-form-grid">{rateFields.map(([key, label, fallback]) => <TextField key={key} label={label} type="number" min="1" step="1" max={key.startsWith('tokens') ? 1000000000 : 10000} value={rates[key]} placeholder={`默认 ${fallback}`} onChange={e => setRates(old => ({ ...old, [key]: e.target.value }))} />)}</div><TextField label="策略修改原因" value={reason} onChange={e => setReason(e.target.value)} maxLength={500} /><Button variant="primary" busy={busy} disabled={invalidRates || reason.trim().length < 3} onClick={() => void save()}>保存用户策略</Button></div></Card>
    <Card title="调整长期额度"><div className="stack"><TextField label="调整点数（正数增加，负数扣减）" type="number" step="1" value={amount} onChange={e => setAmount(e.target.value)} hint="按差额记账，不改写历史消费；扣减不能占用已预留额度。" /><TextField label="额度调整原因" value={creditReason} onChange={e => setCreditReason(e.target.value)} maxLength={500} /><Button variant="primary" disabled={busy || !Number.isSafeInteger(Number(amount)) || Number(amount) === 0 || creditReason.trim().length < 3} onClick={() => setConfirm(true)}>核对额度调整</Button></div></Card>
    {error && <Notice tone="error" role="alert">{error}</Notice>}{success && <Notice role="status">{success}</Notice>}
    <Dialog open={confirm} title="确认调整长期额度" onClose={() => setConfirm(false)} footer={<><Button data-dialog-initial-focus onClick={() => setConfirm(false)}>取消</Button><Button variant="primary" busy={busy} onClick={() => void credit()}>确认调整</Button></>}><p>用户：{value.username}</p><p>调整：{Number(amount) > 0 ? '+' : ''}{number(Number(amount))} 点</p><p>原因：{creditReason}</p><Notice>保存后立即生效，并记录操作人、原因和调整前后余额。</Notice></Dialog>
  </div>
}
