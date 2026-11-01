import { useEffect, useState } from 'react'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Card, EmptyState, Notice } from '../components/ui'
import { GatewayEditor } from '../features/admin/GatewayEditor'
import { UsersPanel, adminError } from '../features/admin/UsersPanel'
import { RecordsPanel } from '../features/admin/RecordsPanel'
import type { Audit, Gateway, Page } from '../features/admin/types'
import { date } from '../features/admin/types'

type Tab = 'gateway' | 'users' | 'records' | 'audit'
const tabs: { id: Tab; label: string }[] = [{ id: 'gateway', label: 'Providers 与模型' }, { id: 'users', label: '用户与额度' }, { id: 'records', label: '使用记录' }, { id: 'audit', label: '管理审计' }]
export function AdminPage() {
  const { client, isAdmin } = useSession()
  const [tab, setTab] = useState<Tab>('gateway'); const [gateway, setGateway] = useState<Gateway | null>(null)
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [message, setMessage] = useState('')
  const [recordUser, setRecordUser] = useState(''); const [audit, setAudit] = useState<Audit[]>([]); const [auditNext, setAuditNext] = useState('')
  const load = async () => { if (!client || !isAdmin) return; setBusy(true); setError(''); try { setGateway(await client.admin<Gateway>('gateway')) } catch (e) { setError(adminError(e)) } finally { setBusy(false) } }
  useEffect(() => { void load() }, [client, isAdmin])
  const loadAudit = async (before = '') => { if (!client) return; setBusy(true); setError(''); try { const page = await client.admin<Page<Audit>>('audit', { query: { before } }); setAudit(old => before ? [...old, ...page.data] : page.data); setAuditNext(page.next_cursor) } catch (e) { setError(adminError(e)) } finally { setBusy(false) } }
  if (!isAdmin || !client) return <EmptyState title="没有管理权限" description="此页面仅对服务器指定的管理员开放。普通账户不能读取或修改其他用户的额度。" />
  return <div className="stack page-stack"><div className="page-heading"><p className="eyebrow">AI Gateway</p><h1>AI 网关管理</h1><p className="secondary">管理 provider、模型费率、用户额度和请求结算。配置与额度变更均记录审计。</p></div><div className="row wrap"><Badge tone="success">管理员</Badge><Badge>{gateway ? `配置版本 ${gateway.revision}` : '正在载入'}</Badge><Button disabled={busy} onClick={() => void load()}>刷新配置</Button></div><nav className="preview-tabs row wrap" aria-label="AI 网关管理">{tabs.map(t => <Button key={t.id} variant={tab === t.id ? 'primary' : 'secondary'} aria-pressed={tab === t.id} onClick={() => { setTab(t.id); setMessage(''); if (t.id === 'audit') void loadAudit() }}>{t.label}</Button>)}</nav>{error && <Notice tone="error" role="alert">{error}</Notice>}{message && <Notice role="status">{message}</Notice>}
    {gateway && tab === 'gateway' && <GatewayEditor key={gateway.revision} initial={gateway} busy={busy} save={async (g, reason) => { setBusy(true); setError(''); setMessage(''); try { setGateway(await client.admin<Gateway>('gateway', { method: 'PUT', body: { gateway: g, reason } })); setMessage('配置已保存，新请求立即使用新配置。') } catch (e) { setError(adminError(e)) } finally { setBusy(false) } }} test={async id => { const result = await client.admin<{ ok: boolean; status: number; latency_ms: number }>(`providers/${encodeURIComponent(id)}/test`, { method: 'POST' }); return `${result.ok ? '连接正常' : '连接未通过'} · HTTP ${result.status || '无响应'} · ${result.latency_ms} ms` }} />}
    {gateway && tab === 'users' && <UsersPanel client={client} gateway={gateway} viewRecords={id => { setRecordUser(id); setTab('records') }} />}
    {gateway && tab === 'records' && <RecordsPanel key={recordUser} client={client} gateway={gateway} userID={recordUser} />}
    {tab === 'audit' && <div className="stack"><Button disabled={busy} onClick={() => void loadAudit()}>刷新审计</Button>{audit.map(a => <Card key={a.id} title={({ 'gateway.update': '网关配置更新', 'user.policy': '用户额度策略更新', 'user.credit': '长期额度调整' } as Record<string, string>)[a.action] ?? a.action}><div className="stack"><p>{date(a.created_at)} · {a.reason}</p><p className="secondary break-word">操作人：{a.actor_id}</p><p className="secondary break-word">对象：{a.target}</p>{a.details != null && <details><summary>变更详情</summary><pre className="admin-json">{JSON.stringify(a.details, null, 2)}</pre></details>}</div></Card>)}{!busy && !audit.length && <EmptyState title="暂无管理操作记录" />}{auditNext && <Button disabled={busy} onClick={() => void loadAudit(auditNext)}>加载更多审计</Button>}</div>}
    {busy && !gateway && <p role="status">正在加载管理配置…</p>}
  </div>
}
