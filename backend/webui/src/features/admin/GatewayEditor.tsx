import { useState } from 'react'
import { Badge, Button, Card, Notice, SelectField, TextField } from '../../components/ui'
import type { Gateway, Model, Provider } from './types'

export function GatewayEditor({ initial, save, test, busy }: { initial: Gateway; save: (g: Gateway, reason: string) => Promise<void>; test: (id: string) => Promise<string>; busy: boolean }) {
  const [g, setG] = useState(() => structuredClone(initial))
  const [reason, setReason] = useState('')
  const [newProvider, setNewProvider] = useState('')
  const [newModel, setNewModel] = useState('')
  const [probe, setProbe] = useState<Record<string, string>>({})
  const [testing, setTesting] = useState<string | null>(null)
  const [error, setError] = useState('')
  const dirty = JSON.stringify(g) !== JSON.stringify(initial)
  const provider = (id: string, patch: Partial<Provider>) => setG(old => ({ ...old, providers: { ...old.providers, [id]: { ...old.providers[id], ...patch } } }))
  const model = (id: string, patch: Partial<Model>) => setG(old => ({ ...old, models: { ...old.models, [id]: { ...old.models[id], ...patch } } }))
  const addProvider = () => {
    const id = newProvider.trim()
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(id) || g.providers[id]) { setError('Provider ID 格式无效或已经存在。'); return }
    provider(id, { name: id, type: 'deepseek', endpoint: 'https://api.deepseek.com', api_key: '', has_key: false, disabled: false }); setNewProvider(''); setError('')
  }
  const addModel = () => {
    const id = newModel.trim()
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(id) || g.models[id] || !Object.keys(g.providers).length) { setError('请填写唯一模型别名，并先添加 provider。'); return }
    model(id, { provider_id: Object.keys(g.providers)[0], model: '', disabled: false, max_output_tokens: 4096, pricing: { version: `manual-${new Date().toISOString().slice(0, 10)}`, input_nano_usd_per_token: 0, cached_input_nano_usd_per_token: 0, output_nano_usd_per_token: 0 } }); setNewModel(''); setError('')
  }
  return <div className="stack">
    <Notice>配置保存后对新请求即时生效；进行中的请求继续按原费率结算。1 美元模型成本 = 500,000 点。密钥只写入后端，留空保留原值；修改端点必须重新提供密钥。</Notice>
    <Card title="默认额度与路由"><div className="admin-form-grid"><TextField label="每日免费额度（点）" type="number" min="0" max="1000000000" value={g.daily_quota_points} onChange={e => setG({ ...g, daily_quota_points: Number(e.target.value) })} /><TextField label="每日请求上限" type="number" min="0" value={g.daily_requests} onChange={e => setG({ ...g, daily_requests: Number(e.target.value) })} /><SelectField label="默认模型" value={g.default_model} onChange={e => setG({ ...g, default_model: e.target.value })}>{Object.keys(g.models).map(id => <option key={id}>{id}</option>)}</SelectField></div></Card>
    <h2>Providers</h2>
    {Object.entries(g.providers).map(([id, p]) => <Card key={id} title={p.name || id}><div className="stack"><div className="row wrap"><Badge>{id}</Badge><Badge tone={p.disabled ? 'warning' : 'success'}>{p.disabled ? '停用' : '启用'}</Badge><Badge>{p.has_key ? '已设置密钥' : '待设置密钥'}</Badge></div><div className="admin-form-grid"><TextField label="显示名称" value={p.name} onChange={e => provider(id, { name: e.target.value })} /><SelectField label="API 协议" value={p.type} onChange={e => provider(id, { type: e.target.value })}><option value="deepseek">DeepSeek</option><option value="openai">OpenAI / OpenAI compatible</option></SelectField><TextField label="HTTPS API 基础地址" value={p.endpoint} onChange={e => provider(id, { endpoint: e.target.value })} placeholder="https://api.openai.com/v1" /><TextField label="API 密钥" type="password" autoComplete="new-password" value={p.api_key ?? ''} placeholder={p.has_key ? '留空保留已有密钥' : '输入 provider 密钥'} onChange={e => provider(id, { api_key: e.target.value })} /><TextField label="HTTP 代理地址（可选）" value={p.proxy_url ?? ''} placeholder="http://proxy.example.com:3128" onChange={e => provider(id, { proxy_url: e.target.value })} /><TextField label="代理用户名（可选）" autoComplete="off" value={p.proxy_username ?? ''} onChange={e => provider(id, { proxy_username: e.target.value })} /><TextField label="代理密码" type="password" autoComplete="new-password" value={p.proxy_password ?? ''} placeholder={p.has_proxy_password ? '留空保留已有密码' : '无需认证时留空'} onChange={e => provider(id, { proxy_password: e.target.value })} /></div><p className="secondary">支持 HTTP / HTTPS 代理；地址留空使用默认网络连接。代理密码留空保留；修改代理地址或用户名时需重新填写密码，清空用户名可移除认证。保存后新请求及连通性检查立即使用此配置，代理失败不会回退直连。</p><label className="row"><input type="checkbox" checked={p.disabled} onChange={e => provider(id, { disabled: e.target.checked })} />停用此 provider 的全部模型</label><div className="row wrap"><Button disabled={dirty || busy || !!testing} onClick={async () => { setTesting(id); try { setProbe({ ...probe, [id]: await test(id) }) } catch { setProbe({ ...probe, [id]: '连通性检查失败，请重试。' }) } finally { setTesting(null) } }}>{testing === id ? '检查中…' : '检查已保存配置'}</Button><Button variant="danger" disabled={Object.values(g.models).some(m => m.provider_id === id)} onClick={() => setG(old => { const providers = { ...old.providers }; delete providers[id]; return { ...old, providers } })}>移除 provider</Button></div>{probe[id] && <p role="status">{probe[id]}</p>}</div></Card>)}
    <div className="row wrap"><TextField label="新增 Provider ID" value={newProvider} onChange={e => setNewProvider(e.target.value)} placeholder="openai" /><Button onClick={addProvider}>添加 provider</Button></div>
    <h2>模型与费率</h2>
    <p className="secondary">费率按美元 / 百万 token 输入；输入费率是非缓存部分，缓存命中单独计费。请填入实际模型官方费率，不会自动套用其他模型价格。</p>
    {Object.entries(g.models).map(([id, m]) => <Card key={id} title={id}><div className="stack"><div className="admin-form-grid"><SelectField label="Provider" value={m.provider_id} onChange={e => model(id, { provider_id: e.target.value })}>{Object.keys(g.providers).map(p => <option key={p}>{p}</option>)}</SelectField><TextField label="上游模型 ID" value={m.model} onChange={e => model(id, { model: e.target.value })} /><TextField label="最大输出 token" type="number" min="1" max="32768" value={m.max_output_tokens} onChange={e => model(id, { max_output_tokens: Number(e.target.value) })} /><TextField label="费率版本" value={m.pricing.version ?? ''} onChange={e => model(id, { pricing: { ...m.pricing, version: e.target.value } })} />{([['input_nano_usd_per_token', '输入'], ['cached_input_nano_usd_per_token', '缓存命中'], ['output_nano_usd_per_token', '输出']] as const).map(([key, name]) => <Rate key={key} name={name} rate={m.pricing[key]} change={v => model(id, { pricing: { ...m.pricing, [key]: v } })} />)}</div><label className="row"><input type="checkbox" checked={m.disabled} onChange={e => model(id, { disabled: e.target.checked })} />停用模型</label><Button variant="danger" disabled={id === g.default_model} onClick={() => setG(old => { const models = { ...old.models }; delete models[id]; return { ...old, models } })}>移除模型</Button></div></Card>)}
    <div className="row wrap"><TextField label="新增模型别名" value={newModel} onChange={e => setNewModel(e.target.value)} placeholder="deepseek-chat" /><Button onClick={addModel}>添加模型</Button></div>
    {error && <Notice tone="error">{error}</Notice>}
    <Card title="保存配置"><div className="stack"><Badge tone={dirty ? 'warning' : 'neutral'}>{dirty ? '有未保存更改' : `已保存 · 版本 ${initial.revision}`}</Badge><TextField label="操作原因" value={reason} onChange={e => setReason(e.target.value)} maxLength={500} placeholder="例如：更新 DeepSeek 费率" /><Button variant="primary" busy={busy} disabled={!dirty || reason.trim().length < 3} onClick={() => void save(g, reason)}>保存并立即应用</Button></div></Card>
  </div>
}
function Rate({ name, rate, change }: { name: string; rate: number; change: (n: number) => void }) { return <TextField label={`${name}（美元 / 百万 token）`} type="number" step="0.001" min="0" value={rate / 1000} onChange={e => change(Math.round(Number(e.target.value) * 1000))} /> }
