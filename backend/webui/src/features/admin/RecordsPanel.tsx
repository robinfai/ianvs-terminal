import { useEffect, useState } from 'react'
import type { DataApiClient } from '../../api/client'
import { Badge, Button, Card, EmptyState, Notice, SelectField, TextField } from '../../components/ui'
import type { Gateway, RecordRow, Records, Summary } from './types'
import { date, number, points } from './types'
import { adminError } from './UsersPanel'
const today = () => new Date().toISOString().slice(0, 10)
const weekAgo = () => new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10)
export function RecordsPanel({ client, gateway, userID }: { client: DataApiClient; gateway: Gateway; userID: string }) {
  const [filters, setFilters] = useState({ from: weekAgo(), to: today(), user_id: userID, model: '', provider_id: '', status: '' })
  const [applied, setApplied] = useState(filters)
  const [data, setData] = useState<RecordRow[]>([]); const [summary, setSummary] = useState<Summary | null>(null); const [next, setNext] = useState('')
  const [busy, setBusy] = useState(false); const [error, setError] = useState('')
  const load = async (before = '') => {
    setBusy(true); setError('')
    try { const result = await client.admin<Records>('requests', { query: { ...applied, before } }); setData(old => before ? [...old, ...result.data] : result.data); setSummary(result.summary); setNext(result.next_cursor) } catch (e) { setError(adminError(e)); if (!before) { setData([]); setSummary(null); setNext('') } } finally { setBusy(false) }
  }
  useEffect(() => { void load() }, [applied])
  const exportCSV = () => {
    const escape = (value: string | number) => '"' + String(value).replace(/^[=+@-]/, "'$&").replace(/"/g, '""') + '"'
    const rows: (string | number)[][] = [['请求 ID', '用户 ID', '用户名', '时间', 'Provider', '模型', '状态', '输入 token', '缓存 token', '输出 token', '扣费点数', '费率版本']]
    for (const { entry: e, user_id, username } of data) rows.push([e.id, user_id, username, e.created_at, e.provider, e.model, e.status, e.usage.input_tokens, e.usage.cached_input_tokens, e.usage.output_tokens, e.usage.spent_nano_usd / 2000, e.pricing_snapshot.version ?? ''])
    const url = URL.createObjectURL(new Blob(['\ufeff' + rows.map(row => row.map(escape).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a'); a.href = url; a.download = `trail-ai-usage-${applied.from}-${applied.to}.csv`; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  return <div className="stack"><Card title="查询使用记录"><form className="stack" onSubmit={e => { e.preventDefault(); setApplied({ ...filters }) }}><div className="admin-form-grid"><TextField label="开始日期（UTC）" type="date" value={filters.from} onChange={e => setFilters({ ...filters, from: e.target.value })} /><TextField label="结束日期（UTC）" type="date" value={filters.to} onChange={e => setFilters({ ...filters, to: e.target.value })} /><TextField label="用户 ID（留空查全部）" value={filters.user_id} onChange={e => setFilters({ ...filters, user_id: e.target.value })} /><SelectField label="模型" value={filters.model} onChange={e => setFilters({ ...filters, model: e.target.value })}><option value="">全部模型</option>{Object.keys(gateway.models).map(id => <option key={id}>{id}</option>)}</SelectField><SelectField label="Provider" value={filters.provider_id} onChange={e => setFilters({ ...filters, provider_id: e.target.value })}><option value="">全部</option>{Object.entries(gateway.providers).map(([id,p]) => <option key={id} value={id}>{p.name || id}</option>)}</SelectField><SelectField label="结算状态" value={filters.status} onChange={e => setFilters({ ...filters, status: e.target.value })}><option value="">全部</option><option value="settled">已结算</option><option value="pending">待结算 / 预占</option><option value="refunded">已释放预占</option></SelectField></div><p className="secondary">每次最多查询 90 天。汇总覆盖筛选范围内全部记录，列表每页 50 条。记录不包含对话内容。</p><div className="row wrap"><Button variant="primary" type="submit" busy={busy}>查询</Button><Button disabled={busy} onClick={() => void load()}>刷新</Button><Button disabled={!data.length} onClick={exportCSV}>导出已加载 {data.length} 条 CSV</Button></div></form></Card>
    {error && <Notice tone="error" role="alert">{error}</Notice>}
    {summary && <div className="metric-grid"><Card title="请求数"><p className="stat-value">{number(summary.requests)}</p></Card><Card title="已扣额度"><p className="stat-value">{points(summary.spent_nano_usd)} 点</p><p className="secondary">预占 {points(summary.pending_reserved_nano_usd)} 点</p></Card><Card title="输入 / 缓存 / 输出 token"><p>{number(summary.input_tokens)} / {number(summary.cached_input_tokens)} / {number(summary.output_tokens)}</p></Card></div>}
    <div className="stack">{data.map(({ entry: e, user_id, username }) => <Card key={`${user_id}-${e.id}`} title={`${username || user_id} · ${e.model}`}><div className="stack"><div className="row wrap"><Badge>{e.provider_id || e.provider}</Badge><Badge tone={e.status === 'settled' ? 'success' : e.status === 'pending' ? 'warning' : 'neutral'}>{e.status === 'settled' ? '已结算' : e.status === 'pending' ? '待结算' : '已释放预占'}</Badge><span className="secondary">{date(e.created_at)}</span></div><p>扣费 <strong>{points(e.usage.spent_nano_usd)} 点</strong>{e.status === 'pending' ? ` · 预占 ${points(e.reserved_nano_usd)} 点` : ''}</p><p>输入 {number(e.usage.input_tokens)} · 缓存 {number(e.usage.cached_input_tokens)} · 输出 {number(e.usage.output_tokens)} token</p><details><summary>请求与费率快照</summary><div className="stack"><p className="break-word">请求 ID：{e.id}</p><p className="break-word">用户 ID：{user_id}</p><p>上游模型：{e.upstream_model}</p><p>费率版本：{e.pricing_snapshot.version || '未标记'}</p><p>美元 / 百万 token：输入 {e.pricing_snapshot.input_nano_usd_per_token / 1000}；缓存 {e.pricing_snapshot.cached_input_nano_usd_per_token / 1000}；输出 {e.pricing_snapshot.output_nano_usd_per_token / 1000}</p>{e.settled_at && <p>结算时间：{date(e.settled_at)}</p>}</div></details></div></Card>)}</div>
    {!data.length && !busy && !error && <EmptyState title="该范围暂无使用记录" />}{busy && <p role="status">正在加载记录…</p>}{next && <Button disabled={busy} onClick={() => void load(next)}>加载更多记录</Button>}
  </div>
}
